--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LIVE_EGG_ATTRIBUTE = "IsBasketEgg"
local OWNER_USER_ID_ATTRIBUTE = "OwnerUserId"
local IN_BASKET_ATTRIBUTE = "InBasket"
local HAS_LEFT_BASKET_ATTRIBUTE = "HasLeftBasket"
local IS_BROKEN_ATTRIBUTE = "IsBroken"

local BASKET_NAME = "Basket"
local COLLISION_SHELL_NAME = "EggCollisionShell"
local EGG_COLLISION_GROUP = "Eggs"
local BASKET_COLLISION_GROUP = "EggBasket"
local CHARACTER_COLLISION_GROUP = "Characters"

local BREAK_NORMAL_SPEED_THRESHOLD = 13.0
local LEAVE_CONFIRM_TIME = 0.05
local LEAVE_HORIZONTAL_MARGIN = 0.12
local BELOW_FLOOR_MARGIN = 0.08
local RECENT_VELOCITY_MEMORY = 0.30
local PREDICTIVE_CONTACT_LOOKAHEAD = 0.012

local SPLAT_TEXTURE = "rbxassetid://136220663285126"
local SPLAT_SIZE = 1.70
local SPLAT_THICKNESS = 0.012
local SPLAT_SURFACE_OFFSET = 0.003
local SPLAT_LIFETIME = 90
local SPLAT_FOLDER_NAME = "EggSplatEffects"
local SLIP_HITBOX_SIZE = Vector3.new(1.45, 0.16, 1.45)
local SLIP_HITBOX_LOCAL_Y = 0.07
local REMOTES_FOLDER_NAME = "Remotes"
local BREAK_CANDIDATE_REMOTE_NAME = "EggBreakCandidate"

type EggTrack = {
	egg: Model,
	collider: BasePart,
	lastPosition: Vector3,
	lastVelocity: Vector3,
	recentFastVelocity: Vector3,
	recentFastVelocityUntil: number,
	outsideSince: number?,
	breaking: boolean,
	touchedConnection: RBXScriptConnection?,
	destroyingConnection: RBXScriptConnection?,
}

local trackedEggs: { [Model]: EggTrack } = {}

local function getSplatFolder(): Folder
	local existing = Workspace:FindFirstChild(SPLAT_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	elseif existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = SPLAT_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function getOrCreateBreakCandidateRemote(): RemoteEvent
	local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = REMOTES_FOLDER_NAME
		remotes.Parent = ReplicatedStorage
	end
	local existing = remotes:FindFirstChild(BREAK_CANDIDATE_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	elseif existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = BREAK_CANDIDATE_REMOTE_NAME
	remote.Parent = remotes
	return remote
end

local function removeLegacyYolk3D(instance: Instance)
	if instance.Name == "Yolk3D" and instance:IsA("BasePart") then
		instance:Destroy()
	end
end

local function getOwnerCharacter(egg: Model): Model?
	local ownerUserId = egg:GetAttribute(OWNER_USER_ID_ATTRIBUTE)
	if typeof(ownerUserId) ~= "number" then
		return nil
	end
	local player = Players:GetPlayerByUserId(ownerUserId)
	return if player then player.Character else nil
end

local function getBasketBounds(egg: Model): (BasePart?, Model?)
	local character = getOwnerCharacter(egg)
	if not character then
		return nil, nil
	end
	local basket = character:FindFirstChild(BASKET_NAME)
	if not basket or not basket:IsA("Model") then
		return nil, nil
	end
	local bottom = basket:FindFirstChild("Bottom")
	local shell = basket:FindFirstChild(COLLISION_SHELL_NAME)
	if not bottom or not bottom:IsA("BasePart") or not shell or not shell:IsA("Model") then
		return nil, nil
	end
	return bottom, shell
end

local function readNumberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

local function isPositionClearlyOutsideBasket(track: EggTrack, worldPosition: Vector3): boolean
	local bottom, shell = getBasketBounds(track.egg)
	if not bottom or not shell then
		return false
	end

	local floorY = readNumberAttribute(shell, "FloorLocalY")
	local rimY = readNumberAttribute(shell, "RimLocalY")
	local lowerWidth = readNumberAttribute(shell, "LowerInteriorWidth")
	local lowerDepth = readNumberAttribute(shell, "LowerInteriorDepth")
	local upperWidth = readNumberAttribute(shell, "UpperInteriorWidth")
	local upperDepth = readNumberAttribute(shell, "UpperInteriorDepth")
	if not floorY or not rimY or not lowerWidth or not lowerDepth or not upperWidth or not upperDepth then
		return false
	end

	local localCenter = bottom.CFrame:PointToObjectSpace(worldPosition)
	local heightAlpha = math.clamp((localCenter.Y - floorY) / math.max(rimY - floorY, 0.001), 0, 1)
	local interiorWidth = lowerWidth + (upperWidth - lowerWidth) * heightAlpha
	local interiorDepth = lowerDepth + (upperDepth - lowerDepth) * heightAlpha
	local outsideHorizontally = math.abs(localCenter.X)
		> interiorWidth * 0.5 + LEAVE_HORIZONTAL_MARGIN
		or math.abs(localCenter.Z) > interiorDepth * 0.5 + LEAVE_HORIZONTAL_MARGIN
	local radius = track.collider.Size.Y * 0.5
	local belowFloor = localCenter.Y < floorY - radius - BELOW_FLOOR_MARGIN
	return outsideHorizontally or belowFloor
end

local function isClearlyOutsideBasket(track: EggTrack): boolean
	return isPositionClearlyOutsideBasket(track, track.collider.Position)
end

local function updateBasketState(track: EggTrack, now: number)
	if track.egg:GetAttribute(HAS_LEFT_BASKET_ATTRIBUTE) == true then
		return
	end

	if isClearlyOutsideBasket(track) then
		track.outsideSince = track.outsideSince or now
		if now - (track.outsideSince :: number) >= LEAVE_CONFIRM_TIME then
			track.egg:SetAttribute(IN_BASKET_ATTRIBUTE, false)
			track.egg:SetAttribute(HAS_LEFT_BASKET_ATTRIBUTE, true)
		end
	else
		track.outsideSince = nil
		track.egg:SetAttribute(IN_BASKET_ATTRIBUTE, true)
	end
end

local function makeSurfaceCFrame(position: Vector3, normal: Vector3): CFrame
	local up = if normal.Magnitude > 0.001 then normal.Unit else Vector3.yAxis
	local reference = if math.abs(up:Dot(Vector3.xAxis)) < 0.95
		then Vector3.xAxis
		else Vector3.zAxis
	local right = up:Cross(reference).Unit
	local back = right:Cross(up).Unit
	-- Match the immediate client visual exactly so the authoritative handoff
	-- cannot rotate the PNG after impact.
	return CFrame.fromMatrix(position, right, up, back)
end

local function spawnBrokenEggSplat(position: Vector3, normal: Vector3, sourceEgg: Model)
	local surfaceNormal = if normal.Magnitude > 0.001 then normal.Unit else Vector3.yAxis
	local splat = Instance.new("Part")
	splat.Name = "BrokenEggSplat"
	splat.Size = Vector3.new(SPLAT_SIZE, SPLAT_THICKNESS, SPLAT_SIZE)
	splat.CFrame = makeSurfaceCFrame(
		position + surfaceNormal * (SPLAT_THICKNESS * 0.5 + SPLAT_SURFACE_OFFSET),
		surfaceNormal
	)
	splat.Transparency = 1
	splat.Anchored = true
	splat.CanCollide = false
	splat.CanTouch = false
	splat.CanQuery = false
	splat.CastShadow = false
	splat:SetAttribute("SourceOwnerUserId", sourceEgg:GetAttribute(OWNER_USER_ID_ATTRIBUTE))
	splat:SetAttribute("SourceEggIndex", sourceEgg:GetAttribute("EggIndex"))
	splat.Parent = getSplatFolder()

	-- A pixel-dense SurfaceGui keeps the uploaded image noticeably sharper
	-- than a world Decal when viewed at normal gameplay distance.
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "BrokenEggSurface"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.AlwaysOnTop = false
	surfaceGui.LightInfluence = 0.15
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 240
	surfaceGui.Parent = splat

	local image = Instance.new("ImageLabel")
	image.Name = "BrokenEggImage"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Size = UDim2.fromScale(1, 1)
	image.Image = SPLAT_TEXTURE
	image.ResampleMode = Enum.ResamplerMode.Default
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = surfaceGui

	local slipHitbox = Instance.new("Part")
	slipHitbox.Name = "SlipHitbox"
	slipHitbox.Size = SLIP_HITBOX_SIZE
	slipHitbox.CFrame = splat.CFrame * CFrame.new(0, SLIP_HITBOX_LOCAL_Y, 0)
	slipHitbox.Transparency = 1
	slipHitbox.Anchored = true
	slipHitbox.CanCollide = false
	slipHitbox.CanTouch = false
	slipHitbox.CanQuery = true
	slipHitbox.Massless = true
	slipHitbox.CastShadow = false
	slipHitbox:SetAttribute("IsEggSlipZone", true)
	slipHitbox.Parent = splat

	Debris:AddItem(splat, SPLAT_LIFETIME)
end

local function getImpactSurface(
	track: EggTrack,
	otherPart: BasePart,
	centerOverride: Vector3?
): (Vector3, Vector3)
	local centerPosition = centerOverride or track.collider.Position
	local currentRelativeVelocity = track.lastVelocity - otherPart.AssemblyLinearVelocity
	local recentRelativeVelocity = track.recentFastVelocity - otherPart.AssemblyLinearVelocity
	local relativeVelocity = if recentRelativeVelocity.Magnitude > currentRelativeVelocity.Magnitude
		then recentRelativeVelocity
		else currentRelativeVelocity
	local direction = if relativeVelocity.Magnitude > 0.1
		then relativeVelocity.Unit
		else Vector3.new(0, -1, 0)
	local radius = math.max(track.collider.Size.X, track.collider.Size.Y, track.collider.Size.Z) * 0.5

	local params = RaycastParams.new()
	-- Only accept the part reported by Touched. This prevents a nearby egg,
	-- character limb, or basket strip from becoming the splat surface.
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { otherPart }
	params.IgnoreWater = false

	-- Ground impacts are by far the common case. Cast from well above the egg
	-- straight down onto the exact touched part so the splat lands on the real
	-- surface instead of inheriting a tilted velocity-based fallback normal.
	local downwardOrigin = centerPosition + Vector3.new(0, radius + 1.5, 0)
	local downwardResult = Workspace:Raycast(
		downwardOrigin,
		Vector3.new(0, -(radius * 2 + 4), 0),
		params
	)
	if downwardResult and downwardResult.Normal.Y >= 0.45 then
		return downwardResult.Position, downwardResult.Normal
	end

	local origin = centerPosition - direction * (radius + 0.35)
	local result = Workspace:Raycast(origin, direction * (radius * 2 + 0.9), params)
	if result then
		return result.Position, result.Normal
	end

	-- Last reliable fallback: project to the touched part's bounding box rather
	-- than orienting a decal in mid-air from velocity alone.
	local localPoint = otherPart.CFrame:PointToObjectSpace(centerPosition)
	local halfSize = otherPart.Size * 0.5
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -halfSize.X, halfSize.X),
		math.clamp(localPoint.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPoint.Z, -halfSize.Z, halfSize.Z)
	)
	local distances = {
		{ distance = math.abs(localPoint.X - halfSize.X), normal = Vector3.xAxis, point = Vector3.new(halfSize.X, clamped.Y, clamped.Z) },
		{ distance = math.abs(localPoint.X + halfSize.X), normal = -Vector3.xAxis, point = Vector3.new(-halfSize.X, clamped.Y, clamped.Z) },
		{ distance = math.abs(localPoint.Y - halfSize.Y), normal = Vector3.yAxis, point = Vector3.new(clamped.X, halfSize.Y, clamped.Z) },
		{ distance = math.abs(localPoint.Y + halfSize.Y), normal = -Vector3.yAxis, point = Vector3.new(clamped.X, -halfSize.Y, clamped.Z) },
		{ distance = math.abs(localPoint.Z - halfSize.Z), normal = Vector3.zAxis, point = Vector3.new(clamped.X, clamped.Y, halfSize.Z) },
		{ distance = math.abs(localPoint.Z + halfSize.Z), normal = -Vector3.zAxis, point = Vector3.new(clamped.X, clamped.Y, -halfSize.Z) },
	}
	table.sort(distances, function(a, b)
		return a.distance < b.distance
	end)
	local closest = distances[1]
	return otherPart.CFrame:PointToWorldSpace(closest.point),
		otherPart.CFrame:VectorToWorldSpace(closest.normal).Unit
end

local function unregisterEgg(egg: Model)
	local track = trackedEggs[egg]
	if not track then
		return
	end
	trackedEggs[egg] = nil
	if track.touchedConnection then
		track.touchedConnection:Disconnect()
	end
	if track.destroyingConnection then
		track.destroyingConnection:Disconnect()
	end
end

local function completeBreak(
	track: EggTrack,
	impactPosition: Vector3,
	impactNormal: Vector3,
	normalImpactSpeed: number
)
	if track.breaking
		or not track.egg.Parent
		or track.egg:GetAttribute(IS_BROKEN_ATTRIBUTE) == true
		or track.egg:GetAttribute(HAS_LEFT_BASKET_ATTRIBUTE) ~= true
		or normalImpactSpeed < BREAK_NORMAL_SPEED_THRESHOLD
	then
		return
	end

	track.breaking = true
	track.egg:SetAttribute(IS_BROKEN_ATTRIBUTE, true)
	track.collider.CanCollide = false
	track.collider.CanTouch = false
	spawnBrokenEggSplat(impactPosition, impactNormal, track.egg)
	local egg = track.egg
	unregisterEgg(egg)
	egg:Destroy()
end

local function tryPredictiveBreak(track: EggTrack): boolean
	if track.breaking
		or not track.egg.Parent
		or track.egg:GetAttribute(IS_BROKEN_ATTRIBUTE) == true
	then
		return false
	end

	local currentVelocity = track.collider.AssemblyLinearVelocity
	if currentVelocity.Magnitude < BREAK_NORMAL_SPEED_THRESHOLD then
		return false
	end

	local travel = track.collider.Position - track.lastPosition
		+ currentVelocity * PREDICTIVE_CONTACT_LOOKAHEAD
	if travel.Magnitude < 0.01 then
		return false
	end

	local filter: { Instance } = { track.egg }
	local character = getOwnerCharacter(track.egg)
	if character then
		table.insert(filter, character)
	end
	local splatFolder = Workspace:FindFirstChild(SPLAT_FOLDER_NAME)
	if splatFolder then
		table.insert(filter, splatFolder)
	end
	for otherEgg in trackedEggs do
		if otherEgg ~= track.egg then
			table.insert(filter, otherEgg)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = false
	params.RespectCanCollide = true
	local radius = math.max(
		track.collider.Size.X,
		track.collider.Size.Y,
		track.collider.Size.Z
	) * 0.46
	local result = Workspace:Spherecast(track.lastPosition, radius, travel, params)
	if not result or not result.Instance:IsA("BasePart") then
		return false
	end
	local hitPart = result.Instance :: BasePart
	if hitPart.CollisionGroup == BASKET_COLLISION_GROUP
		or hitPart.CollisionGroup == CHARACTER_COLLISION_GROUP
		or hitPart.CollisionGroup == EGG_COLLISION_GROUP
	then
		return false
	end

	local normalImpactSpeed = math.abs(
		(currentVelocity - hitPart.AssemblyLinearVelocity):Dot(result.Normal.Unit)
	)
	if normalImpactSpeed < BREAK_NORMAL_SPEED_THRESHOLD then
		return false
	end

	if track.egg:GetAttribute(HAS_LEFT_BASKET_ATTRIBUTE) ~= true then
		if not isClearlyOutsideBasket(track) then
			return false
		end
		track.egg:SetAttribute(IN_BASKET_ATTRIBUTE, false)
		track.egg:SetAttribute(HAS_LEFT_BASKET_ATTRIBUTE, true)
	end

	-- Spherecast.Position is the leading edge of the egg collider, not the
	-- visual centre of the egg. Project the egg's current centre straight onto
	-- the contacted surface so the splat appears exactly beneath the egg rather
	-- than slightly ahead along its travel direction.
	local splatPosition, splatNormal = getImpactSurface(track, hitPart)
	completeBreak(track, splatPosition, splatNormal, normalImpactSpeed)
	return track.breaking
end

local function tryBreakEgg(track: EggTrack, otherPart: BasePart)
	if track.breaking
		or track.egg:GetAttribute(IS_BROKEN_ATTRIBUTE) == true
		or not otherPart.CanCollide
		or otherPart:IsDescendantOf(track.egg)
		or otherPart.CollisionGroup == EGG_COLLISION_GROUP
		or otherPart.CollisionGroup == BASKET_COLLISION_GROUP
		or otherPart.CollisionGroup == CHARACTER_COLLISION_GROUP
	then
		return
	end

	local character = getOwnerCharacter(track.egg)
	if character and otherPart:IsDescendantOf(character) then
		return
	end

	local impactPosition, impactNormal = getImpactSurface(track, otherPart)
	local currentRelativeVelocity = track.lastVelocity - otherPart.AssemblyLinearVelocity
	local recentRelativeVelocity = track.recentFastVelocity - otherPart.AssemblyLinearVelocity
	local currentNormalSpeed = math.abs(currentRelativeVelocity:Dot(impactNormal.Unit))
	local recentNormalSpeed = if os.clock() <= track.recentFastVelocityUntil
		then math.abs(recentRelativeVelocity:Dot(impactNormal.Unit))
		else 0
	local normalImpactSpeed = math.max(currentNormalSpeed, recentNormalSpeed)
	if normalImpactSpeed < BREAK_NORMAL_SPEED_THRESHOLD then
		return
	end

	updateBasketState(track, os.clock())
	if track.egg:GetAttribute(HAS_LEFT_BASKET_ATTRIBUTE) ~= true then
		-- A hard world impact while geometrically outside is itself definitive
		-- proof that the egg has left the basket. Confirm immediately so the egg
		-- cannot roll and later snap back to a cached impact position.
		if not isClearlyOutsideBasket(track) then
			return
		end
		track.egg:SetAttribute(IN_BASKET_ATTRIBUTE, false)
		track.egg:SetAttribute(HAS_LEFT_BASKET_ATTRIBUTE, true)
	end
	completeBreak(track, impactPosition, impactNormal, normalImpactSpeed)
end

local function tryBreakFromClient(
	player: Player,
	egg: any,
	otherPart: any,
	clientCenter: any,
	clientVelocity: any
)
	if typeof(egg) ~= "Instance"
		or not egg:IsA("Model")
		or typeof(otherPart) ~= "Instance"
		or not otherPart:IsA("BasePart")
		or typeof(clientCenter) ~= "Vector3"
		or typeof(clientVelocity) ~= "Vector3"
	then
		return
	end

	local track = trackedEggs[egg]
	if not track
		or track.breaking
		or egg:GetAttribute(OWNER_USER_ID_ATTRIBUTE) ~= player.UserId
		or not otherPart:IsDescendantOf(Workspace)
		or not otherPart.CanCollide
		or otherPart.CollisionGroup == EGG_COLLISION_GROUP
		or otherPart.CollisionGroup == BASKET_COLLISION_GROUP
		or otherPart.CollisionGroup == CHARACTER_COLLISION_GROUP
		or clientVelocity.Magnitude > 250
		or (clientCenter - track.collider.Position).Magnitude > 6
	then
		return
	end

	local character = player.Character
	if character and otherPart:IsDescendantOf(character) then
		return
	end

	if egg:GetAttribute(HAS_LEFT_BASKET_ATTRIBUTE) ~= true then
		if not isPositionClearlyOutsideBasket(track, clientCenter) then
			return
		end
		egg:SetAttribute(IN_BASKET_ATTRIBUTE, false)
		egg:SetAttribute(HAS_LEFT_BASKET_ATTRIBUTE, true)
	end

	local impactPosition, impactNormal = getImpactSurface(track, otherPart, clientCenter)
	local normalImpactSpeed = math.abs(
		(clientVelocity - otherPart.AssemblyLinearVelocity):Dot(impactNormal.Unit)
	)
	completeBreak(track, impactPosition, impactNormal, normalImpactSpeed)
end

local function registerEgg(instance: Instance)
	if not instance:IsA("Model")
		or instance:GetAttribute(LIVE_EGG_ATTRIBUTE) ~= true
		or trackedEggs[instance]
	then
		return
	end
	local collider = instance:FindFirstChild("Collider")
	if not collider or not collider:IsA("BasePart") then
		return
	end

	if instance:GetAttribute(IN_BASKET_ATTRIBUTE) == nil then
		instance:SetAttribute(IN_BASKET_ATTRIBUTE, true)
	end
	if instance:GetAttribute(HAS_LEFT_BASKET_ATTRIBUTE) == nil then
		instance:SetAttribute(HAS_LEFT_BASKET_ATTRIBUTE, false)
	end
	if instance:GetAttribute(IS_BROKEN_ATTRIBUTE) == nil then
		instance:SetAttribute(IS_BROKEN_ATTRIBUTE, false)
	end

	local track: EggTrack = {
		egg = instance,
		collider = collider,
		lastPosition = collider.Position,
		lastVelocity = collider.AssemblyLinearVelocity,
		recentFastVelocity = collider.AssemblyLinearVelocity,
		recentFastVelocityUntil = os.clock() + RECENT_VELOCITY_MEMORY,
		outsideSince = nil,
		breaking = false,
		touchedConnection = nil,
		destroyingConnection = nil,
	}
	trackedEggs[instance] = track
	track.touchedConnection = collider.Touched:Connect(function(otherPart: BasePart)
		tryBreakEgg(track, otherPart)
	end)
	track.destroyingConnection = instance.Destroying:Connect(function()
		unregisterEgg(instance)
	end)
end

Workspace.ChildAdded:Connect(registerEgg)
for _, child in Workspace:GetChildren() do
	registerEgg(child)
end

for _, descendant in Workspace:GetDescendants() do
	removeLegacyYolk3D(descendant)
end
Workspace.DescendantAdded:Connect(removeLegacyYolk3D)

getOrCreateBreakCandidateRemote().OnServerEvent:Connect(tryBreakFromClient)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for egg, track in trackedEggs do
		if not egg.Parent or not track.collider.Parent then
			unregisterEgg(egg)
		else
			updateBasketState(track, now)
			if tryPredictiveBreak(track) then
				continue
			end
			track.lastPosition = track.collider.Position
			local currentVelocity = track.collider.AssemblyLinearVelocity
			if now > track.recentFastVelocityUntil
				or currentVelocity.Magnitude > track.recentFastVelocity.Magnitude
			then
				track.recentFastVelocity = currentVelocity
				track.recentFastVelocityUntil = now + RECENT_VELOCITY_MEMORY
			end
			track.lastVelocity = currentVelocity
		end
	end
end)
