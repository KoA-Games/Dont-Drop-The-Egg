--!strict

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local EGG_GROUP = "Eggs"
local CHARACTER_GROUP = "Characters"
local BASKET_COLLIDER_GROUP = "EggBasket"
local BASKET_NAME = "Basket"
local EGG_NAME = "BasketEgg"
local COLLISION_SHELL_NAME = "EggCollisionShell"
local EGG_COUNT = 5
local EGG_SPAWN_DELAY = 0.1
local VERTICAL_ATTACHMENT_NAME = "VerticalStabilizerAttachment"
local VERTICAL_FORCE_NAME = "VerticalStabilizerForce"

-- Raise/lower the egg here relative to Basket.Bottom.
local EGG_BOTTOM_CLEARANCE = 0.05
local EGG_COLLIDER_DIAMETER = 0.5
local EGG_PHYSICAL_PROPERTIES = PhysicalProperties.new(0.25, 0.45, 0.02, 50, 100)

-- Five non-overlapping centers inside the basket. X is left/right and Y is
-- Basket.Bottom's local Z (front/back). Keep centers at least one collider
-- diameter apart when tuning these values.
local EGG_SPAWN_OFFSETS: { Vector2 } = {
	Vector2.new(0, 0),
	Vector2.new(-0.55, -0.28),
	Vector2.new(0.55, -0.28),
	Vector2.new(-0.55, 0.28),
	Vector2.new(0.55, 0.28),
}

-- The visible walls are only 0.18 studs thick. A character can move farther
-- than that between physics steps, so loose eggs can tunnel through them.
-- These values affect only the invisible egg-only collision shell.
local SHELL_WALL_THICKNESS = 0.42
local SHELL_WALL_HEIGHT = 0.82
local SHELL_WALL_Y_OFFSET = 0.085
-- Keep the top surface exactly aligned with the visible basket floor, but make
-- the invisible egg-only floor deep enough that a newly network-owned 0.5-stud
-- collider cannot tunnel through it during character spawn/settling.
local SHELL_FLOOR_THICKNESS = 1.20

local activeEggs: { [Model]: { Model } } = {}

local FORBIDDEN_PHYSICS_CLASSES: { [string]: boolean } = {
	AlignPosition = true,
	AlignOrientation = true,
	BodyPosition = true,
	BodyVelocity = true,
	BodyAngularVelocity = true,
	BodyGyro = true,
	BodyForce = true,
	RocketPropulsion = true,
	LinearVelocity = true,
	AngularVelocity = true,
	VectorForce = true,
	Torque = true,
}

local function removeHybridExperimentRemnants()
	local staleReplicatedConfig = ReplicatedStorage:FindFirstChild("EggTestConfig")
	if staleReplicatedConfig then
		staleReplicatedConfig:Destroy()
	end
	ReplicatedStorage:SetAttribute("EggTestMode", nil)

	local staleTemplates = ReplicatedStorage:FindFirstChild("EggTemplates")
	if staleTemplates then
		staleTemplates:Destroy()
	end

	local staleStarterController =
		StarterPlayer.StarterPlayerScripts:FindFirstChild("HybridEggController")
	if staleStarterController then
		staleStarterController:Destroy()
	end
end

local function ensureCollisionGroup(name: string)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end

local function configureCollisionGroups()
	ensureCollisionGroup(EGG_GROUP)
	ensureCollisionGroup(CHARACTER_GROUP)
	ensureCollisionGroup(BASKET_COLLIDER_GROUP)

	PhysicsService:CollisionGroupSetCollidable(EGG_GROUP, CHARACTER_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(EGG_GROUP, EGG_GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(EGG_GROUP, BASKET_COLLIDER_GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(EGG_GROUP, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(CHARACTER_GROUP, BASKET_COLLIDER_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(BASKET_COLLIDER_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(BASKET_COLLIDER_GROUP, BASKET_COLLIDER_GROUP, false)
end

local function applyCharacterCollisionGroup(character: Model)
	local function apply(instance: Instance)
		if instance:IsA("BasePart") then
			local basket = character:FindFirstChild(BASKET_NAME)
			if basket and instance:IsDescendantOf(basket) then
				return
			end
			instance.CollisionGroup = CHARACTER_GROUP
		end
	end

	for _, descendant in character:GetDescendants() do
		apply(descendant)
	end

	character.DescendantAdded:Connect(apply)
end

local function configureBasketCollider(part: Part)
	part.Transparency = 1
	part.Anchored = false
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CollisionGroup = BASKET_COLLIDER_GROUP
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.65, 0, 100, 100)
end

local function addBasketCollisionShell(basket: Model, bottom: BasePart): Model
	local existing = basket:FindFirstChild(COLLISION_SHELL_NAME)
	if existing then
		existing:Destroy()
	end

	local shell = Instance.new("Model")
	shell.Name = COLLISION_SHELL_NAME

	for _, name in { "Bottom", "FrontWall", "BackWall", "LeftWall", "RightWall" } do
		local visiblePart = basket:FindFirstChild(name)
		if visiblePart and visiblePart:IsA("BasePart") then
			local collisionPart = Instance.new("Part")
			collisionPart.Name = name .. "Collider"

			if name == "Bottom" then
				-- Keep the collision surface aligned with the visible floor top.
				collisionPart.Size = Vector3.new(
					visiblePart.Size.X,
					SHELL_FLOOR_THICKNESS,
					visiblePart.Size.Z
				)
				local downwardOffset = (SHELL_FLOOR_THICKNESS - visiblePart.Size.Y) * 0.5
				collisionPart.CFrame = visiblePart.CFrame * CFrame.new(0, -downwardOffset, 0)
			elseif name == "FrontWall" or name == "BackWall" then
				collisionPart.Size = Vector3.new(
					visiblePart.Size.X + SHELL_WALL_THICKNESS,
					SHELL_WALL_HEIGHT,
					SHELL_WALL_THICKNESS
				)
				collisionPart.CFrame = visiblePart.CFrame * CFrame.new(0, SHELL_WALL_Y_OFFSET, 0)
			else
				collisionPart.Size = Vector3.new(
					SHELL_WALL_THICKNESS,
					SHELL_WALL_HEIGHT,
					visiblePart.Size.Z + SHELL_WALL_THICKNESS
				)
				collisionPart.CFrame = visiblePart.CFrame * CFrame.new(0, SHELL_WALL_Y_OFFSET, 0)
			end

			configureBasketCollider(collisionPart)
			collisionPart.Parent = shell

			local weld = Instance.new("WeldConstraint")
			weld.Name = "BasketColliderWeld"
			weld.Part0 = bottom
			weld.Part1 = collisionPart
			weld.Parent = collisionPart
		end
	end

	shell.Parent = basket
	return shell
end

local function cleanUpEggs(character: Model)
	local eggs = activeEggs[character]
	activeEggs[character] = nil
	if eggs then
		for _, egg in eggs do
			if egg.Parent then
				egg:Destroy()
			end
		end
	end
end

local function removeStaleRuntimeEggs()
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and (child.Name == EGG_NAME or child.Name:match("^" .. EGG_NAME .. "_%d+$")) then
			child:Destroy()
		end
	end
end

local function configureCleanEggAssembly(egg: Model): (Part?, boolean)
	local collider = egg:FindFirstChild("Collider")
	local visual = egg:FindFirstChild("Visual")
	if not collider or not collider:IsA("Part") then
		return nil, false
	end
	if not visual or not visual:IsA("BasePart") then
		return nil, false
	end

	local forbiddenMovementRemoved = false

	-- A physical egg needs exactly one collider and one massless visual. Remove
	-- any old mover, force, extra constraint, script, or extra physical part
	-- that could fight Roblox's solver.
	for _, descendant in egg:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			forbiddenMovementRemoved = true
			descendant:Destroy()
		elseif FORBIDDEN_PHYSICS_CLASSES[descendant.ClassName] then
			forbiddenMovementRemoved = true
			descendant:Destroy()
		elseif descendant:IsA("BasePart") and descendant ~= collider and descendant ~= visual then
			forbiddenMovementRemoved = true
			descendant:Destroy()
		elseif descendant:IsA("WeldConstraint") and descendant.Name ~= "VisualWeld" then
			forbiddenMovementRemoved = true
			descendant:Destroy()
		end
	end

	collider.Shape = Enum.PartType.Ball
	collider.Size = Vector3.one * EGG_COLLIDER_DIAMETER
	collider.Anchored = false
	collider.CanCollide = true
	collider.CanTouch = true
	collider.CanQuery = true
	collider.Massless = false
	collider.CollisionGroup = EGG_GROUP
	collider.CustomPhysicalProperties = EGG_PHYSICAL_PROPERTIES

	visual.Anchored = false
	visual.CanCollide = false
	visual.CanTouch = false
	visual.CanQuery = false
	visual.Massless = true
	visual.CollisionGroup = EGG_GROUP

	local existingVisualWeld = visual:FindFirstChild("VisualWeld")
	local visualWeld: WeldConstraint
	if existingVisualWeld and existingVisualWeld:IsA("WeldConstraint") then
		visualWeld = existingVisualWeld
	else
		if existingVisualWeld then
			existingVisualWeld:Destroy()
		end
		visualWeld = Instance.new("WeldConstraint")
		visualWeld.Name = "VisualWeld"
		visualWeld.Parent = visual
	end
	visualWeld.Part0 = collider
	visualWeld.Part1 = visual

	egg.PrimaryPart = collider
	return collider, forbiddenMovementRemoved
end

local function addVerticalStabilizerForce(collider: Part)
	local oldAttachment = collider:FindFirstChild(VERTICAL_ATTACHMENT_NAME)
	if oldAttachment then
		oldAttachment:Destroy()
	end
	local oldForce = collider:FindFirstChild(VERTICAL_FORCE_NAME)
	if oldForce then
		oldForce:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = VERTICAL_ATTACHMENT_NAME
	attachment.Position = Vector3.zero
	attachment.Parent = collider

	local verticalForce = Instance.new("VectorForce")
	verticalForce.Name = VERTICAL_FORCE_NAME
	verticalForce.Attachment0 = attachment
	verticalForce.RelativeTo = Enum.ActuatorRelativeTo.World
	verticalForce.ApplyAtCenterOfMass = true
	verticalForce.Force = Vector3.zero
	verticalForce.Enabled = false
	verticalForce.Parent = collider
end

local function getAssemblyPartCount(collider: BasePart): number
	local connected: { [BasePart]: boolean } = { [collider] = true }
	for _, part in collider:GetConnectedParts(true) do
		connected[part] = true
	end

	local count = 0
	for _ in connected do
		count += 1
	end
	return count
end

local function spawnEggsInBasket(character: Model)
	cleanUpEggs(character)

	local basket = character:WaitForChild(BASKET_NAME, 15)
	if not basket or not basket:IsA("Model") then
		warn("EggBasketSpawnService: runtime Basket was not available")
		return
	end

	local bottom = basket:FindFirstChild("Bottom")
	if not bottom or not bottom:IsA("BasePart") then
		warn("EggBasketSpawnService: Basket.Bottom was not available")
		return
	end

	addBasketCollisionShell(basket, bottom)

	local template = ServerStorage:FindFirstChild("EggPhysicsTemplate")
	if not template or not template:IsA("Model") then
		warn("EggBasketSpawnService: EggPhysicsTemplate was not available")
		return
	end

	local networkOwner = Players:GetPlayerFromCharacter(character)
	local eggs: { Model } = {}
	activeEggs[character] = eggs

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			cleanUpEggs(character)
		end)
	end

	basket.Destroying:Once(function()
		cleanUpEggs(character)
	end)
	character.Destroying:Once(function()
		cleanUpEggs(character)
	end)

	for index = 1, EGG_COUNT do
		local offset = EGG_SPAWN_OFFSETS[index]
		-- A death, respawn, basket removal, or second spawn request invalidates
		-- this set immediately, so the delayed loop cannot create duplicates.
		if activeEggs[character] ~= eggs or not character.Parent or not basket.Parent then
			break
		end

		local egg = template:Clone()
		egg.Name = EGG_NAME .. "_" .. tostring(index)
		if networkOwner then
			egg:SetAttribute("EggOwnerUserId", networkOwner.UserId)
		end
		egg:SetAttribute("EggIndex", index)

		local collider, forbiddenMovementRemoved = configureCleanEggAssembly(egg)
		if not collider then
			egg:Destroy()
			cleanUpEggs(character)
			warn("EggBasketSpawnService: clean Collider/Visual assembly was not available")
			return
		end
		addVerticalStabilizerForce(collider)

		local spawnHeight = bottom.Size.Y * 0.5 + collider.Size.Y * 0.5 + EGG_BOTTOM_CLEARANCE
		-- This is the egg's only scripted movement, performed before it enters
		-- Workspace. From this point onward the basket and Roblox physics move it.
		egg:PivotTo(bottom.CFrame * CFrame.new(offset.X, spawnHeight, offset.Y))
		egg.Parent = Workspace
		table.insert(eggs, egg)

		local canSetOwnership, ownershipReason = collider:CanSetNetworkOwnership()
		local ownershipAssigned = false
		if canSetOwnership and networkOwner then
			local assigned, assignmentError = pcall(function()
				collider:SetNetworkOwner(networkOwner)
			end)
			ownershipAssigned = assigned
			if not assigned then
				ownershipReason = tostring(assignmentError)
			end
		end

		local actualOwner = collider:GetNetworkOwner()
		print(
			"[EggPhysics] NetworkOwner",
			"egg=" .. tostring(index) .. "/" .. tostring(EGG_COUNT),
			"requested=" .. (networkOwner and networkOwner.Name or "none"),
			"canSet=" .. tostring(canSetOwnership),
			"assigned=" .. tostring(ownershipAssigned),
			"actual=" .. (actualOwner and actualOwner.Name or "server"),
			"reason=" .. tostring(ownershipReason or "none")
		)
		print("[EggPhysics] AssemblyPartCount", "egg=" .. tostring(index), getAssemblyPartCount(collider))
		print("[EggPhysics] ForbiddenMovementRemoved", "egg=" .. tostring(index), forbiddenMovementRemoved)

		if index < EGG_COUNT then
			task.wait(EGG_SPAWN_DELAY)
		end
	end

	print("[EggPhysics] ActiveEggCount", #eggs)
	task.delay(1, function()
		if bottom.Parent then
			local upDot = math.clamp(bottom.CFrame.UpVector:Dot(Vector3.yAxis), -1, 1)
			local tiltDegrees = math.deg(math.acos(upDot))
			local localGravity = bottom.CFrame:VectorToObjectSpace(Vector3.new(0, -1, 0))
			print(
				"[EggPhysics] BasketTilt",
				string.format("degrees=%.3f", tiltDegrees),
				string.format("localDownhillX=%.4f", localGravity.X),
				string.format("localDownhillZ=%.4f", localGravity.Z)
			)
		end
	end)

end

local function onCharacterAdded(character: Model)
	applyCharacterCollisionGroup(character)
	task.spawn(spawnEggsInBasket, character)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(cleanUpEggs)

	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

configureCollisionGroups()
removeHybridExperimentRemnants()
removeStaleRuntimeEggs()
print(
	"[EggPhysics] NativeVerticalStabilizer",
	"eggCount=" .. tostring(EGG_COUNT),
	"forcesPrepared=true"
)
Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
