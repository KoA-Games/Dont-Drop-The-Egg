--!strict

local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local breakRemote = ReplicatedStorage:WaitForChild("Remotes")
	:WaitForChild("EggBreakCandidate") :: RemoteEvent

local BREAK_SPEED_THRESHOLD = 13.0
local RECENT_VELOCITY_MEMORY = 0.30
local FLOOR_MIN_NORMAL_Y = 0.60
local FLOOR_CONTACT_TOLERANCE = 0.16
local SPLAT_THICKNESS = 0.012
local SPLAT_SURFACE_OFFSET = 0.003
local SPLASH_PARTICLE_COUNT = 8
local SPLASH_PARTICLE_LIFETIME = NumberRange.new(0.18, 0.27)

type SplatVariant = {
	texture: string,
	size: number,
}

-- Keep this distance table identical to EggBreakService so the immediate local
-- impact does not change shape when the authoritative server splat arrives.
local SPLAT_VARIANTS_SMALL_TO_LARGE: { SplatVariant } = {
	{ texture = "rbxassetid://121525285901661", size = 1.45 }, -- egg3
	{ texture = "rbxassetid://79177056137071", size = 1.60 }, -- egg4
	{ texture = "rbxassetid://118420947274204", size = 1.75 }, -- egg1
	{ texture = "rbxassetid://110482754432356", size = 1.95 }, -- egg5
	{ texture = "rbxassetid://107954623201279", size = 2.15 }, -- egg2
}
local SPLAT_DISTANCE_THRESHOLDS = { 1.75, 3.50, 5.50, 8.00 }

local function preloadSplatTextures()
	local preloadTargets: { Instance } = {}
	for _, splatVariant in SPLAT_VARIANTS_SMALL_TO_LARGE do
		local image = Instance.new("ImageLabel")
		image.Image = splatVariant.texture
		table.insert(preloadTargets, image)
	end

	local preloadSucceeded, preloadError = pcall(function()
		ContentProvider:PreloadAsync(preloadTargets)
	end)
	for _, image in preloadTargets do
		image:Destroy()
	end
	if not preloadSucceeded then
		warn("EggBreakImmediate: splat texture preload failed: " .. tostring(preloadError))
	end
end

-- Finish the five small image downloads before listening for the first impact.
-- Existing eggs are registered immediately afterwards, so this only moves the
-- network wait to startup instead of letting the first broken egg stay blank.
preloadSplatTextures()

type ClientEggTrack = {
	egg: Model,
	collider: BasePart,
	lastBasketPosition: Vector3,
	recentFastVelocity: Vector3,
	recentFastVelocityUntil: number,
	touchedConnection: RBXScriptConnection?,
	destroyingConnection: RBXScriptConnection?,
}

type PendingVisual = {
	splat: BasePart,
	position: Vector3,
	originalTransparency: { [BasePart]: number },
	ownerUserId: number,
	eggIndex: number,
}

local trackedEggs: { [Model]: ClientEggTrack } = {}
local pendingVisuals: { [Model]: PendingVisual } = {}
local localEffects = Instance.new("Folder")
localEffects.Name = "LocalEggBreakEffects"
localEffects.Archivable = false
localEffects.Parent = Workspace

local function getOwnerBasket(): Model?
	local character = player.Character
	if character then
		local carriedBasket = character:FindFirstChild("Basket")
		if carriedBasket and carriedBasket:IsA("Model") then
			return carriedBasket
		end
	end
	local droppedBasket = Workspace:FindFirstChild("DroppedBasket_" .. tostring(player.UserId))
	return if droppedBasket and droppedBasket:IsA("Model") then droppedBasket else nil
end

local function selectSplatVariant(
	track: ClientEggTrack,
	impactPosition: Vector3
): (SplatVariant, number, number)
	local offset = impactPosition - track.lastBasketPosition
	local travelDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude

	for index, threshold in SPLAT_DISTANCE_THRESHOLDS do
		if travelDistance < threshold then
			return SPLAT_VARIANTS_SMALL_TO_LARGE[index], travelDistance, index
		end
	end
	local largestIndex = #SPLAT_VARIANTS_SMALL_TO_LARGE
	return SPLAT_VARIANTS_SMALL_TO_LARGE[largestIndex], travelDistance, largestIndex
end

local function isOutsideBasket(track: ClientEggTrack): boolean
	local basket = getOwnerBasket()
	if not basket then
		return false
	end
	local bottom = basket:FindFirstChild("Bottom")
	local shell = basket:FindFirstChild("EggCollisionShell")
	if not bottom or not bottom:IsA("BasePart") or not shell or not shell:IsA("Model") then
		return false
	end

	local floorY = shell:GetAttribute("FloorLocalY")
	local rimY = shell:GetAttribute("RimLocalY")
	local lowerWidth = shell:GetAttribute("LowerInteriorWidth")
	local lowerDepth = shell:GetAttribute("LowerInteriorDepth")
	local upperWidth = shell:GetAttribute("UpperInteriorWidth")
	local upperDepth = shell:GetAttribute("UpperInteriorDepth")
	if typeof(floorY) ~= "number"
		or typeof(rimY) ~= "number"
		or typeof(lowerWidth) ~= "number"
		or typeof(lowerDepth) ~= "number"
		or typeof(upperWidth) ~= "number"
		or typeof(upperDepth) ~= "number"
	then
		return false
	end

	local localCenter = bottom.CFrame:PointToObjectSpace(track.collider.Position)
	local alpha = math.clamp((localCenter.Y - floorY) / math.max(rimY - floorY, 0.001), 0, 1)
	local width = lowerWidth + (upperWidth - lowerWidth) * alpha
	local depth = lowerDepth + (upperDepth - lowerDepth) * alpha
	local radius = track.collider.Size.Y * 0.5
	return math.abs(localCenter.X) > width * 0.5 + 0.12
		or math.abs(localCenter.Z) > depth * 0.5 + 0.12
		or localCenter.Y < floorY - radius - 0.08
end

local function getSurface(
	track: ClientEggTrack,
	otherPart: BasePart
): (Vector3?, Vector3?)
	local radius = math.max(
		track.collider.Size.X,
		track.collider.Size.Y,
		track.collider.Size.Z
	) * 0.5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { otherPart }
	params.IgnoreWater = false

	local result = Workspace:Raycast(
		track.collider.Position + Vector3.new(0, radius + 1.5, 0),
		Vector3.new(0, -(radius * 2 + 4), 0),
		params
	)
	if result and result.Normal.Y >= FLOOR_MIN_NORMAL_Y then
		return result.Position, result.Normal
	end

	local velocity = track.recentFastVelocity
	if velocity.Magnitude > 0.1 then
		local direction = velocity.Unit
		result = Workspace:Raycast(
			track.collider.Position - direction * (radius + 0.35),
			direction * (radius * 2 + 0.9),
			params
		)
		if result then
			return result.Position, result.Normal
		end
	end
	return nil, nil
end

local function isVerifiedFloorContact(
	track: ClientEggTrack,
	position: Vector3,
	normal: Vector3
): boolean
	if normal.Magnitude < 0.001 or normal.Unit.Y < FLOOR_MIN_NORMAL_Y then
		return false
	end
	local radius = math.max(
		track.collider.Size.X,
		track.collider.Size.Y,
		track.collider.Size.Z
	) * 0.5
	local surfaceDistance = (track.collider.Position - position):Dot(normal.Unit)
	-- A fast collider may already be slightly through the floor when Touched is
	-- delivered.  Keep the air-gap limit, but accept a confirmed floor crossing.
	return surfaceDistance <= radius + FLOOR_CONTACT_TOLERANCE
end

local function approachingImpactSpeed(relativeVelocity: Vector3, normal: Vector3): number
	if normal.Magnitude < 0.001 then
		return 0
	end
	return math.max(-relativeVelocity:Dot(normal.Unit), 0)
end

local function makeSurfaceCFrame(position: Vector3, normal: Vector3): CFrame
	local up = normal.Unit
	local reference = if math.abs(up:Dot(Vector3.xAxis)) < 0.95
		then Vector3.xAxis
		else Vector3.zAxis
	local right = up:Cross(reference).Unit
	local back = right:Cross(up).Unit
	-- Keep one stable orientation. A second random rotation when the local
	-- preview handed off to the server made the PNG appear to twist on impact.
	return CFrame.fromMatrix(position, right, up, back)
end

local function emitSplashBurst(splat: BasePart)
	local particleAnchor = Instance.new("Part")
	particleAnchor.Name = "EggSplashBurstAnchor"
	particleAnchor.Size = Vector3.one * 0.02
	particleAnchor.CFrame = splat.CFrame
	particleAnchor.Transparency = 1
	particleAnchor.Anchored = true
	particleAnchor.CanCollide = false
	particleAnchor.CanTouch = false
	particleAnchor.CanQuery = false
	particleAnchor.CastShadow = false
	particleAnchor.Parent = localEffects

	local attachment = Instance.new("Attachment")
	attachment.Name = "EggSplashEmitterAttachment"
	attachment.Parent = particleAnchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "EggSplashBurst"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Lifetime = SPLASH_PARTICLE_LIFETIME
	emitter.Speed = NumberRange.new(2.8, 4.6)
	emitter.SpreadAngle = Vector2.new(105, 105)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -9, 0)
	emitter.Drag = 2.5
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 252, 235)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 229, 135)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(245, 164, 28)),
	})
	emitter.LightEmission = 0
	emitter.LightInfluence = 1
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.11),
		NumberSequenceKeypoint.new(0.55, 0.075),
		NumberSequenceKeypoint.new(1, 0.015),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(0.65, 0.18),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment
	emitter:Emit(SPLASH_PARTICLE_COUNT)

	task.delay(0.35, function()
		if particleAnchor.Parent then
			particleAnchor:Destroy()
		end
	end)
end

local function createLocalSplat(
	track: ClientEggTrack,
	position: Vector3,
	normal: Vector3
): BasePart
	local surfaceNormal = normal.Unit
	local splatVariant, travelDistance, variantIndex = selectSplatVariant(track, position)
	local splat = Instance.new("Part")
	splat.Name = "LocalBrokenEggSplat"
	splat.Size = Vector3.new(splatVariant.size, SPLAT_THICKNESS, splatVariant.size)
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
	splat:SetAttribute("TravelDistance", travelDistance)
	splat:SetAttribute("SplatVariantIndex", variantIndex)
	splat.Parent = localEffects

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
	image.Image = splatVariant.texture
	image.ImageTransparency = 0
	image.ResampleMode = Enum.ResamplerMode.Default
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = surfaceGui

	emitSplashBurst(splat)
	Debris:AddItem(splat, 90)
	return splat
end

local function hideEggLocally(egg: Model): { [BasePart]: number }
	local originals: { [BasePart]: number } = {}
	for _, descendant in egg:GetDescendants() do
		if descendant:IsA("BasePart") then
			originals[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = 1
		end
	end
	return originals
end

local function restoreEggLocally(originals: { [BasePart]: number })
	for part, transparency in originals do
		if part.Parent then
			part.LocalTransparencyModifier = transparency
		end
	end
end

local function tryImmediateBreak(track: ClientEggTrack, otherPart: BasePart)
	if pendingVisuals[track.egg]
		or not otherPart.CanCollide
		or otherPart.CollisionGroup == "Eggs"
		or otherPart.CollisionGroup == "EggBasket"
		or otherPart.CollisionGroup == "Characters"
	then
		return
	end
	local character = player.Character
	if character and otherPart:IsDescendantOf(character) then
		return
	end
	if track.egg:GetAttribute("HasLeftBasket") ~= true and not isOutsideBasket(track) then
		return
	end

	local position, normal = getSurface(track, otherPart)
	if not position or not normal or not isVerifiedFloorContact(track, position, normal) then
		return
	end
	local currentVelocity = track.collider.AssemblyLinearVelocity
	local recentVelocity = track.recentFastVelocity
	local currentNormalSpeed = approachingImpactSpeed(
		currentVelocity - otherPart.AssemblyLinearVelocity,
		normal
	)
	local recentNormalSpeed = if os.clock() <= track.recentFastVelocityUntil
		then approachingImpactSpeed(
			recentVelocity - otherPart.AssemblyLinearVelocity,
			normal
		)
		else 0
	local normalSpeed = math.max(currentNormalSpeed, recentNormalSpeed)
	if normalSpeed < BREAK_SPEED_THRESHOLD then
		return
	end

	local originals = hideEggLocally(track.egg)
	local splat = createLocalSplat(track, position, normal)
	pendingVisuals[track.egg] = {
		splat = splat,
		position = position,
		originalTransparency = originals,
		ownerUserId = player.UserId,
		eggIndex = track.egg:GetAttribute("EggIndex") :: number,
	}
	breakRemote:FireServer(
		track.egg,
		otherPart,
		track.collider.Position,
		if recentNormalSpeed > currentNormalSpeed then recentVelocity else currentVelocity
	)

	task.delay(1, function()
		local pending = pendingVisuals[track.egg]
		if pending and pending.splat == splat then
			pendingVisuals[track.egg] = nil
			if splat.Parent then
				splat:Destroy()
			end
			if track.egg.Parent then
				restoreEggLocally(originals)
			end
		end
	end)
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

local function registerEgg(instance: Instance)
	if not instance:IsA("Model")
		or instance:GetAttribute("IsBasketEgg") ~= true
		or instance:GetAttribute("OwnerUserId") ~= player.UserId
		or trackedEggs[instance]
	then
		return
	end
	local collider = instance:FindFirstChild("Collider")
	if not collider or not collider:IsA("BasePart") then
		return
	end

	local track: ClientEggTrack = {
		egg = instance,
		collider = collider,
		lastBasketPosition = collider.Position,
		recentFastVelocity = collider.AssemblyLinearVelocity,
		recentFastVelocityUntil = os.clock() + RECENT_VELOCITY_MEMORY,
		touchedConnection = nil,
		destroyingConnection = nil,
	}
	trackedEggs[instance] = track
	track.touchedConnection = collider.Touched:Connect(function(otherPart: BasePart)
		tryImmediateBreak(track, otherPart)
	end)
	track.destroyingConnection = instance.Destroying:Connect(function()
		unregisterEgg(instance)
	end)
end

Workspace.DescendantAdded:Connect(function(instance: Instance)
	if not instance:IsA("BasePart")
		or instance.Name ~= "BrokenEggSplat"
		or not instance:IsDescendantOf(Workspace:FindFirstChild("EggSplatEffects") or Workspace)
	then
		return
	end
	local sourceOwnerUserId = instance:GetAttribute("SourceOwnerUserId")
	local sourceEggIndex = instance:GetAttribute("SourceEggIndex")
	for egg, pending in pendingVisuals do
		local exactSourceMatch = sourceOwnerUserId == pending.ownerUserId
			and sourceEggIndex == pending.eggIndex
		local spatialFallback = sourceOwnerUserId == nil
			and sourceEggIndex == nil
			and (pending.position - instance.Position).Magnitude <= 0.75
		if exactSourceMatch or spatialFallback then
			pendingVisuals[egg] = nil
			if pending.splat.Parent then
				pending.splat:Destroy()
			end
			break
		end
	end
end)

Workspace.ChildAdded:Connect(registerEgg)
for _, child in Workspace:GetChildren() do
	registerEgg(child)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for egg, track in trackedEggs do
		if not egg.Parent or not track.collider.Parent then
			unregisterEgg(egg)
		else
			if track.egg:GetAttribute("HasLeftBasket") ~= true
				and not isOutsideBasket(track)
			then
				track.lastBasketPosition = track.collider.Position
			end
			local velocity = track.collider.AssemblyLinearVelocity
			if now > track.recentFastVelocityUntil
				or velocity.Magnitude > track.recentFastVelocity.Magnitude
			then
				track.recentFastVelocity = velocity
				track.recentFastVelocityUntil = now + RECENT_VELOCITY_MEMORY
			end
		end
	end
end)
