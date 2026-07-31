--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local SLIP_DURATION = 0.95
local SLIP_COOLDOWN = 1.00
local MIN_ENTRY_SPEED = 4
local MIN_SLIDE_SPEED = 24
local MAX_SLIDE_SPEED = 32
local STEERING_STRENGTH = 0.10
local END_SPEED_MULTIPLIER = 0.55
local DETECTION_INTERVAL = 0.03

local FEET_QUERY_WIDTH = 2.0
local FEET_QUERY_EXTRA_DEPTH = 0.65
local STEERING_RESPONSE = 4.0
local EGG_SPAWN_LOCK_ATTRIBUTE = "EggSpawnMovementLocked"

local IsSlipping = false
local LastSlipTime = -math.huge

local character: Model? = nil
local humanoid: Humanoid? = nil
local humanoidRootPart: BasePart? = nil
local overlapParams: OverlapParams? = nil
local wasOnSlipZone = false
local detectionAccumulator = 0

local slipStartTime = 0
local initialSlideSpeed = 0
local slideDirection = Vector3.zAxis
local originalAutoRotate: boolean? = nil
local slipAttachment: Attachment? = nil
local slipLinearVelocity: LinearVelocity? = nil

local characterDiedConnection: RBXScriptConnection? = nil
local characterAncestryConnection: RBXScriptConnection? = nil
local rootAncestryConnection: RBXScriptConnection? = nil

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function restoreHumanoidState()
	local activeHumanoid = humanoid
	if activeHumanoid and activeHumanoid.Parent and originalAutoRotate ~= nil then
		activeHumanoid.AutoRotate = originalAutoRotate
	end
	originalAutoRotate = nil
end

local function destroySlipMovement()
	if slipLinearVelocity then
		slipLinearVelocity:Destroy()
		slipLinearVelocity = nil
	end
	if slipAttachment then
		slipAttachment:Destroy()
		slipAttachment = nil
	end
end

local function endSlip(now: number)
	if not IsSlipping then
		return
	end
	IsSlipping = false
	LastSlipTime = now
	destroySlipMovement()
	restoreHumanoidState()
end

local function disconnectCharacterConnections()
	if characterDiedConnection then
		characterDiedConnection:Disconnect()
		characterDiedConnection = nil
	end
	if characterAncestryConnection then
		characterAncestryConnection:Disconnect()
		characterAncestryConnection = nil
	end
	if rootAncestryConnection then
		rootAncestryConnection:Disconnect()
		rootAncestryConnection = nil
	end
end

local function clearCharacter()
	endSlip(os.clock())
	destroySlipMovement()
	restoreHumanoidState()
	disconnectCharacterConnections()
	character = nil
	humanoid = nil
	humanoidRootPart = nil
	overlapParams = nil
	wasOnSlipZone = false
	detectionAccumulator = 0
end

local function chooseEntryDirection(activeHumanoid: Humanoid, root: BasePart): (Vector3, number)
	local horizontalVelocity = horizontal(root.AssemblyLinearVelocity)
	local entrySpeed = horizontalVelocity.Magnitude
	if entrySpeed >= 0.05 then
		return horizontalVelocity.Unit, entrySpeed
	end

	local moveDirection = horizontal(activeHumanoid.MoveDirection)
	if moveDirection.Magnitude >= 0.05 then
		return moveDirection.Unit, entrySpeed
	end

	local lookDirection = horizontal(root.CFrame.LookVector)
	if lookDirection.Magnitude >= 0.05 then
		return lookDirection.Unit, entrySpeed
	end
	return Vector3.zAxis, entrySpeed
end

local function beginSlip(now: number)
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	if IsSlipping
		or not activeHumanoid
		or not root
		or activeHumanoid.Health <= 0
		or (character and character:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) == true)
		or now - LastSlipTime < SLIP_COOLDOWN
	then
		return
	end

	local entryDirection, entrySpeed = chooseEntryDirection(activeHumanoid, root)
	if entrySpeed < MIN_ENTRY_SPEED then
		return
	end

	IsSlipping = true
	slipStartTime = now
	initialSlideSpeed = math.clamp(
		math.max(entrySpeed * 1.20, MIN_SLIDE_SPEED),
		MIN_SLIDE_SPEED,
		MAX_SLIDE_SPEED
	)
	slideDirection = entryDirection
	originalAutoRotate = activeHumanoid.AutoRotate
	activeHumanoid.AutoRotate = false

	destroySlipMovement()
	local attachment = Instance.new("Attachment")
	attachment.Name = "EggSlipAttachment"
	attachment.Parent = root
	slipAttachment = attachment

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "EggSlipLinearVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linearVelocity.PrimaryTangentAxis = Vector3.xAxis
	linearVelocity.SecondaryTangentAxis = Vector3.zAxis
	linearVelocity.PlaneVelocity = Vector2.new(
		slideDirection.X * initialSlideSpeed,
		slideDirection.Z * initialSlideSpeed
	)
	linearVelocity.ForceLimitsEnabled = false
	linearVelocity.Parent = root
	slipLinearVelocity = linearVelocity
end

local function getFeetQuery(
	activeHumanoid: Humanoid,
	root: BasePart
): (CFrame, Vector3)
	-- Cover the narrow column from the root down through the feet. This works
	-- for both R6- and R15-style hip heights without scanning the workspace.
	local queryHeight = math.max(
		activeHumanoid.HipHeight + root.Size.Y * 0.5 + FEET_QUERY_EXTRA_DEPTH,
		1.5
	)
	local queryCenter = root.Position - Vector3.new(0, queryHeight * 0.5, 0)
	return CFrame.new(queryCenter), Vector3.new(FEET_QUERY_WIDTH, queryHeight, FEET_QUERY_WIDTH)
end

local function isStandingOnSlipZone(): boolean
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	local params = overlapParams
	if not activeHumanoid or not root or not params then
		return false
	end

	local queryCFrame, querySize = getFeetQuery(activeHumanoid, root)
	local nearbyParts = Workspace:GetPartBoundsInBox(queryCFrame, querySize, params)
	for _, part in nearbyParts do
		if part:GetAttribute("IsEggSlipZone") == true then
			return true
		end
	end
	return false
end

local function updateDetection(now: number)
	local onSlipZone = isStandingOnSlipZone()
	if onSlipZone and not wasOnSlipZone then
		beginSlip(now)
	end
	-- A zone must be fully exited before it can trigger again. This prevents a
	-- long overlap from retriggering after the cooldown expires.
	wasOnSlipZone = onSlipZone
end

local function updateSlip(now: number, deltaTime: number)
	if not IsSlipping then
		return
	end
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	local linearVelocity = slipLinearVelocity
	if not activeHumanoid
		or not root
		or not root.Parent
		or not linearVelocity
		or not linearVelocity.Parent
		or activeHumanoid.Health <= 0
	then
		endSlip(now)
		return
	end

	local alpha = math.clamp((now - slipStartTime) / SLIP_DURATION, 0, 1)
	if alpha >= 1 then
		endSlip(now)
		return
	end

	local inputDirection = horizontal(activeHumanoid.MoveDirection)
	if inputDirection.Magnitude >= 0.05 then
		inputDirection = inputDirection.Unit
		local steeringTarget = (
			slideDirection * (1 - STEERING_STRENGTH)
				+ inputDirection * STEERING_STRENGTH
		).Unit
		local responseAlpha = math.clamp(deltaTime * STEERING_RESPONSE, 0, 1)
		slideDirection = slideDirection:Lerp(steeringTarget, responseAlpha).Unit
	end

	local endSpeed = initialSlideSpeed * END_SPEED_MULTIPLIER
	local slideSpeed = initialSlideSpeed + (endSpeed - initialSlideSpeed) * alpha
	linearVelocity.PlaneVelocity = Vector2.new(
		slideDirection.X * slideSpeed,
		slideDirection.Z * slideSpeed
	)
end

local function setupCharacter(newCharacter: Model)
	clearCharacter()
	local foundHumanoid = newCharacter:WaitForChild("Humanoid", 10)
	local foundRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if not foundHumanoid
		or not foundHumanoid:IsA("Humanoid")
		or not foundRoot
		or not foundRoot:IsA("BasePart")
		or newCharacter ~= player.Character
	then
		return
	end

	character = newCharacter
	humanoid = foundHumanoid
	humanoidRootPart = foundRoot
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { newCharacter }
	params.MaxParts = 32
	overlapParams = params

	characterDiedConnection = foundHumanoid.Died:Connect(clearCharacter)
	characterAncestryConnection = newCharacter.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearCharacter()
		end
	end)
	rootAncestryConnection = foundRoot.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearCharacter()
		end
	end)
end

player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(function(removingCharacter)
	if removingCharacter == character then
		clearCharacter()
	end
end)

script.Destroying:Connect(clearCharacter)
script:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not script.Enabled then
		clearCharacter()
	end
end)

RunService.PreSimulation:Connect(function(deltaTime: number)
	if not script.Enabled then
		return
	end
	local now = os.clock()
	if character and character:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) == true then
		endSlip(now)
		wasOnSlipZone = false
		detectionAccumulator = 0
		return
	end
	updateSlip(now, deltaTime)

	detectionAccumulator += deltaTime
	if detectionAccumulator >= DETECTION_INTERVAL then
		detectionAccumulator %= DETECTION_INTERVAL
		updateDetection(now)
	end
end)

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
