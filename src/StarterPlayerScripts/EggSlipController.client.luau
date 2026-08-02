--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local SLIP_DURATION = 0.95
local SLIP_COOLDOWN = 1.00
local MIN_ENTRY_SPEED = 4
local ENTRY_TO_SLIDE_SPEED_MULTIPLIER = 1.60
local MIN_SLIDE_SPEED = 12
local MAX_SLIDE_SPEED = 32
local STEERING_STRENGTH = 0.10
local MAX_CHAIN_SLIDE_SPEED = 44
local CHAIN_SPEED_BOOST = 6
local CHAIN_DIRECTION_INFLUENCE = 0.20
local END_SPEED_MULTIPLIER = 0.55
local DETECTION_INTERVAL = 0.03

local FEET_QUERY_WIDTH = 2.0
local FEET_QUERY_EXTRA_DEPTH = 0.65
local STEERING_RESPONSE = 4.0
local EGG_SPAWN_LOCK_ATTRIBUTE = "EggSpawnMovementLocked"
local POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE = "PostSlipSpeedMultiplier"
local EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE = "EggSlipMovementActive"

local SLIP_START_ANIMATION_ID = "rbxassetid://125100082914442"
local SLIP_STRUGGLE_ANIMATION_ID = "rbxassetid://77524598504382"
local SLIP_RECOVER_ANIMATION_ID = "rbxassetid://80081691988334"
local ANIMATION_LENGTH_TIMEOUT = 5
local SLIP_START_TRANSITION_LEAD = 0.04
local SLIP_START_CROSSFADE = 0.04
local SLIP_STRUGGLE_TRANSITION_LEAD = 0.06
local SLIP_STRUGGLE_CROSSFADE = 0.06
local SLIP_RECOVER_FADE = 0.20
local POST_SLIP_SPEED_MULTIPLIER = 0.60
local POST_SLIP_SPEED_RESTORE_DURATION = 0.80

type VisualState = "Idle" | "SlipStart" | "SlipStruggle" | "SlipRecover" | "PostSlipSlow"

local IsSlipping = false
local LastSlipTime = -math.huge

local character: Model? = nil
local humanoid: Humanoid? = nil
local humanoidRootPart: BasePart? = nil
local characterAnimator: Animator? = nil
local overlapParams: OverlapParams? = nil
local touchingSlipZones: { [BasePart]: boolean } = {}
local detectionAccumulator = 0

local slipStartTime = 0
local initialSlideSpeed = 0
local slideDirection = Vector3.zAxis
local originalAutoRotate: boolean? = nil
local slipAttachment: Attachment? = nil
local slipLinearVelocity: LinearVelocity? = nil

local visualState: VisualState = "Idle"
local sequenceToken = 0
local animationTracksReady = false
local slipStartAnimation: Animation? = nil
local slipStruggleAnimation: Animation? = nil
local slipRecoverAnimation: Animation? = nil
local slipStartTrack: AnimationTrack? = nil
local slipStruggleTrack: AnimationTrack? = nil
local slipRecoverTrack: AnimationTrack? = nil
local slipStartLength: number? = nil
local slipStruggleLength: number? = nil
local slipRecoverLength: number? = nil

local endSlip: (number) -> () = function() end

local characterDiedConnection: RBXScriptConnection? = nil
local characterAncestryConnection: RBXScriptConnection? = nil
local rootAncestryConnection: RBXScriptConnection? = nil

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function stopTrack(track: AnimationTrack?, fadeTime: number)
	if track and track.IsPlaying then
		track:Stop(fadeTime)
	end
end

local function destroyTrack(track: AnimationTrack?)
	if track then
		track:Destroy()
	end
end

local function destroyAnimation(animation: Animation?)
	if animation then
		animation:Destroy()
	end
end

local function resetSlipMovementAttributes()
	local activeCharacter = character
	if activeCharacter and activeCharacter.Parent then
		activeCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
		activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	end
end

local function clearSlipAnimations()
	sequenceToken += 1
	visualState = "Idle"
	animationTracksReady = false

	stopTrack(slipStartTrack, 0.03)
	stopTrack(slipStruggleTrack, 0.03)
	stopTrack(slipRecoverTrack, 0.03)
	resetSlipMovementAttributes()
	destroyTrack(slipStartTrack)
	destroyTrack(slipStruggleTrack)
	destroyTrack(slipRecoverTrack)
	destroyAnimation(slipStartAnimation)
	destroyAnimation(slipStruggleAnimation)
	destroyAnimation(slipRecoverAnimation)

	slipStartAnimation = nil
	slipStruggleAnimation = nil
	slipRecoverAnimation = nil
	slipStartTrack = nil
	slipStruggleTrack = nil
	slipRecoverTrack = nil
	slipStartLength = nil
	slipStruggleLength = nil
	slipRecoverLength = nil
end

local function resolveTrackLength(
	track: AnimationTrack,
	clipName: string,
	setupToken: number
): number?
	local deadline = os.clock() + ANIMATION_LENGTH_TIMEOUT
	while track.Length <= 0 and os.clock() < deadline do
		if sequenceToken ~= setupToken or not script.Enabled then
			return nil
		end
		RunService.Heartbeat:Wait()
	end

	if sequenceToken ~= setupToken then
		return nil
	end
	if track.Length <= 0 then
		warn(string.format("[EggSlipAnim] Failed to resolve %s length", clipName))
		return nil
	end

	return track.Length
end

local function visualSequenceIsCurrent(token: number, expectedState: VisualState): boolean
	local activeHumanoid = humanoid
	return sequenceToken == token
		and visualState == expectedState
		and animationTracksReady
		and activeHumanoid ~= nil
		and activeHumanoid.Parent ~= nil
		and activeHumanoid.Health > 0
end

local function speedRecoveryIsCurrent(
	token: number,
	activeCharacter: Model,
	activeHumanoid: Humanoid
): boolean
	return sequenceToken == token
		and character == activeCharacter
		and activeCharacter.Parent ~= nil
		and humanoid == activeHumanoid
		and activeHumanoid.Parent ~= nil
		and activeHumanoid.Health > 0
		and (visualState == "SlipRecover" or visualState == "PostSlipSlow")
end

local function beginPostSlipSpeedRecovery(token: number): boolean
	local activeCharacter = character
	local activeHumanoid = humanoid
	if not activeCharacter or not activeHumanoid then
		return false
	end

	-- Publish a dimensionless penalty. ShiftSprintController remains the only
	-- owner of Humanoid.WalkSpeed and applies it to normal or sprint speed.
	activeCharacter:SetAttribute(
		POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE,
		POST_SLIP_SPEED_MULTIPLIER
	)
	print("[EggSlipSpeed] penalty start multiplier=0.60")

	-- Remove the controlled slip velocity before normal locomotion resumes.
	endSlip(os.clock())
	activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)

	task.spawn(function()
		local elapsed = 0
		while elapsed < POST_SLIP_SPEED_RESTORE_DURATION do
			local deltaTime = RunService.Heartbeat:Wait()
			if not speedRecoveryIsCurrent(token, activeCharacter, activeHumanoid) then
				return
			end

			elapsed = math.min(elapsed + deltaTime, POST_SLIP_SPEED_RESTORE_DURATION)
			local alpha = elapsed / POST_SLIP_SPEED_RESTORE_DURATION
			local easedAlpha = alpha * alpha * (3 - 2 * alpha)
			local multiplier = POST_SLIP_SPEED_MULTIPLIER
				+ (1 - POST_SLIP_SPEED_MULTIPLIER) * easedAlpha
			activeCharacter:SetAttribute(
				POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE,
				multiplier
			)
		end

		if not speedRecoveryIsCurrent(token, activeCharacter, activeHumanoid) then
			return
		end
		activeCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
		visualState = "Idle"
		print("[EggSlipSpeed] penalty restored multiplier=1.00")
	end)
	return true
end

local function beginSlipVisual()
	if visualState ~= "Idle" then
		return
	end
	if not animationTracksReady then
		warn("[EggSlipAnim] Cannot start because animation tracks are not ready")
		return
	end

	local startTrack = slipStartTrack
	local struggleTrack = slipStruggleTrack
	local recoverTrack = slipRecoverTrack
	local startLength = slipStartLength
	local struggleLength = slipStruggleLength
	local recoverLength = slipRecoverLength
	if not startTrack
		or not struggleTrack
		or not recoverTrack
		or not startLength
		or not struggleLength
		or not recoverLength
	then
		warn("[EggSlipAnim] Cannot start because an animation track length is unavailable")
		return
	end

	sequenceToken += 1
	local token = sequenceToken
	stopTrack(startTrack, 0.02)
	stopTrack(struggleTrack, 0.02)
	stopTrack(recoverTrack, 0.02)

	visualState = "SlipStart"
	startTrack:Play(0.03, 1, 1)

	task.delay(math.max(startLength - SLIP_START_TRANSITION_LEAD, 0), function()
		if not visualSequenceIsCurrent(token, "SlipStart") then
			return
		end

		visualState = "SlipStruggle"
		struggleTrack:Play(SLIP_START_CROSSFADE, 1, 1)
		startTrack:Stop(SLIP_START_CROSSFADE)

		task.delay(math.max(struggleLength - SLIP_STRUGGLE_TRANSITION_LEAD, 0), function()
			if not visualSequenceIsCurrent(token, "SlipStruggle") then
				return
			end

			visualState = "SlipRecover"
			recoverTrack:Play(SLIP_STRUGGLE_CROSSFADE, 1, 1)
			struggleTrack:Stop(SLIP_STRUGGLE_CROSSFADE)

			task.delay(math.max(recoverLength - SLIP_RECOVER_FADE, 0), function()
				if not visualSequenceIsCurrent(token, "SlipRecover") then
					return
				end

				local speedRecoveryStarted = beginPostSlipSpeedRecovery(token)
				recoverTrack:Stop(SLIP_RECOVER_FADE)
				task.delay(SLIP_RECOVER_FADE, function()
					if not visualSequenceIsCurrent(token, "SlipRecover") then
						return
					end
					visualState = if speedRecoveryStarted then "PostSlipSlow" else "Idle"
				end)
			end)
		end)
	end)
end

local function loadSlipAnimations(animator: Animator, setupToken: number): boolean
	local startAnimation = Instance.new("Animation")
	startAnimation.Name = "SlipStartAnimation"
	startAnimation.AnimationId = SLIP_START_ANIMATION_ID
	local struggleAnimation = Instance.new("Animation")
	struggleAnimation.Name = "SlipStruggleAnimation"
	struggleAnimation.AnimationId = SLIP_STRUGGLE_ANIMATION_ID
	local recoverAnimation = Instance.new("Animation")
	recoverAnimation.Name = "SlipRecoverAnimation"
	recoverAnimation.AnimationId = SLIP_RECOVER_ANIMATION_ID

	slipStartAnimation = startAnimation
	slipStruggleAnimation = struggleAnimation
	slipRecoverAnimation = recoverAnimation

	local startTrack = animator:LoadAnimation(startAnimation)
	local struggleTrack = animator:LoadAnimation(struggleAnimation)
	local recoverTrack = animator:LoadAnimation(recoverAnimation)
	startTrack.Priority = Enum.AnimationPriority.Action
	struggleTrack.Priority = Enum.AnimationPriority.Action
	recoverTrack.Priority = Enum.AnimationPriority.Action
	startTrack.Looped = false
	struggleTrack.Looped = false
	recoverTrack.Looped = false

	slipStartTrack = startTrack
	slipStruggleTrack = struggleTrack
	slipRecoverTrack = recoverTrack

	local resolvedStartLength = resolveTrackLength(startTrack, "SlipStart", setupToken)
	local resolvedStruggleLength = resolveTrackLength(struggleTrack, "SlipStruggle", setupToken)
	local resolvedRecoverLength = resolveTrackLength(recoverTrack, "SlipRecover", setupToken)
	if sequenceToken ~= setupToken
		or not resolvedStartLength
		or not resolvedStruggleLength
		or not resolvedRecoverLength
	then
		return false
	end

	slipStartLength = resolvedStartLength
	slipStruggleLength = resolvedStruggleLength
	slipRecoverLength = resolvedRecoverLength
	animationTracksReady = true
	return true
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

endSlip = function(now: number)
	if not IsSlipping then
		destroySlipMovement()
		restoreHumanoidState()
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
	clearSlipAnimations()
	character = nil
	humanoid = nil
	humanoidRootPart = nil
	characterAnimator = nil
	overlapParams = nil
	table.clear(touchingSlipZones)
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

local function beginSlip(now: number): boolean
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	if IsSlipping
		or visualState ~= "Idle"
		or not activeHumanoid
		or not root
		or activeHumanoid.Health <= 0
		or (character and character:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) == true)
		or now - LastSlipTime < SLIP_COOLDOWN
	then
		return false
	end

	local entryDirection, entrySpeed = chooseEntryDirection(activeHumanoid, root)
	if entrySpeed < MIN_ENTRY_SPEED then
		return false
	end
	IsSlipping = true
	if character then
		character:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, true)
	end
	slipStartTime = now
	initialSlideSpeed = math.clamp(
		entrySpeed * ENTRY_TO_SLIDE_SPEED_MULTIPLIER,
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
	return true
end

local function currentSlideSpeed(now: number): number
	local alpha = math.clamp((now - slipStartTime) / SLIP_DURATION, 0, 1)
	local endSpeed = initialSlideSpeed * END_SPEED_MULTIPLIER
	return initialSlideSpeed + (endSpeed - initialSlideSpeed) * alpha
end

local function extendSlip(now: number)
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	local linearVelocity = slipLinearVelocity
	if not IsSlipping or not activeHumanoid or not root or not linearVelocity then
		return
	end

	local entryDirection, _ = chooseEntryDirection(activeHumanoid, root)
	local blendedDirection = slideDirection * (1 - CHAIN_DIRECTION_INFLUENCE)
		+ entryDirection * CHAIN_DIRECTION_INFLUENCE
	if blendedDirection.Magnitude >= 0.05 then
		slideDirection = blendedDirection.Unit
	end

	initialSlideSpeed = math.clamp(
		math.max(currentSlideSpeed(now) + CHAIN_SPEED_BOOST, MIN_SLIDE_SPEED),
		MIN_SLIDE_SPEED,
		MAX_CHAIN_SLIDE_SPEED
	)
	slipStartTime = now
	linearVelocity.PlaneVelocity = Vector2.new(
		slideDirection.X * initialSlideSpeed,
		slideDirection.Z * initialSlideSpeed
	)
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

local function getTouchingSlipZones(): { BasePart }
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	local params = overlapParams
	if not activeHumanoid or not root or not params then
		return {}
	end

	local queryCFrame, querySize = getFeetQuery(activeHumanoid, root)
	local nearbyParts = Workspace:GetPartBoundsInBox(queryCFrame, querySize, params)
	local zones: { BasePart } = {}
	for _, part in nearbyParts do
		if part:GetAttribute("IsEggSlipZone") == true then
			table.insert(zones, part)
		end
	end
	return zones
end

local function updateDetection(now: number)
	local zones = getTouchingSlipZones()
	local currentZones: { [BasePart]: boolean } = {}
	local nearestNewZone: BasePart? = nil
	local nearestDistance = math.huge
	local root = humanoidRootPart

	for _, zone in zones do
		currentZones[zone] = true
		if not touchingSlipZones[zone] and root then
			local distance = (zone.Position - root.Position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestNewZone = zone
			end
		end
	end

	touchingSlipZones = currentZones
	if nearestNewZone then
		if IsSlipping then
			extendSlip(now)
		else
			if beginSlip(now) then
				beginSlipVisual()
			end
		end
	end
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

	local slideSpeed = currentSlideSpeed(now)
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
	local foundAnimator = foundHumanoid:WaitForChild("Animator", 10)
	if not foundAnimator or not foundAnimator:IsA("Animator") or newCharacter ~= player.Character then
		return
	end

	character = newCharacter
	humanoid = foundHumanoid
	humanoidRootPart = foundRoot
	characterAnimator = foundAnimator
	newCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
	newCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	local setupToken = sequenceToken
	if not loadSlipAnimations(foundAnimator, setupToken) then
		if sequenceToken == setupToken and character == newCharacter then
			clearCharacter()
		end
		return
	end
	if sequenceToken ~= setupToken
		or newCharacter ~= player.Character
		or foundHumanoid.Health <= 0
	then
		if sequenceToken == setupToken and character == newCharacter then
			clearCharacter()
		end
		return
	end
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
		table.clear(touchingSlipZones)
		detectionAccumulator = 0
		return
	end

	detectionAccumulator += deltaTime
	if detectionAccumulator >= DETECTION_INTERVAL then
		detectionAccumulator %= DETECTION_INTERVAL
		updateDetection(now)
	end
	updateSlip(now, deltaTime)
end)

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
