--!strict

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local EGG_GROUP = "Eggs"
local CHARACTER_GROUP = "Characters"
local BASKET_COLLIDER_GROUP = "EggBasket"
local BASKET_NAME = "Basket"
local MOUNT_READY_ATTRIBUTE = "BasketMountReady"
local EGG_NAME = "BasketEgg"
local COLLISION_SHELL_NAME = "EggCollisionShell"
local SELECTED_EGG_COUNT_ATTRIBUTE = "SelectedEggCount"
local REMOTES_FOLDER_NAME = "Remotes"
local SET_EGG_COUNT_REMOTE_NAME = "SetEggCount"
local MIN_EGG_COUNT = 1
local DEFAULT_EGG_COUNT = 5
local MAX_EGG_COUNT = 30
local EGG_SPAWN_DELAY = 0.06
local EGG_REBUILD_DELAY = 0.08
local EGG_INITIAL_MOUNT_SETTLE_DELAY = 0.35
local EGG_POST_SPAWN_SETTLE_DELAY = 0.18
local EGG_SPAWN_LOCK_ATTRIBUTE = "EggSpawnMovementLocked"

-- Raise/lower the egg here relative to Basket.Bottom.
local EGG_BOTTOM_CLEARANCE = 0.015
local EGG_COLLIDER_DIAMETER = 0.43
local EGG_VISUAL_SCALE_FACTOR = 0.86
local EGG_SPAWN_HORIZONTAL_GAP = 0.035
local EGG_SPAWN_WALL_MARGIN = 0.12
local EGG_LAYER_CLEARANCE = 0.008
-- Real loose eggs must be able to roll when the hand-driven basket changes
-- direction. The previous high weighted friction made a settled five-egg layer
-- behave like one stuck cluster. Density and elasticity remain deliberately low.
local EGG_PHYSICAL_PROPERTIES = PhysicalProperties.new(0.25, 0.28, 0.02, 50, 20)

-- Five-part flared collision shell. The lower and upper outer faces remain
-- inside the visible woven silhouette; the values near the upper egg layers
-- provide an effective interior of approximately 2.15 x 1.80 studs.
local SHELL_LOWER_INTERIOR_WIDTH = 1.81
local SHELL_LOWER_INTERIOR_DEPTH = 1.31
local SHELL_UPPER_INTERIOR_WIDTH = 2.30
local SHELL_UPPER_INTERIOR_DEPTH = 1.95
local SHELL_VISIBLE_HEIGHT = 0.82
-- The imported woven floor has real relief/openings. Keep the egg-only floor
-- slightly above that visible surface so the larger egg visual cannot poke
-- through the weave while its spherical collider is resting normally.
local SHELL_FLOOR_VISUAL_GUARD = 0.12
local SHELL_USABLE_HEIGHT = SHELL_VISIBLE_HEIGHT - SHELL_FLOOR_VISUAL_GUARD
local SHELL_WALL_THICKNESS = 0.46
-- Keep the raised top surface stable above the visible weave, and make the
-- invisible egg-only floor deep enough that a newly network-owned collider
-- cannot tunnel through it during character spawn/settling.
local SHELL_FLOOR_THICKNESS = 2.40

local activeEggs: { [Model]: { Model } } = {}
local spawnGeneration: { [Player]: number } = {}
type MovementLockState = {
	generation: number,
	character: Model,
	humanoid: Humanoid,
	originalWalkSpeed: number,
}
local movementLocks: { [Player]: MovementLockState } = {}
local LEGACY_VERTICAL_STABILIZER_NAME = "EggVerticalStabilizer"

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

local function isBrokenEggPrototype(instance: Instance): boolean
	local compactName = instance.Name:lower():gsub("[%s_%-]", "")
	return compactName:sub(1, 9) == "brokenegg"
		or instance:GetAttribute("IsBrokenEgg") == true
		or instance:GetAttribute("IsBrokenEggPrototype") == true
end

local function removeBrokenEggPrototypeRemnants()
	local removalRoots: { Instance } = {}
	local marked: { [Instance]: boolean } = {}
	for _, container in {
		Workspace,
		ServerStorage,
		ReplicatedStorage,
		ServerScriptService,
		StarterPlayer,
	} do
		for _, descendant in container:GetDescendants() do
			if isBrokenEggPrototype(descendant) then
				local ancestorMarked = false
				local ancestor = descendant.Parent
				while ancestor and ancestor ~= container do
					if marked[ancestor] then
						ancestorMarked = true
						break
					end
					ancestor = ancestor.Parent
				end
				if not ancestorMarked then
					marked[descendant] = true
					table.insert(removalRoots, descendant)
				end
			end
		end
	end

	for _, instance in removalRoots do
		if instance.Parent then
			instance:Destroy()
		end
	end
	if #removalRoots > 0 then
		print("[EggCleanup] Removed broken egg prototype remnants", #removalRoots)
	end
end

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

local function removeLegacyEggVerticalStabilizer(container: Instance)
	local legacyScript = container:FindFirstChild(LEGACY_VERTICAL_STABILIZER_NAME)
	if legacyScript then
		legacyScript:Destroy()
		print("[EggPhysics] Removed legacy per-egg vertical stabilizer")
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
	part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.32, 0, 100, 20)
end

local function createShellPart(
	name: string,
	size: Vector3,
	localCFrame: CFrame,
	shell: Model,
	bottom: BasePart
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	configureBasketCollider(part)
	part.CFrame = bottom.CFrame * localCFrame
	part.Parent = shell

	local weld = Instance.new("WeldConstraint")
	weld.Name = "BasketColliderWeld"
	weld.Part0 = bottom
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function frontBackWallLocalCFrame(zSign: number, floorLocalY: number): (CFrame, number)
	local lowerZ = zSign * (SHELL_LOWER_INTERIOR_DEPTH * 0.5 + SHELL_WALL_THICKNESS * 0.5)
	local upperZ = zSign * (SHELL_UPPER_INTERIOR_DEPTH * 0.5 + SHELL_WALL_THICKNESS * 0.5)
	local lowerPoint = Vector3.new(0, floorLocalY, lowerZ)
	local upperPoint = Vector3.new(0, floorLocalY + SHELL_USABLE_HEIGHT, upperZ)
	local yAxis = (upperPoint - lowerPoint).Unit
	local xAxis = Vector3.xAxis
	local zAxis = xAxis:Cross(yAxis).Unit
	return CFrame.fromMatrix((lowerPoint + upperPoint) * 0.5, xAxis, yAxis, zAxis),
		(upperPoint - lowerPoint).Magnitude
end

local function leftRightWallLocalCFrame(xSign: number, floorLocalY: number): (CFrame, number)
	local lowerX = xSign * (SHELL_LOWER_INTERIOR_WIDTH * 0.5 + SHELL_WALL_THICKNESS * 0.5)
	local upperX = xSign * (SHELL_UPPER_INTERIOR_WIDTH * 0.5 + SHELL_WALL_THICKNESS * 0.5)
	local lowerPoint = Vector3.new(lowerX, floorLocalY, 0)
	local upperPoint = Vector3.new(upperX, floorLocalY + SHELL_USABLE_HEIGHT, 0)
	local yAxis = (upperPoint - lowerPoint).Unit
	local zAxis = Vector3.zAxis
	local xAxis = yAxis:Cross(zAxis).Unit
	return CFrame.fromMatrix((lowerPoint + upperPoint) * 0.5, xAxis, yAxis, zAxis),
		(upperPoint - lowerPoint).Magnitude
end

local function addBasketCollisionShell(basket: Model, bottom: BasePart): Model
	local existing = basket:FindFirstChild(COLLISION_SHELL_NAME)
	if existing then
		existing:Destroy()
	end

	local shell = Instance.new("Model")
	shell.Name = COLLISION_SHELL_NAME
	shell.Parent = basket
	local floorLocalY = bottom.Size.Y * 0.5 + SHELL_FLOOR_VISUAL_GUARD
	local rimLocalY = floorLocalY + SHELL_USABLE_HEIGHT
	shell:SetAttribute("FloorLocalY", floorLocalY)
	shell:SetAttribute("RimLocalY", rimLocalY)
	shell:SetAttribute("LowerInteriorWidth", SHELL_LOWER_INTERIOR_WIDTH)
	shell:SetAttribute("LowerInteriorDepth", SHELL_LOWER_INTERIOR_DEPTH)
	shell:SetAttribute("UpperInteriorWidth", SHELL_UPPER_INTERIOR_WIDTH)
	shell:SetAttribute("UpperInteriorDepth", SHELL_UPPER_INTERIOR_DEPTH)

	-- The thick floor extends downward only. Its top sits just above the open
	-- woven surface, preventing the egg visual from showing through while
	-- retaining the existing anti-tunnelling protection.
	createShellPart(
		"BottomCollider",
		Vector3.new(
			SHELL_LOWER_INTERIOR_WIDTH + SHELL_WALL_THICKNESS,
			SHELL_FLOOR_THICKNESS,
			SHELL_LOWER_INTERIOR_DEPTH + SHELL_WALL_THICKNESS
		),
		CFrame.new(0, floorLocalY - SHELL_FLOOR_THICKNESS * 0.5, 0),
		shell,
		bottom
	)

	local frontCFrame, frontLength = frontBackWallLocalCFrame(-1, floorLocalY)
	local backCFrame, backLength = frontBackWallLocalCFrame(1, floorLocalY)
	local leftCFrame, leftLength = leftRightWallLocalCFrame(-1, floorLocalY)
	local rightCFrame, rightLength = leftRightWallLocalCFrame(1, floorLocalY)
	-- Keep each rectangular wall span within the narrow lower silhouette. The
	-- perpendicular walls overlap enough that the remaining corner openings are
	-- much smaller than the unchanged 0.43-stud egg collider.
	local collisionWallSpanWidth = SHELL_LOWER_INTERIOR_WIDTH
		+ SHELL_WALL_THICKNESS * 2
	local collisionWallSpanDepth = SHELL_LOWER_INTERIOR_DEPTH
		+ SHELL_WALL_THICKNESS * 2

	createShellPart(
		"FrontWallCollider",
		Vector3.new(collisionWallSpanWidth, frontLength, SHELL_WALL_THICKNESS),
		frontCFrame,
		shell,
		bottom
	)
	createShellPart(
		"BackWallCollider",
		Vector3.new(collisionWallSpanWidth, backLength, SHELL_WALL_THICKNESS),
		backCFrame,
		shell,
		bottom
	)
	createShellPart(
		"LeftWallCollider",
		Vector3.new(SHELL_WALL_THICKNESS, leftLength, collisionWallSpanDepth),
		leftCFrame,
		shell,
		bottom
	)
	createShellPart(
		"RightWallCollider",
		Vector3.new(SHELL_WALL_THICKNESS, rightLength, collisionWallSpanDepth),
		rightCFrame,
		shell,
		bottom
	)
	return shell
end

type SpawnLayout = {
	positions: { Vector3 },
	interiorWidth: number,
	interiorDepth: number,
	interiorHeight: number,
	rimLocalY: number,
	positionsPerLayer: number,
}

local function validateEggCount(value: any): number?
	if typeof(value) ~= "number"
		or value ~= value
		or math.abs(value) == math.huge
		or value % 1 ~= 0
		or value < MIN_EGG_COUNT
		or value > MAX_EGG_COUNT
	then
		return nil
	end
	return value
end

local function getSelectedEggCount(player: Player): number
	local selected = validateEggCount(player:GetAttribute(SELECTED_EGG_COUNT_ATTRIBUTE))
	if selected then
		return selected
	end
	player:SetAttribute(SELECTED_EGG_COUNT_ATTRIBUTE, DEFAULT_EGG_COUNT)
	return DEFAULT_EGG_COUNT
end

local function generateSpawnLayout(
	bottom: BasePart,
	shell: Model,
	requestedCount: number
): SpawnLayout
	local floorLocalY = shell:GetAttribute("FloorLocalY")
	local rimLocalY = shell:GetAttribute("RimLocalY")
	local lowerWidth = shell:GetAttribute("LowerInteriorWidth")
	local lowerDepth = shell:GetAttribute("LowerInteriorDepth")
	local upperWidth = shell:GetAttribute("UpperInteriorWidth")
	local upperDepth = shell:GetAttribute("UpperInteriorDepth")
	if typeof(floorLocalY) ~= "number" then
		floorLocalY = bottom.Size.Y * 0.5 + SHELL_FLOOR_VISUAL_GUARD
	end
	if typeof(rimLocalY) ~= "number" then
		rimLocalY = bottom.Size.Y * 0.5 + SHELL_VISIBLE_HEIGHT
	end
	if typeof(lowerWidth) ~= "number" then
		lowerWidth = SHELL_LOWER_INTERIOR_WIDTH
	end
	if typeof(lowerDepth) ~= "number" then
		lowerDepth = SHELL_LOWER_INTERIOR_DEPTH
	end
	if typeof(upperWidth) ~= "number" then
		upperWidth = SHELL_UPPER_INTERIOR_WIDTH
	end
	if typeof(upperDepth) ~= "number" then
		upperDepth = SHELL_UPPER_INTERIOR_DEPTH
	end

	local typedFloorLocalY = floorLocalY :: number
	local typedRimLocalY = rimLocalY :: number
	local typedLowerWidth = lowerWidth :: number
	local typedLowerDepth = lowerDepth :: number
	local typedUpperWidth = upperWidth :: number
	local typedUpperDepth = upperDepth :: number
	local radius = EGG_COLLIDER_DIAMETER * 0.5
	local horizontalSpacing = EGG_COLLIDER_DIAMETER + EGG_SPAWN_HORIZONTAL_GAP
	local halfCellDiagonal = math.sqrt(2) * horizontalSpacing * 0.5
	local minimumVerticalSeparation = EGG_COLLIDER_DIAMETER * 0.55
	local layerSpacing = math.sqrt(math.max(
		EGG_COLLIDER_DIAMETER ^ 2 - halfCellDiagonal ^ 2,
		minimumVerticalSeparation ^ 2
	)) + EGG_LAYER_CLEARANCE
	local firstCenterY = typedFloorLocalY + radius + EGG_BOTTOM_CLEARANCE
	local firstLayerAlpha = math.clamp(
		(firstCenterY - typedFloorLocalY)
			/ math.max(typedRimLocalY - typedFloorLocalY, 0.001),
		0,
		1
	)
	local firstLayerWidth = typedLowerWidth
		+ (typedUpperWidth - typedLowerWidth) * firstLayerAlpha
	local firstLayerDepth = typedLowerDepth
		+ (typedUpperDepth - typedLowerDepth) * firstLayerAlpha
	local firstLayerSafeWidth = math.max(
		firstLayerWidth - EGG_COLLIDER_DIAMETER - EGG_SPAWN_WALL_MARGIN * 2,
		0
	)
	local firstLayerSafeDepth = math.max(
		firstLayerDepth - EGG_COLLIDER_DIAMETER - EGG_SPAWN_WALL_MARGIN * 2,
		0
	)
	-- Fix the horizontal lattice from the lowest/narrowest layer. Reusing that
	-- lattice above prevents a wider upper layer from changing phase and causing
	-- cross-layer overlap during the sequential 12-6-12 spawn.
	local columns = math.max(1, math.floor(firstLayerSafeWidth / horizontalSpacing) + 1)
	local rows = math.max(1, math.floor(firstLayerSafeDepth / horizontalSpacing) + 1)
	local positions: { Vector3 } = {}
	local layerIndex = 0
	local positionsPerLayer = columns * rows

	while #positions < requestedCount do
		local y = firstCenterY + layerIndex * layerSpacing
		local usedWidth = (columns - 1) * horizontalSpacing
		local usedDepth = (rows - 1) * horizontalSpacing
		local centeredStartX = -usedWidth * 0.5
		local centeredStartZ = -usedDepth * 0.5
		local usePocketLayer = layerIndex % 2 == 1 and columns > 1 and rows > 1
		local layerColumns = if usePocketLayer then columns - 1 else columns
		local layerRows = if usePocketLayer then rows - 1 else rows
		local cellOffset = if usePocketLayer then 0.5 else 0

		for row = 0, layerRows - 1 do
			for column = 0, layerColumns - 1 do
				if #positions >= requestedCount then
					break
				end
				local x = centeredStartX + (column + cellOffset) * horizontalSpacing
				local z = centeredStartZ + (row + cellOffset) * horizontalSpacing
				table.insert(positions, Vector3.new(x, y, z))
			end
		end
		layerIndex += 1
	end

	-- Report the usable opening dimensions. The lower shell is deliberately
	-- narrower and expands continuously to these values at the rim.
	local effectiveHeightAlpha = 1
	local effectiveInteriorWidth = typedLowerWidth
		+ (typedUpperWidth - typedLowerWidth) * effectiveHeightAlpha
	local effectiveInteriorDepth = typedLowerDepth
		+ (typedUpperDepth - typedLowerDepth) * effectiveHeightAlpha

	return {
		positions = positions,
		interiorWidth = effectiveInteriorWidth,
		interiorDepth = effectiveInteriorDepth,
		interiorHeight = math.max(typedRimLocalY - typedFloorLocalY, 0),
		rimLocalY = typedRimLocalY,
		positionsPerLayer = positionsPerLayer,
	}
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

local function cleanUpOwnedWorkspaceEggs(player: Player)
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model")
			and child:GetAttribute("IsBasketEgg") == true
			and child:GetAttribute("OwnerUserId") == player.UserId
		then
			child:Destroy()
		end
	end
end

local function invalidatePlayerSpawn(player: Player): number
	local generation = (spawnGeneration[player] or 0) + 1
	spawnGeneration[player] = generation
	return generation
end

local function releaseSpawnMovementLock(player: Player, generation: number?)
	local state = movementLocks[player]
	if not state or (generation ~= nil and state.generation ~= generation) then
		return
	end
	movementLocks[player] = nil
	if state.character.Parent then
		state.character:SetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE, false)
	end
	if state.humanoid.Parent and state.humanoid.Health > 0 then
		state.humanoid.WalkSpeed = state.originalWalkSpeed
	end
end

local function acquireSpawnMovementLock(
	player: Player,
	character: Model,
	generation: number
): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local existing = movementLocks[player]
	local originalWalkSpeed = humanoid.WalkSpeed
	if existing and existing.character == character and existing.humanoid == humanoid then
		originalWalkSpeed = existing.originalWalkSpeed
	elseif existing then
		releaseSpawnMovementLock(player, nil)
	end

	movementLocks[player] = {
		generation = generation,
		character = character,
		humanoid = humanoid,
		originalWalkSpeed = originalWalkSpeed,
	}
	character:SetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE, true)
	humanoid.WalkSpeed = 0
	humanoid:Move(Vector3.zero, false)

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		root.AssemblyAngularVelocity = Vector3.zero
	end
	return true
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

	local visualMesh = visual:FindFirstChildOfClass("SpecialMesh")
	if visualMesh then
		visualMesh.Scale = visualMesh.Scale * EGG_VISUAL_SCALE_FACTOR
		visualMesh.Offset = visualMesh.Offset * EGG_VISUAL_SCALE_FACTOR
	else
		visual.Size = visual.Size * EGG_VISUAL_SCALE_FACTOR
	end

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

local function spawnEggsInBasket(
	player: Player,
	character: Model,
	requestedCount: number,
	generation: number
)
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

	-- Do not add the collision shell or loose eggs until the rigid root mount is ready.
	local readyDeadline = os.clock() + 3
	while basket:GetAttribute(MOUNT_READY_ATTRIBUTE) ~= true
		and basket.Parent
		and os.clock() < readyDeadline
	do
		RunService.Heartbeat:Wait()
	end
	if basket:GetAttribute(MOUNT_READY_ATTRIBUTE) ~= true then
		warn("EggBasketSpawnService: rigid root basket mount was not ready")
		return
	end

	-- Keep loose eggs out of the assembly during the brief hand-follower startup
	-- transient. This changes only initial placement timing, not egg physics.
	task.wait(EGG_INITIAL_MOUNT_SETTLE_DELAY)
	if spawnGeneration[player] ~= generation
		or player.Character ~= character
		or not basket.Parent
		or not bottom.Parent
	then
		return
	end
	local shell = addBasketCollisionShell(basket, bottom)
	local layout = generateSpawnLayout(bottom, shell, requestedCount)

	local template = ServerStorage:FindFirstChild("EggPhysicsTemplate")
	if not template or not template:IsA("Model") then
		warn("EggBasketSpawnService: EggPhysicsTemplate was not available")
		return
	end

	if Players:GetPlayerFromCharacter(character) ~= player then
		warn("EggBasketSpawnService: player owner was not available")
		return
	end
	local eggs: { Model } = {}
	activeEggs[character] = eggs
	local ownershipAssignedCount = 0
	local forbiddenMovementRemovedCount = 0
	local firstAssemblyPartCount: number? = nil

	for index = 1, requestedCount do
		local localSpawnPosition = layout.positions[index]
		-- A death, respawn, basket removal, or second spawn request invalidates
		-- this set immediately, so the delayed loop cannot create duplicates.
		if spawnGeneration[player] ~= generation
			or player.Character ~= character
			or activeEggs[character] ~= eggs
			or not character.Parent
			or not basket.Parent
		then
			break
		end

		local egg = template:Clone()
		egg.Name = EGG_NAME .. "_" .. tostring(index)
		egg:SetAttribute("OwnerUserId", player.UserId)
		egg:SetAttribute("IsBasketEgg", true)
		egg:SetAttribute("EggIndex", index)
		egg:SetAttribute("InBasket", true)
		egg:SetAttribute("HasLeftBasket", false)
		egg:SetAttribute("IsBroken", false)

		local collider, forbiddenMovementRemoved = configureCleanEggAssembly(egg)
		if not collider then
			egg:Destroy()
			cleanUpEggs(character)
			warn("EggBasketSpawnService: clean Collider/Visual assembly was not available")
			return
		end
		-- This is the egg's only scripted movement, performed before it enters
		-- Workspace. From this point onward the basket and Roblox physics move it.
		egg:PivotTo(bottom.CFrame * CFrame.new(localSpawnPosition))
		egg.Parent = Workspace
		collider.AssemblyLinearVelocity = bottom.AssemblyLinearVelocity
		collider.AssemblyAngularVelocity = bottom.AssemblyAngularVelocity
		table.insert(eggs, egg)
		if forbiddenMovementRemoved then
			forbiddenMovementRemovedCount += 1
		end
		if firstAssemblyPartCount == nil then
			firstAssemblyPartCount = getAssemblyPartCount(collider)
		end

		local canSetOwnership, ownershipReason = collider:CanSetNetworkOwnership()
		if canSetOwnership then
			local assigned, assignmentError = pcall(function()
				collider:SetNetworkOwner(player)
			end)
			if assigned then
				ownershipAssignedCount += 1
			else
				ownershipReason = tostring(assignmentError)
			end
		end
		if not canSetOwnership or collider:GetNetworkOwner() ~= player then
			warn(
				"[EggSelection] Network ownership failed",
				"egg=" .. tostring(index),
				"reason=" .. tostring(ownershipReason or "unknown")
			)
		end

		if index < requestedCount then
			task.wait(EGG_SPAWN_DELAY)
		end
	end

	if spawnGeneration[player] ~= generation or activeEggs[character] ~= eggs then
		return
	end
	print(
		"[EggSelection] SpawnComplete",
		"player=" .. player.Name,
		"requested=" .. tostring(requestedCount),
		"active=" .. tostring(#eggs),
		"networkOwned=" .. tostring(ownershipAssignedCount),
		"positionsPerLayer=" .. tostring(layout.positionsPerLayer),
		"assemblyParts=" .. tostring(firstAssemblyPartCount or 0),
		"forbiddenMovementRemoved=" .. tostring(forbiddenMovementRemovedCount)
	)

	task.delay(2, function()
		if spawnGeneration[player] ~= generation
			or activeEggs[character] ~= eggs
			or not bottom.Parent
		then
			return
		end

		local highestEggTop = -math.huge
		local activeCount = 0
		for _, egg in eggs do
			local collider = egg:FindFirstChild("Collider")
			if collider and collider:IsA("BasePart") and collider.Parent then
				activeCount += 1
				local localCenter = bottom.CFrame:PointToObjectSpace(collider.Position)
				highestEggTop = math.max(
					highestEggTop,
					localCenter.Y + collider.Size.Y * 0.5
				)
			end
		end

		if highestEggTop > -math.huge then
			print(
				"[EggSelection] Capacity",
				"requested=" .. tostring(requestedCount),
				"active=" .. tostring(activeCount),
				"interiorWidth=" .. string.format("%.3f", layout.interiorWidth),
				"interiorDepth=" .. string.format("%.3f", layout.interiorDepth),
				"interiorHeight=" .. string.format("%.3f", layout.interiorHeight),
				"colliderDiameter=" .. string.format("%.3f", EGG_COLLIDER_DIAMETER),
				"highestClearance=" .. string.format("%.3f", layout.rimLocalY - highestEggTop),
				"belowRim=" .. tostring(highestEggTop <= layout.rimLocalY)
			)
		end
	end)
end

local function requestEggRebuild(player: Player)
	local generation = invalidatePlayerSpawn(player)
	local character = player.Character
	if not character then
		releaseSpawnMovementLock(player, nil)
		cleanUpOwnedWorkspaceEggs(player)
		return
	end
	if not acquireSpawnMovementLock(player, character, generation) then
		cleanUpOwnedWorkspaceEggs(player)
		return
	end

	cleanUpEggs(character)
	cleanUpOwnedWorkspaceEggs(player)
	local requestedCount = getSelectedEggCount(player)
	task.spawn(function()
		task.wait(EGG_REBUILD_DELAY)
		if spawnGeneration[player] ~= generation or player.Character ~= character then
			releaseSpawnMovementLock(player, generation)
			return
		end
		local succeeded, failure = xpcall(function()
			spawnEggsInBasket(player, character, requestedCount, generation)
		end, debug.traceback)
		if not succeeded then
			warn("EggBasketSpawnService: egg rebuild failed", failure)
		end
		if spawnGeneration[player] == generation and player.Character == character then
			task.wait(EGG_POST_SPAWN_SETTLE_DELAY)
		end
		releaseSpawnMovementLock(player, generation)
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	removeLegacyEggVerticalStabilizer(character)
	applyCharacterCollisionGroup(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			invalidatePlayerSpawn(player)
			releaseSpawnMovementLock(player, nil)
			cleanUpEggs(character)
			cleanUpOwnedWorkspaceEggs(player)
		end)
	end
	character.Destroying:Once(function()
		cleanUpEggs(character)
	end)
	task.defer(requestEggRebuild, player)
end

local function onPlayerAdded(player: Player)
	getSelectedEggCount(player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(function(character: Model)
		invalidatePlayerSpawn(player)
		releaseSpawnMovementLock(player, nil)
		cleanUpEggs(character)
		cleanUpOwnedWorkspaceEggs(player)
	end)

	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function getOrCreateSetEggCountRemote(): RemoteEvent
	local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if remotes and not remotes:IsA("Folder") then
		remotes:Destroy()
		remotes = nil
	end
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = REMOTES_FOLDER_NAME
		remotes.Parent = ReplicatedStorage
	end

	local existing = remotes:FindFirstChild(SET_EGG_COUNT_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	elseif existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = SET_EGG_COUNT_REMOTE_NAME
	remote.Parent = remotes
	return remote
end

removeBrokenEggPrototypeRemnants()
configureCollisionGroups()
removeHybridExperimentRemnants()
removeLegacyEggVerticalStabilizer(StarterPlayer.StarterCharacterScripts)
removeStaleRuntimeEggs()
local setEggCountRemote = getOrCreateSetEggCountRemote()
setEggCountRemote.OnServerEvent:Connect(function(player: Player, requestedValue: any)
	local requestedCount = validateEggCount(requestedValue)
	if not requestedCount then
		warn(
			"[EggSelection] Rejected invalid count",
			"player=" .. player.Name,
			"value=" .. tostring(requestedValue)
		)
		return
	end

	if getSelectedEggCount(player) == requestedCount then
		return
	end
	player:SetAttribute(SELECTED_EGG_COUNT_ATTRIBUTE, requestedCount)
	requestEggRebuild(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	invalidatePlayerSpawn(player)
	releaseSpawnMovementLock(player, nil)
	if player.Character then
		cleanUpEggs(player.Character)
	end
	cleanUpOwnedWorkspaceEggs(player)
	spawnGeneration[player] = nil
end)

print(
	"[EggSelection] Ready",
	"default=" .. tostring(DEFAULT_EGG_COUNT),
	"minimum=" .. tostring(MIN_EGG_COUNT),
	"maximum=" .. tostring(MAX_EGG_COUNT),
	"spawnDelay=" .. tostring(EGG_SPAWN_DELAY),
	"perEggForces=false"
)
Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
