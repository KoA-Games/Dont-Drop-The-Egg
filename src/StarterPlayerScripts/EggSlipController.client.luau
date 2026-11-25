--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

type ChainMode = "normal" | "sprint"
type FallSide = "Left" | "Right"
type FallCause = "sharpTurn" | "chain"
type FallDirection = "left" | "right" | "back"
type ChainFeedbackKind = "warning" | "threshold"
type SlipContactEvent = {
	id: number,
	creationTime: number,
	rootPosition: Vector3,
	firstYolk: Instance,
	groupedYolks: { [Instance]: boolean },
	chainCountIncreased: boolean,
	extensionApplied: boolean,
}

local NORMAL_SLIP_DURATION = 0.74
local NORMAL_INITIAL_SPEED_RATIO = 1.00
local NORMAL_MOMENTUM_HOLD_TIME = 0.32
local NORMAL_END_SPEED_RATIO = 0.74

local SPRINT_SLIP_DURATION = 0.98
local SPRINT_INITIAL_SPEED_RATIO = 1.00
local SPRINT_MOMENTUM_HOLD_TIME = 0.44
local SPRINT_END_SPEED_RATIO = 0.78

local SPRINT_CHAIN_WARNING_COUNT = 2
local SPRINT_CHAIN_FALL_COUNT = 3
local NORMAL_CHAIN_WARNING_COUNT = 3
local NORMAL_CHAIN_FALL_COUNT = 4

local OVERLAP_EVENT_MERGE_WINDOW = 0.16
local OVERLAP_EVENT_MAX_ROOT_DISTANCE = 1.75
local OVERLAP_BOUNDS_PADDING = 0.25

local SLIP_CHAIN = {
	slipCooldown = 1.00,
	detectionInterval = 0.03,
	minimumValidEntrySpeed = 1.5,
	speedTolerance = 0.25,
	normalGraceTime = 0.90,
	sprintGraceTime = 0.75,
	normalExtension = 0.20,
	sprintExtension = 0.26,
	maxNormalTotalExtension = 0.50,
	maxSprintTotalExtension = 0.65,
	warningPulseDuration = 0.58,
	thresholdPulseDuration = 0.42,
	warningWobbleDuration = 0.32,
	warningWobbleDegrees = 7,
	thresholdWobbleDegrees = 8,
	minimumChainFallCommitTime = 0.38,
	maximumChainFallWait = 0.65,
	countAttribute = "SlipChainCount",
	modeAttribute = "SlipChainMode",
	count = 0,
	mode = nil :: ChainMode?,
	contactedYolks = {} :: { [Instance]: boolean },
	duplicateLoggedYolks = {} :: { [Instance]: boolean },
	currentContactEvent = nil :: SlipContactEvent?,
	nextContactEventId = 0,
	generation = 0,
	resetDeadline = nil :: number?,
	totalExtension = 0,
	recoverNotBefore = 0,
	mostRecentContactTime = 0,
	warningShown = false,
	fallCommitted = false,
	fallCause = nil :: FallCause?,
	fallDirection = nil :: FallDirection?,
	fallCommitTime = 0,
	fallWindowWait = 0,
	struggleVisibleSince = 0,
	recentLateralSide = nil :: FallSide?,
	recentLateralTime = 0,
	nextFallbackSide = "Left" :: FallSide,
	feedbackKind = nil :: ChainFeedbackKind?,
	feedbackStartTime = 0,
	wobbleStartTime = 0,
	wobbleEndTime = 0,
	warningGui = nil :: ScreenGui?,
	countLabel = nil :: TextLabel?,
	dangerLabel = nil :: TextLabel?,
	countScale = nil :: UIScale?,
	dangerScale = nil :: UIScale?,
	edgePulse = nil :: Frame?,
	edgeStroke = nil :: UIStroke?,
}

local FEET_QUERY_WIDTH = 2.0
local FEET_QUERY_EXTRA_DEPTH = 0.65
local EGG_SPAWN_LOCK_ATTRIBUTE = "EggSpawnMovementLocked"
local FALL_MOVEMENT_LOCK_ATTRIBUTE = "FallMovementLocked"
local POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE = "PostSlipSpeedMultiplier"
local EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE = "EggSlipMovementActive"
local IS_SPRINTING_ATTRIBUTE = "IsSprinting"

local SLIP_START_ANIMATION_ID = "rbxassetid://125100082914442"
local SLIP_STRUGGLE_ANIMATION_ID = "rbxassetid://77524598504382"
local SLIP_RECOVER_ANIMATION_ID = "rbxassetid://80081691988334"
local FALL_BACK_LEFT_ANIMATION_ID = "rbxassetid://137848365560941"
local GET_UP_LEFT_ANIMATION_ID = "rbxassetid://83463696986246"
local FALL_BACK_RIGHT_ANIMATION_ID = "rbxassetid://100171026544238"
local GET_UP_RIGHT_ANIMATION_ID = "rbxassetid://137110155427860"
local FALL_STRAIGHT_BACK_ANIMATION_ID = "rbxassetid://120774873304029"
local GET_UP_BACK_ANIMATION_ID = "rbxassetid://120384703491133"
local SLIP_START_TRANSITION_LEAD = 0.04
local SLIP_START_CROSSFADE = 0.04
local SLIP_STRUGGLE_TRANSITION_LEAD = 0.06
local SLIP_STRUGGLE_CROSSFADE = 0.06
local SLIP_RECOVER_FADE = 0.20
local POST_SLIP_SPEED_MULTIPLIER = 0.60
local POST_SLIP_SPEED_RESTORE_DURATION = 0.80

local MIN_VISIBLE_STRUGGLE_TIME = 0.42
local CHAIN_FALL_MIN_STRUGGLE_TIME = 0.42
local SLIP_STRUGGLE_LATE_LEFT_FALL_TIME = 0.66
local SLIP_STRUGGLE_LATE_RIGHT_FALL_TIME = SLIP_STRUGGLE_LATE_LEFT_FALL_TIME
local SLIP_STRUGGLE_PLAYBACK_SPEED = 1.00
type SingleSlipProfile = {
	mode: "normal" | "sprint",
	duration: number,
	initialSpeedRatio: number,
	momentumHoldTime: number,
	endSpeedRatio: number,
}

local NORMAL_SLIP_PROFILE: SingleSlipProfile = {
	mode = "normal",
	duration = NORMAL_SLIP_DURATION,
	initialSpeedRatio = NORMAL_INITIAL_SPEED_RATIO,
	momentumHoldTime = NORMAL_MOMENTUM_HOLD_TIME,
	endSpeedRatio = NORMAL_END_SPEED_RATIO,
}

local SPRINT_SLIP_PROFILE: SingleSlipProfile = {
	mode = "sprint",
	duration = SPRINT_SLIP_DURATION,
	initialSpeedRatio = SPRINT_INITIAL_SPEED_RATIO,
	momentumHoldTime = SPRINT_MOMENTUM_HOLD_TIME,
	endSpeedRatio = SPRINT_END_SPEED_RATIO,
}
local SHARP_TURN = {
	window = 0.18,
	cautionDegrees = 45,
	fallDegrees = 65,
	minimumDirectionMagnitude = 0.55,
	minimumCommittedFeedbackTime = 0.10,
	cautionFadeTime = 0.12,
	iconDuration = 0.32,
	edgeFlashDuration = 0.26,
	trailDuration = 0.22,
	committed = false,
	commitTime = 0,
	token = 0,
	fading = false,
	cautionLogged = false,
	lastAngle = 0,
	lastSource = "camera",
	activeSide = "Left" :: FallSide,
	cameraSamples = {} :: { { timestamp: number, direction: Vector3 } },
	movementSamples = {} :: { { timestamp: number, direction: Vector3 } },
	edgeFlash = nil :: Frame?,
	temporaryTrailObjects = {} :: { Instance },
}
local MODERATE_TURN = {
	-- Named tuning constants. The sharp threshold is read from the existing
	-- detector so this feature cannot silently diverge from directional falls.
	MODERATE_TURN_MIN_ANGLE = 25,
	MODERATE_TURN_STRONG_ANGLE = 45,
	SHARP_TURN_FALL_ANGLE = SHARP_TURN.fallDegrees,
	MILD_TURN_SPEED_MULTIPLIER = 0.92,
	STRONG_TURN_SPEED_MULTIPLIER = 0.82,
	TURN_PENALTY_BLEND_TIME = 0.10,
	TURN_REARM_ANGLE = 15,
	TURN_REARM_DELAY = 0.22,
	mildCharacterRoll = 5,
	mildCharacterYaw = 3.5,
	mildCameraRoll = 1.25,
	mildCameraYaw = 0,
	mildFeedbackDuration = 0.22,
	strongCharacterRoll = 10.5,
	strongCharacterYaw = 7,
	strongCameraRoll = 3,
	strongCameraYaw = 2.5,
	strongFeedbackDuration = 0.28,
	episodeActive = false,
	episodeDirection = nil :: FallSide?,
	episodeBaseSpeed = 0,
	highestTurnTierApplied = 0,
	lastQualifiedTurnTime = 0,
	neutralSince = nil :: number?,
	penaltyBlendActive = false,
	penaltyBlendStartTime = 0,
	penaltyBlendStartSpeed = 0,
	penaltyTargetSpeed = math.huge,
	feedbackTier = 0,
	feedbackStartTime = 0,
	feedbackDuration = 0,
	feedbackSide = nil :: FallSide?,
}
local WARNING_VISUAL = {
	characterCautionRoll = 10,
	characterCautionYaw = 3,
	characterCommittedRoll = 20,
	characterCommittedYaw = 16,
	cameraCautionRoll = 2.5,
	cameraCommittedRoll = 7,
	cameraCommittedYaw = 7,
	cameraCommittedFovIncrease = 4,
}
local WARNING_FEEDBACK_RESPONSE = 14
local TURN_WARNING_RENDER_BINDING = "EggSlipTurnWarning_" .. tostring(player.UserId)
local FALL_TRANSITION_FADE = 0.06
local FALL_ENTRY_TIME_POSITION = 0.12
local FALL_BASKET_RELEASE_DELAY = 0.10
local FALL_FINAL_HOLD_POLL_MARGIN = 1 / 60
local FALL_FINAL_HOLD_OFFSET = 0.02
local FALLEN_HOLD_DURATION = 0.75
local GET_UP_TRANSITION_FADE = 0.06
local GET_UP_FINAL_HOLD_OFFSET = 0.02
local FALL_BASKET_RELEASE_REQUEST_NAME = "FallBasketReleaseRequest"
local FALL_BASKET_RELEASED_ATTRIBUTE = "FallBasketReleased"
local CHAIN_BACK = {
	fallBasketReleaseNormalizedTime = 0.14 / 0.90,
	fallBackImpactNormalizedTime = 0.58 / 0.90,
	getUpHandPlantNormalizedTime = 0.48 / 1.42,
	getUpHalfKneelNormalizedTime = 0.86 / 1.42,
	markerConnections = {} :: { RBXScriptConnection },
	fallAnimation = nil :: Animation?,
	getUpAnimation = nil :: Animation?,
	fallTrack = nil :: AnimationTrack?,
	getUpTrack = nil :: AnimationTrack?,
	fallLength = nil :: number?,
	getUpLength = nil :: number?,
}
local BASKET_RECOVERY = {
	contextActionService = game:GetService("ContextActionService"),
	pathfindingService = game:GetService("PathfindingService"),
	animationId = "rbxassetid://138910186738222",
	walkSpeed = 9,
	standoff = 1.5,
	reachedDistance = 0.6,
	directMoveTime = 1.05,
	approachTimeout = 2.8,
	settleTimeout = 0.5,
	settleLinearSpeed = 1.5,
	settleAngularSpeed = 2.5,
	maxRadius = 10,
	hardRadius = 12,
	targetRefreshInterval = 0.20,
	faceDuration = 0.14,
	pickupFade = 0.05,
	holdTransitionDuration = 0.10,
	grabNormalizedTime = 0.56 / 1.50,
	overheadNormalizedTime = 1.20 / 1.50,
	completeEndOffset = 0.02,
	inputAction = "EggSlipBasketRecoveryInput",
	inputPriority = Enum.ContextActionPriority.High.Value + 50,
	inputLocked = false,
	normalWalkSpeed = 16,
	markerConnections = {} :: { RBXScriptConnection },
	moveTarget = nil :: Vector3?,
	moveToActive = false,
	facingActive = false,
	pickupCompleteHandled = false,
	animation = nil :: Animation?,
	track = nil :: AnimationTrack?,
	length = nil :: number?,
	droppedBasket = nil :: Model?,
	defaultLengths = {
		SlipStart = 0.38,
		SlipStruggle = 0.90,
		SlipRecover = 0.42,
		FallBackLeft = 1.16,
		GetUpLeft = 1.34,
		FallBackRight = 1.16,
		GetUpRight = 1.34,
		FallStraightBack = 0.90,
		GetUpBack = 1.42,
		BasketPickup = 1.50,
	},
}

local CINEMATIC_CAMERA = {
	renderBinding = "EggSlipCinematicCamera_" .. tostring(player.UserId),
	active = false,
	camera = nil :: Camera?,
	savedType = nil :: Enum.CameraType?,
	savedSubject = nil :: Instance?,
	savedFov = nil :: number?,
	startTime = 0,
	orbitDuration = 0.92,
	startDirection = Vector3.zAxis,
	orbitAngle = 0,
	startDistance = 8,
	startHeight = 3,
	currentCFrame = nil :: CFrame?,
}

type VisualState = "Idle"
	| "SlipStart"
	| "SlipStruggle"
	| "SlipRecover"
	| "PostSlipSlow"
	| "FallBackLeft"
	| "FallBackRight"
	| "FallStraightBack"
	| "FallenHold"
	| "GetUpLeft"
	| "GetUpRight"
	| "GetUpBack"
	| "StandingNoBasket"
	| "SeekDroppedBasket"
	| "BasketPickup"
	| "BasketHoldTransition"

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
local slipEntrySpeed = 0
local slideDirection = Vector3.zAxis
local activeSlipProfile: SingleSlipProfile? = nil
local lastControlledSlideSpeed = 0
local maxObservedSlipSpeed = 0
local slipSpeedWarningPrinted = false

local originalAutoRotate: boolean? = nil
local slipAttachment: Attachment? = nil
local slipLinearVelocity: LinearVelocity? = nil

local visualState: VisualState = "Idle"
local sequenceToken = 0
local animationTracksReady = false
local slipStartAnimation: Animation? = nil
local slipStruggleAnimation: Animation? = nil
local slipRecoverAnimation: Animation? = nil
local fallBackLeftAnimation: Animation? = nil
local getUpLeftAnimation: Animation? = nil
local fallBackRightAnimation: Animation? = nil
local getUpRightAnimation: Animation? = nil
local slipStartTrack: AnimationTrack? = nil
local slipStruggleTrack: AnimationTrack? = nil
local slipRecoverTrack: AnimationTrack? = nil
local fallBackLeftTrack: AnimationTrack? = nil
local getUpLeftTrack: AnimationTrack? = nil
local fallBackRightTrack: AnimationTrack? = nil
local getUpRightTrack: AnimationTrack? = nil
local slipStartLength: number? = nil
local slipStruggleLength: number? = nil
local slipRecoverLength: number? = nil
local fallBackLeftLength: number? = nil
local getUpLeftLength: number? = nil
local fallBackRightLength: number? = nil
local getUpRightLength: number? = nil

local fallSavedWalkSpeed: number? = nil
local fallSavedAutoRotate: boolean? = nil
local fallBasketReleased = false
local slipStartedWhileSprinting = false
local committedTurnSide: FallSide? = nil
local activeFallSide: FallSide? = nil
local fallDecisionMade = false
local capturedSlideDirection = Vector3.zAxis
local turnRisk = 0
local displayedTurnRisk = 0
local lastCameraOffset = CFrame.identity
local lastCameraFovOffset = 0
local lastCameraBaseFov: number? = nil
local warningRootJoint: Motor6D? = nil
local warningWaist: Motor6D? = nil
local warningRootBaseC0: CFrame? = nil
local warningWaistBaseC0: CFrame? = nil
local warningGui: ScreenGui? = nil
local warningLabel: TextLabel? = nil
local warningScale: UIScale? = nil
local turnWarningRenderBound = false

local endSlip: (number, string?) -> () = function() end
local beginFallBack: (FallSide, number) -> () = function() end
local beginGetUp: (number) -> () = function() end

local characterDiedConnection: RBXScriptConnection? = nil
local characterAncestryConnection: RBXScriptConnection? = nil
local rootAncestryConnection: RBXScriptConnection? = nil

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function smoothStep(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
end

local function computeSingleSlipSpeed(
	elapsedTime: number,
	entrySpeed: number,
	profile: SingleSlipProfile
): number
	local cappedEntrySpeed = math.max(entrySpeed, 0)
	local initialSpeed = math.min(
		cappedEntrySpeed * profile.initialSpeedRatio,
		cappedEntrySpeed
	)
	if elapsedTime <= profile.momentumHoldTime then
		return initialSpeed
	end

	local decelerationDuration = math.max(
		profile.duration - profile.momentumHoldTime,
		1 / 60
	)
	local decelerationAlpha = smoothStep(
		math.clamp(
			(elapsedTime - profile.momentumHoldTime) / decelerationDuration,
			0,
			1
		)
	)
	local endSpeed = math.min(
		cappedEntrySpeed * profile.endSpeedRatio,
		cappedEntrySpeed
	)
	return math.min(
		initialSpeed + (endSpeed - initialSpeed) * decelerationAlpha,
		cappedEntrySpeed
	)
end

function MODERATE_TURN.reset()
	MODERATE_TURN.episodeActive = false
	MODERATE_TURN.episodeDirection = nil
	MODERATE_TURN.episodeBaseSpeed = 0
	MODERATE_TURN.highestTurnTierApplied = 0
	MODERATE_TURN.lastQualifiedTurnTime = 0
	MODERATE_TURN.neutralSince = nil
	MODERATE_TURN.penaltyBlendActive = false
	MODERATE_TURN.penaltyBlendStartTime = 0
	MODERATE_TURN.penaltyBlendStartSpeed = 0
	MODERATE_TURN.penaltyTargetSpeed = math.huge
	MODERATE_TURN.feedbackTier = 0
	MODERATE_TURN.feedbackStartTime = 0
	MODERATE_TURN.feedbackDuration = 0
	MODERATE_TURN.feedbackSide = nil
end

function MODERATE_TURN.cancel(reason: string)
	local hadEpisode = MODERATE_TURN.episodeActive
		or MODERATE_TURN.feedbackTier > 0
		or MODERATE_TURN.penaltyBlendActive
	if hadEpisode then
		for _, temporaryObject in SHARP_TURN.temporaryTrailObjects do
			if temporaryObject.Parent then
				temporaryObject:Destroy()
			end
		end
		table.clear(SHARP_TURN.temporaryTrailObjects)
	end
	MODERATE_TURN.reset()
	if hadEpisode then
		print(string.format("[ModerateTurn] cancelled reason=%s", reason))
	end
end

function MODERATE_TURN.feedbackStrength(now: number): number
	if MODERATE_TURN.feedbackTier <= 0 or MODERATE_TURN.feedbackDuration <= 0 then
		return 0
	end
	local age = now - MODERATE_TURN.feedbackStartTime
	if age < 0 or age >= MODERATE_TURN.feedbackDuration then
		return 0
	end
	local alpha = age / MODERATE_TURN.feedbackDuration
	local attack = smoothStep(math.clamp(alpha / 0.22, 0, 1))
	local release = 1 - smoothStep(math.clamp((alpha - 0.45) / 0.55, 0, 1))
	return math.min(attack, release)
end

function MODERATE_TURN.applyTier(
	tier: number,
	side: FallSide,
	angle: number,
	now: number
)
	local profile = activeSlipProfile
	if not profile or profile.mode ~= "sprint" then
		return
	end
	local root = humanoidRootPart
	local observedSpeed = if root and root.Parent
		then horizontal(root.AssemblyLinearVelocity).Magnitude
		else lastControlledSlideSpeed
	local currentSpeed = math.min(
		lastControlledSlideSpeed,
		observedSpeed,
		slipEntrySpeed
	)
	if not MODERATE_TURN.episodeActive then
		MODERATE_TURN.episodeActive = true
		MODERATE_TURN.episodeDirection = side
		MODERATE_TURN.episodeBaseSpeed = currentSpeed
		MODERATE_TURN.highestTurnTierApplied = 0
	end
	if tier <= MODERATE_TURN.highestTurnTierApplied then
		return
	end

	local previousTier = MODERATE_TURN.highestTurnTierApplied
	local multiplier = if tier == 2
		then MODERATE_TURN.STRONG_TURN_SPEED_MULTIPLIER
		else MODERATE_TURN.MILD_TURN_SPEED_MULTIPLIER
	local legitimateFinalSpeed = math.min(
		slipEntrySpeed * profile.endSpeedRatio,
		slipEntrySpeed
	)
	local targetSpeed = if MODERATE_TURN.episodeBaseSpeed <= legitimateFinalSpeed
		then MODERATE_TURN.episodeBaseSpeed
		else math.max(
			MODERATE_TURN.episodeBaseSpeed * multiplier,
			legitimateFinalSpeed
		)
	MODERATE_TURN.highestTurnTierApplied = tier
	MODERATE_TURN.penaltyBlendActive = true
	MODERATE_TURN.penaltyBlendStartTime = now
	MODERATE_TURN.penaltyBlendStartSpeed = currentSpeed
	MODERATE_TURN.penaltyTargetSpeed = math.min(
		MODERATE_TURN.penaltyTargetSpeed,
		targetSpeed
	)
	MODERATE_TURN.feedbackTier = tier
	MODERATE_TURN.feedbackStartTime = now
	MODERATE_TURN.feedbackDuration = if tier == 2
		then MODERATE_TURN.strongFeedbackDuration
		else MODERATE_TURN.mildFeedbackDuration
	MODERATE_TURN.feedbackSide = side
	SHARP_TURN.activeSide = side

	if tier == 2 then
		SHARP_TURN.createFootTrails(sequenceToken)
	end
	if previousTier == 1 and tier == 2 then
		print(string.format(
			"[ModerateTurn] upgraded mild->strong side=%s",
			string.lower(side)
		))
	end
	print(string.format(
		"[ModerateTurn] tier=%s side=%s angle=%.1f speedBefore=%.2f speedTarget=%.2f",
		if tier == 2 then "strong" else "mild",
		string.lower(side),
		angle,
		MODERATE_TURN.episodeBaseSpeed,
		targetSpeed
	))
end

function MODERATE_TURN.evaluate(now: number, angle: number, side: FallSide?)
	if angle < MODERATE_TURN.TURN_REARM_ANGLE then
		if MODERATE_TURN.episodeActive then
			MODERATE_TURN.neutralSince = MODERATE_TURN.neutralSince or now
			if now - (MODERATE_TURN.neutralSince :: number)
				>= MODERATE_TURN.TURN_REARM_DELAY
				and now - MODERATE_TURN.lastQualifiedTurnTime
					>= MODERATE_TURN.TURN_REARM_DELAY
			then
				MODERATE_TURN.episodeActive = false
				MODERATE_TURN.episodeDirection = nil
				MODERATE_TURN.episodeBaseSpeed = 0
				MODERATE_TURN.highestTurnTierApplied = 0
				MODERATE_TURN.neutralSince = nil
				print("[ModerateTurn] episode rearmed")
			end
		end
		return
	end
	MODERATE_TURN.neutralSince = nil
	if angle < MODERATE_TURN.MODERATE_TURN_MIN_ANGLE or not side then
		return
	end
	if MODERATE_TURN.episodeActive
		and MODERATE_TURN.episodeDirection ~= side
	then
		return
	end

	MODERATE_TURN.lastQualifiedTurnTime = now
	local tier = if angle >= MODERATE_TURN.MODERATE_TURN_STRONG_ANGLE then 2 else 1
	MODERATE_TURN.applyTier(tier, side, angle, now)
end

function MODERATE_TURN.speedCap(now: number, currentSpeed: number): number
	if not MODERATE_TURN.penaltyBlendActive then
		return currentSpeed
	end
	local alpha = math.clamp(
		(now - MODERATE_TURN.penaltyBlendStartTime)
			/ MODERATE_TURN.TURN_PENALTY_BLEND_TIME,
		0,
		1
	)
	local blendedSpeed = MODERATE_TURN.penaltyBlendStartSpeed
		+ (MODERATE_TURN.penaltyTargetSpeed - MODERATE_TURN.penaltyBlendStartSpeed)
			* smoothStep(alpha)
	if alpha >= 1 then
		MODERATE_TURN.penaltyBlendActive = false
	end
	return math.min(currentSpeed, blendedSpeed)
end

function SLIP_CHAIN.publish()
	local activeCharacter = character
	if not activeCharacter or not activeCharacter.Parent then
		return
	end
	if activeCharacter:GetAttribute(SLIP_CHAIN.countAttribute) ~= SLIP_CHAIN.count then
		activeCharacter:SetAttribute(SLIP_CHAIN.countAttribute, SLIP_CHAIN.count)
	end
	if activeCharacter:GetAttribute(SLIP_CHAIN.modeAttribute) ~= SLIP_CHAIN.mode then
		activeCharacter:SetAttribute(SLIP_CHAIN.modeAttribute, SLIP_CHAIN.mode)
	end
end

function SLIP_CHAIN.reset(reason: string)
	local wasActive = SLIP_CHAIN.count > 0
		or SLIP_CHAIN.mode ~= nil
		or next(SLIP_CHAIN.contactedYolks) ~= nil
	SLIP_CHAIN.generation += 1
	SLIP_CHAIN.count = 0
	SLIP_CHAIN.mode = nil
	SLIP_CHAIN.resetDeadline = nil
	SLIP_CHAIN.totalExtension = 0
	SLIP_CHAIN.recoverNotBefore = 0
	SLIP_CHAIN.mostRecentContactTime = 0
	SLIP_CHAIN.warningShown = false
	SLIP_CHAIN.fallCommitted = false
	-- A fall reset clears the contact chain but must preserve the branch that
	-- already owns the active fall sequence until its cleanup completes.
	if reason ~= "fall" then
		SLIP_CHAIN.fallCause = nil
		SLIP_CHAIN.fallDirection = nil
	end
	SLIP_CHAIN.fallCommitTime = 0
	SLIP_CHAIN.fallWindowWait = 0
	SLIP_CHAIN.struggleVisibleSince = 0
	SLIP_CHAIN.recentLateralSide = nil
	SLIP_CHAIN.recentLateralTime = 0
	SLIP_CHAIN.feedbackKind = nil
	SLIP_CHAIN.feedbackStartTime = 0
	SLIP_CHAIN.wobbleStartTime = 0
	SLIP_CHAIN.wobbleEndTime = 0
	SLIP_CHAIN.currentContactEvent = nil
	table.clear(SLIP_CHAIN.contactedYolks)
	table.clear(SLIP_CHAIN.duplicateLoggedYolks)
	if SLIP_CHAIN.countLabel then
		SLIP_CHAIN.countLabel.Visible = false
	end
	if SLIP_CHAIN.dangerLabel then
		SLIP_CHAIN.dangerLabel.Visible = false
	end
	if SLIP_CHAIN.edgePulse then
		SLIP_CHAIN.edgePulse.Visible = false
	end
	if SLIP_CHAIN.edgeStroke then
		SLIP_CHAIN.edgeStroke.Transparency = 1
	end
	SLIP_CHAIN.publish()
	if wasActive then
		print(string.format(
			"[SlipChain] reset reason=%s generation=%d",
			reason,
			SLIP_CHAIN.generation
		))
	end
end

function SLIP_CHAIN.resolveYolkIdentity(hitPart: BasePart): Instance?
	if hitPart:GetAttribute("IsEggSlipZone") ~= true then
		return nil
	end

	-- EggBreakService creates one invisible SlipHitbox beneath one visible
	-- splat BasePart. Returning the parent makes the complete puddle canonical,
	-- so any future sibling hitboxes still resolve to the same identity. The
	-- Model branch keeps the helper safe if a future visual groups a puddle.
	local parent = hitPart.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("Model")) then
		return parent
	end
	return hitPart
end

function SLIP_CHAIN.getCanonicalYolkBounds(
	yolkIdentity: Instance
): (Vector3?, Vector3?)
	local boundsCFrame: CFrame
	local boundsSize: Vector3
	if yolkIdentity:IsA("Model") then
		if not yolkIdentity:FindFirstChildWhichIsA("BasePart", true) then
			return nil, nil
		end
		boundsCFrame, boundsSize = yolkIdentity:GetBoundingBox()
	elseif yolkIdentity:IsA("BasePart") then
		boundsCFrame = yolkIdentity.CFrame
		boundsSize = yolkIdentity.Size
	else
		return nil, nil
	end

	-- Convert the possibly rotated flat bound into a conservative world-XZ
	-- footprint. This keeps puddle-specific dimensions while avoiding an
	-- oversized global merge radius.
	local halfSize = boundsSize * 0.5
	local extentX = math.abs(boundsCFrame.RightVector.X) * halfSize.X
		+ math.abs(boundsCFrame.UpVector.X) * halfSize.Y
		+ math.abs(boundsCFrame.LookVector.X) * halfSize.Z
	local extentZ = math.abs(boundsCFrame.RightVector.Z) * halfSize.X
		+ math.abs(boundsCFrame.UpVector.Z) * halfSize.Y
		+ math.abs(boundsCFrame.LookVector.Z) * halfSize.Z
	return boundsCFrame.Position, Vector3.new(extentX * 2, 0, extentZ * 2)
end

function SLIP_CHAIN.doYolkPuddlesOverlapXZ(
	yolkA: Instance,
	yolkB: Instance
): boolean
	local centerA, sizeA = SLIP_CHAIN.getCanonicalYolkBounds(yolkA)
	local centerB, sizeB = SLIP_CHAIN.getCanonicalYolkBounds(yolkB)
	if not centerA or not sizeA or not centerB or not sizeB then
		return false
	end
	local delta = centerA - centerB
	return math.abs(delta.X)
		<= (sizeA.X + sizeB.X) * 0.5 + OVERLAP_BOUNDS_PADDING
		and math.abs(delta.Z)
			<= (sizeA.Z + sizeB.Z) * 0.5 + OVERLAP_BOUNDS_PADDING
end

function SLIP_CHAIN.overlapsContactEvent(
	event: SlipContactEvent,
	yolkIdentity: Instance
): boolean
	-- Checking every identity already grouped into this short-lived event gives
	-- transitive clustering: A-B and B-C merge even when A and C do not overlap.
	for groupedYolk in pairs(event.groupedYolks) do
		if groupedYolk.Parent
			and SLIP_CHAIN.doYolkPuddlesOverlapXZ(groupedYolk, yolkIdentity)
		then
			return true
		end
	end
	return false
end

function SLIP_CHAIN.expireContactEvent(now: number): boolean
	local event = SLIP_CHAIN.currentContactEvent
	if not event or now - event.creationTime <= OVERLAP_EVENT_MERGE_WINDOW then
		return false
	end
	SLIP_CHAIN.currentContactEvent = nil
	if RunService:IsStudio() then
		print(string.format("[SlipContactEvent] event expired id=%d", event.id))
	end
	return true
end

function SLIP_CHAIN.createContactEvent(
	yolkIdentity: Instance,
	now: number,
	separateReason: string?
): SlipContactEvent
	SLIP_CHAIN.nextContactEventId += 1
	local root = humanoidRootPart
	local event: SlipContactEvent = {
		id = SLIP_CHAIN.nextContactEventId,
		creationTime = now,
		rootPosition = if root and root.Parent
			then horizontal(root.Position)
			else Vector3.zero,
		firstYolk = yolkIdentity,
		groupedYolks = { [yolkIdentity] = true },
		chainCountIncreased = false,
		extensionApplied = false,
	}
	SLIP_CHAIN.currentContactEvent = event
	local eventId = event.id
	-- Run the cleanup just after the inclusive merge boundary. Incoming contact
	-- callbacks still call expireContactEvent themselves, so a late scheduler
	-- cannot extend the actual 0.16-second merge decision window.
	task.delay(OVERLAP_EVENT_MERGE_WINDOW + 1 / 240, function()
		local currentEvent = SLIP_CHAIN.currentContactEvent
		if currentEvent and currentEvent.id == eventId then
			SLIP_CHAIN.expireContactEvent(os.clock())
		end
	end)
	if separateReason and RunService:IsStudio() then
		print(string.format(
			"[SlipContactEvent] new separate event=%d reason=%s",
			event.id,
			separateReason
		))
	end
	return event
end

function SLIP_CHAIN.graceDuration(): number
	return if SLIP_CHAIN.mode == "sprint"
		then SLIP_CHAIN.sprintGraceTime
		else SLIP_CHAIN.normalGraceTime
end

function SLIP_CHAIN.startGrace()
	local mode = SLIP_CHAIN.mode
	if SLIP_CHAIN.count <= 0 or not mode then
		return
	end

	SLIP_CHAIN.generation += 1
	local expectedGeneration = SLIP_CHAIN.generation
	local duration = SLIP_CHAIN.graceDuration()
	local deadline = os.clock() + duration
	SLIP_CHAIN.resetDeadline = deadline
	print(string.format(
		"[SlipChain] grace started mode=%s duration=%.2f generation=%d",
		mode,
		duration,
		expectedGeneration
	))

	task.delay(duration, function()
		if SLIP_CHAIN.generation ~= expectedGeneration
			or SLIP_CHAIN.resetDeadline ~= deadline
		then
			return
		end
		-- A reset timer is never allowed to erase a chain while any new slip
		-- sequence is active. Its eventual recovery starts a fresh grace timer.
		if IsSlipping
			or visualState == "SlipStart"
			or visualState == "SlipStruggle"
			or visualState == "SlipRecover"
			or visualState == "PostSlipSlow"
		then
			return
		end
		SLIP_CHAIN.reset("timeout")
	end)
end

function SLIP_CHAIN.expireElapsedGrace(now: number)
	if SLIP_CHAIN.resetDeadline
		and now >= SLIP_CHAIN.resetDeadline
		and not IsSlipping
		and visualState == "Idle"
	then
		SLIP_CHAIN.reset("timeout")
	end
end

function SLIP_CHAIN.register(yolkIdentity: Instance, now: number): boolean
	SLIP_CHAIN.expireElapsedGrace(now)
	if SLIP_CHAIN.fallCommitted
		or SLIP_CHAIN.fallCause ~= nil
		or SHARP_TURN.committed
		or committedTurnSide ~= nil
	then
		SLIP_CHAIN.currentContactEvent = nil
		return false
	end
	local expiredByTime = SLIP_CHAIN.expireContactEvent(now)

	if SLIP_CHAIN.contactedYolks[yolkIdentity] then
		if not SLIP_CHAIN.duplicateLoggedYolks[yolkIdentity] then
			SLIP_CHAIN.duplicateLoggedYolks[yolkIdentity] = true
			print(string.format(
				"[SlipChain] duplicate ignored yolk=%s",
				yolkIdentity:GetFullName()
			))
		end
		return false
	end

	local separateReason = if expiredByTime then "time" else nil
	local event = SLIP_CHAIN.currentContactEvent
	if event then
		local root = humanoidRootPart
		local rootDistance = if root and root.Parent
			then (horizontal(root.Position) - event.rootPosition).Magnitude
			else math.huge
		local elapsed = now - event.creationTime
		local spatialOverlap = SLIP_CHAIN.overlapsContactEvent(event, yolkIdentity)
		if RunService:IsStudio() then
			print(string.format(
				"[SlipContactEvent] overlapCheck time=%.3f rootDistance=%.3f spatialOverlap=%s",
				elapsed,
				rootDistance,
				tostring(spatialOverlap)
			))
		end

		if elapsed > OVERLAP_EVENT_MERGE_WINDOW then
			separateReason = "time"
		elseif rootDistance > OVERLAP_EVENT_MAX_ROOT_DISTANCE then
			separateReason = "distance"
		elseif not spatialOverlap then
			separateReason = "no-overlap"
		else
			event.groupedYolks[yolkIdentity] = true
			SLIP_CHAIN.contactedYolks[yolkIdentity] = true
			if RunService:IsStudio() then
				print(string.format(
					"[SlipContactEvent] overlap merged event=%d yolk=%s countUnchanged=%d",
					event.id,
					yolkIdentity:GetFullName(),
					SLIP_CHAIN.count
				))
			end
			return false
		end
	end

	local contactEvent = SLIP_CHAIN.createContactEvent(yolkIdentity, now, separateReason)
	local continuedAfterRecovery = SLIP_CHAIN.count > 0 and not IsSlipping
	if SLIP_CHAIN.count == 0 then
		table.clear(SLIP_CHAIN.contactedYolks)
		table.clear(SLIP_CHAIN.duplicateLoggedYolks)
		SLIP_CHAIN.mode = if character
			and character:GetAttribute(IS_SPRINTING_ATTRIBUTE) == true
			then "sprint"
			else "normal"
		SLIP_CHAIN.count = 1
		SLIP_CHAIN.contactedYolks[yolkIdentity] = true
		SLIP_CHAIN.generation += 1
		SLIP_CHAIN.resetDeadline = nil
		SLIP_CHAIN.mostRecentContactTime = now
		contactEvent.chainCountIncreased = true
		SLIP_CHAIN.publish()
		if RunService:IsStudio() then
			print(string.format(
				"[SlipContactEvent] new event=%d count=%d yolk=%s",
				contactEvent.id,
				SLIP_CHAIN.count,
				yolkIdentity:GetFullName()
			))
		end
		print(string.format(
			"[SlipChain] started mode=%s count=1 yolk=%s",
			SLIP_CHAIN.mode :: ChainMode,
			yolkIdentity:GetFullName()
		))
		return true
	end

	-- A distinct valid contact owns the chain before an older grace callback
	-- can run. It changes tracking only; the current movement and animation
	-- sequence tokens remain untouched.
	SLIP_CHAIN.generation += 1
	SLIP_CHAIN.resetDeadline = nil
	SLIP_CHAIN.contactedYolks[yolkIdentity] = true
	SLIP_CHAIN.count += 1
	SLIP_CHAIN.mostRecentContactTime = now
	contactEvent.chainCountIncreased = true
	SLIP_CHAIN.publish()
	if RunService:IsStudio() then
		print(string.format(
			"[SlipContactEvent] new event=%d count=%d yolk=%s",
			contactEvent.id,
			SLIP_CHAIN.count,
			yolkIdentity:GetFullName()
		))
	end
	if continuedAfterRecovery then
		print(string.format(
			"[SlipChain] grace continued count=%d yolk=%s",
			SLIP_CHAIN.count,
			yolkIdentity:GetFullName()
		))
	end
	return true
end

function SLIP_CHAIN.extendActive(now: number): number
	local contactEvent = SLIP_CHAIN.currentContactEvent
	if contactEvent and contactEvent.extensionApplied then
		return 0
	end
	if contactEvent then
		contactEvent.extensionApplied = true
	end
	local sprintChain = SLIP_CHAIN.mode == "sprint"
	local perContact = if sprintChain
		then SLIP_CHAIN.sprintExtension
		else SLIP_CHAIN.normalExtension
	local maximum = if sprintChain
		then SLIP_CHAIN.maxSprintTotalExtension
		else SLIP_CHAIN.maxNormalTotalExtension
	local extension = math.min(
		perContact,
		math.max(maximum - SLIP_CHAIN.totalExtension, 0)
	)
	if extension <= 0 then
		return 0
	end

	-- A chained puddle may only preserve or reduce the target already owned by
	-- the active LinearVelocity. It never recaptures entry speed or velocity.
	local root = humanoidRootPart
	if root and root.Parent then
		local observedSpeed = horizontal(root.AssemblyLinearVelocity).Magnitude
		lastControlledSlideSpeed = math.min(
			lastControlledSlideSpeed,
			observedSpeed,
			slipEntrySpeed
		)
	end
	SLIP_CHAIN.totalExtension += extension
	SLIP_CHAIN.recoverNotBefore = math.max(
		SLIP_CHAIN.recoverNotBefore,
		now
	) + extension
	return extension
end

local function warningAngles(risk: number): (number, number)
	if risk <= 0 then
		return 0, 0
	end
	if not SHARP_TURN.committed then
		if MODERATE_TURN.feedbackTier == 2 then
			return MODERATE_TURN.strongCharacterRoll * risk,
				MODERATE_TURN.strongCharacterYaw * risk
		elseif MODERATE_TURN.feedbackTier == 1 then
			return MODERATE_TURN.mildCharacterRoll * risk,
				MODERATE_TURN.mildCharacterYaw * risk
		end
		return WARNING_VISUAL.characterCautionRoll * risk,
			WARNING_VISUAL.characterCautionYaw * risk
	end

	local age = math.max(os.clock() - SHARP_TURN.commitTime, 0)
	local ramp = smoothStep(math.clamp(age / 0.08, 0, 1))
	local heldStrength = if age <= 0.10
		then ramp
		else 1 - 0.28 * smoothStep(math.clamp((age - 0.10) / 0.18, 0, 1))
	return WARNING_VISUAL.characterCommittedRoll * heldStrength,
		WARNING_VISUAL.characterCommittedYaw * heldStrength
end

local function turnDirectionSign(): number
	return if SHARP_TURN.activeSide == "Right" then -1 else 1
end

local function cameraWarningValues(risk: number): (number, number, number)
	if risk <= 0 then
		return 0, 0, 0
	end
	if not SHARP_TURN.committed then
		if MODERATE_TURN.feedbackTier == 2 then
			return MODERATE_TURN.strongCameraYaw * risk,
				MODERATE_TURN.strongCameraRoll * risk,
				0
		elseif MODERATE_TURN.feedbackTier == 1 then
			return MODERATE_TURN.mildCameraYaw * risk,
				MODERATE_TURN.mildCameraRoll * risk,
				0
		end
		return 0, WARNING_VISUAL.cameraCautionRoll * risk, 0
	end

	local age = math.max(os.clock() - SHARP_TURN.commitTime, 0)
	local impact: number
	if age <= 0.08 then
		impact = smoothStep(age / 0.08)
	else
		impact = 1 - 0.58 * smoothStep(math.clamp((age - 0.08) / 0.22, 0, 1))
	end
	return WARNING_VISUAL.cameraCommittedYaw * impact,
		WARNING_VISUAL.cameraCommittedRoll * impact,
		WARNING_VISUAL.cameraCommittedFovIncrease * impact
end

local function restoreCharacterWarningPose()
	if warningRootJoint and warningRootJoint.Parent and warningRootBaseC0 then
		warningRootJoint.C0 = warningRootBaseC0
	end
	if warningWaist and warningWaist.Parent and warningWaistBaseC0 then
		warningWaist.C0 = warningWaistBaseC0
	end
end

local function restoreCameraWarning()
	local activeCamera = Workspace.CurrentCamera
	if activeCamera then
		-- Outside the post-camera render callback, the camera can still contain
		-- our most recent local offset. Remove that one offset exactly once.
		activeCamera.CFrame = activeCamera.CFrame * lastCameraOffset:Inverse()
		if lastCameraBaseFov then
			activeCamera.FieldOfView = lastCameraBaseFov
		else
			activeCamera.FieldOfView -= lastCameraFovOffset
		end
	end
	lastCameraOffset = CFrame.identity
	lastCameraFovOffset = 0
	lastCameraBaseFov = nil
end

CINEMATIC_CAMERA.framing = function(): (number, number, number)
	if visualState == "FallBackLeft"
		or visualState == "FallBackRight"
		or visualState == "FallStraightBack"
		or visualState == "FallenHold"
	then
		return 12.0, 4.2, 1.30
	elseif visualState == "GetUpLeft"
		or visualState == "GetUpRight"
		or visualState == "GetUpBack"
	then
		return 11.8, 4.0, 1.45
	elseif visualState == "SeekDroppedBasket" then
		return 13.0, 4.5, 1.50
	elseif visualState == "BasketPickup" or visualState == "BasketHoldTransition" then
		return 12.2, 4.2, 1.65
	end
	return 12.0, 4.2, 1.50
end

CINEMATIC_CAMERA.rotateHorizontal = function(direction: Vector3, angle: number): Vector3
	return CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(direction)
end

CINEMATIC_CAMERA.chooseOrbitAngle = function(
	startDirection: Vector3,
	targetDirection: Vector3,
	preferredSide: Vector3
): number
	local dot = math.clamp(startDirection:Dot(targetDirection), -1, 1)
	local shortest = math.atan2(startDirection:Cross(targetDirection).Y, dot)
	local alternate = shortest + if shortest >= 0 then -2 * math.pi else 2 * math.pi
	local shortestMid = CINEMATIC_CAMERA.rotateHorizontal(startDirection, shortest * 0.5)
	local alternateMid = CINEMATIC_CAMERA.rotateHorizontal(startDirection, alternate * 0.5)
	return if alternateMid:Dot(preferredSide) > shortestMid:Dot(preferredSide)
		then alternate
		else shortest
end

CINEMATIC_CAMERA.update = function(deltaTime: number)
	if not CINEMATIC_CAMERA.active then
		return
	end
	local activeCamera = Workspace.CurrentCamera
	local root = humanoidRootPart
	if not activeCamera or not root or not root.Parent then
		return
	end

	activeCamera.CameraType = Enum.CameraType.Scriptable
	local forward = horizontal(root.CFrame.LookVector)
	if forward.Magnitude < 0.05 then
		forward = capturedSlideDirection
	end
	forward = if forward.Magnitude > 0.05 then forward.Unit else Vector3.zAxis
	local right = horizontal(root.CFrame.RightVector)
	right = if right.Magnitude > 0.05 then right.Unit else Vector3.xAxis
	-- Keep the final view almost head-on. The tiny right bias makes the opening
	-- orbit finish on the opposite side without losing the character's face.
	local orbitSideSign = if activeFallSide == "Right" then -1 else 1
	local frontRight = (forward + right * (0.06 * orbitSideSign)).Unit
	local distance, height, focusHeight = CINEMATIC_CAMERA.framing()
	local elapsed = os.clock() - CINEMATIC_CAMERA.startTime
	local orbitAlpha = math.clamp(elapsed / CINEMATIC_CAMERA.orbitDuration, 0, 1)
	local orbitDirection: Vector3
	if orbitAlpha < 1 then
		local eased = smoothStep(orbitAlpha)
		orbitDirection = CINEMATIC_CAMERA.rotateHorizontal(
			CINEMATIC_CAMERA.startDirection,
			CINEMATIC_CAMERA.orbitAngle * eased
		).Unit
		distance = CINEMATIC_CAMERA.startDistance
			+ (distance - CINEMATIC_CAMERA.startDistance) * eased
		height = CINEMATIC_CAMERA.startHeight
			+ (height - CINEMATIC_CAMERA.startHeight) * eased
	else
		-- Follow the direction the character is actually facing. CFrame damping
		-- below turns this into a natural follow instead of a state-to-state cut.
		orbitDirection = frontRight
	end

	local focusPosition = root.Position + Vector3.yAxis * focusHeight
	local cameraPosition = root.Position
		+ orbitDirection * distance
		+ Vector3.yAxis * height
	local desiredCFrame = CFrame.lookAt(cameraPosition, focusPosition, Vector3.yAxis)
	-- Damp every frame, including the opening orbit and framing changes. This
	-- prevents the camera from snapping when the character turns, stands up,
	-- starts walking toward the basket, or begins the pickup animation.
	local followResponse = if orbitAlpha < 1 then 7.0 else 4.5
	local response = 1 - math.exp(-followResponse * deltaTime)
	CINEMATIC_CAMERA.currentCFrame = if CINEMATIC_CAMERA.currentCFrame
		then CINEMATIC_CAMERA.currentCFrame:Lerp(desiredCFrame, response)
		else desiredCFrame
	activeCamera.CFrame = CINEMATIC_CAMERA.currentCFrame :: CFrame
	-- Preserve the player's original FOV. The wider distance supplies the full
	-- body/basket framing without the previous close-up effect.
	activeCamera.FieldOfView = CINEMATIC_CAMERA.savedFov or activeCamera.FieldOfView
end

CINEMATIC_CAMERA.finish = function()
	if not CINEMATIC_CAMERA.active then
		return
	end
	RunService:UnbindFromRenderStep(CINEMATIC_CAMERA.renderBinding)
	local activeCamera = Workspace.CurrentCamera
	if activeCamera then
		if CINEMATIC_CAMERA.savedFov then
			activeCamera.FieldOfView = CINEMATIC_CAMERA.savedFov
		end
		local savedSubject = CINEMATIC_CAMERA.savedSubject
		if savedSubject and savedSubject.Parent then
			activeCamera.CameraSubject = savedSubject
		elseif humanoid and humanoid.Parent then
			activeCamera.CameraSubject = humanoid
		end
		activeCamera.CameraType = CINEMATIC_CAMERA.savedType or Enum.CameraType.Custom
	end
	CINEMATIC_CAMERA.active = false
	CINEMATIC_CAMERA.camera = nil
	CINEMATIC_CAMERA.savedType = nil
	CINEMATIC_CAMERA.savedSubject = nil
	CINEMATIC_CAMERA.savedFov = nil
	CINEMATIC_CAMERA.currentCFrame = nil
end

CINEMATIC_CAMERA.begin = function()
	if CINEMATIC_CAMERA.active then
		return
	end
	local activeCamera = Workspace.CurrentCamera
	local root = humanoidRootPart
	if not activeCamera or not root then
		return
	end
	local forward = horizontal(root.CFrame.LookVector)
	forward = if forward.Magnitude > 0.05 then forward.Unit else capturedSlideDirection
	forward = if forward.Magnitude > 0.05 then forward.Unit else Vector3.zAxis
	local right = horizontal(root.CFrame.RightVector)
	right = if right.Magnitude > 0.05 then right.Unit else Vector3.xAxis
	local orbitSideSign = if activeFallSide == "Right" then -1 else 1
	local targetDirection = (forward + right * (0.06 * orbitSideSign)).Unit
	local startOffset = horizontal(activeCamera.CFrame.Position - root.Position)
	local startDirection = if startOffset.Magnitude > 0.05
		then startOffset.Unit
		else -forward

	CINEMATIC_CAMERA.active = true
	CINEMATIC_CAMERA.camera = activeCamera
	CINEMATIC_CAMERA.savedType = activeCamera.CameraType
	CINEMATIC_CAMERA.savedSubject = activeCamera.CameraSubject
	CINEMATIC_CAMERA.savedFov = activeCamera.FieldOfView
	CINEMATIC_CAMERA.startTime = os.clock()
	CINEMATIC_CAMERA.startDirection = startDirection
	CINEMATIC_CAMERA.orbitAngle = CINEMATIC_CAMERA.chooseOrbitAngle(
		startDirection,
		targetDirection,
		right * orbitSideSign
	)
	CINEMATIC_CAMERA.startDistance = math.clamp(startOffset.Magnitude, 7.0, 14.0)
	CINEMATIC_CAMERA.startHeight = math.clamp(
		activeCamera.CFrame.Position.Y - root.Position.Y,
		2.0,
		5.5
	)
	CINEMATIC_CAMERA.currentCFrame = activeCamera.CFrame
	activeCamera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(
		CINEMATIC_CAMERA.renderBinding,
		Enum.RenderPriority.Camera.Value + 2,
		CINEMATIC_CAMERA.update
	)
end

local function hideTurnWarningGui()
	local label = warningLabel
	if label and label.Parent then
		label.Visible = false
		label.Text = if SHARP_TURN.activeSide == "Right"
			then "↷\nSHARP TURN"
			else "↶\nSHARP TURN"
		label.TextColor3 = Color3.fromRGB(255, 214, 48)
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end
	local scale = warningScale
	if scale and scale.Parent then
		scale.Scale = 1
	end
	local edgeFlash = SHARP_TURN.edgeFlash
	if edgeFlash and edgeFlash.Parent then
		edgeFlash.Visible = false
		edgeFlash.BackgroundTransparency = 1
	end
end

local function resetTurnFeedback(clearCommitment: boolean)
	restoreCharacterWarningPose()
	restoreCameraWarning()
	hideTurnWarningGui()
	table.clear(SHARP_TURN.cameraSamples)
	table.clear(SHARP_TURN.movementSamples)
	if clearCommitment or committedTurnSide == nil then
		for _, temporaryObject in SHARP_TURN.temporaryTrailObjects do
			if temporaryObject.Parent then
				temporaryObject:Destroy()
			end
		end
		table.clear(SHARP_TURN.temporaryTrailObjects)
	end
	turnRisk = 0
	displayedTurnRisk = 0
	SHARP_TURN.token = 0
	SHARP_TURN.fading = false
	SHARP_TURN.cautionLogged = false
	SHARP_TURN.lastAngle = 0
	SHARP_TURN.lastSource = "camera"
	SHARP_TURN.committed = false
	SHARP_TURN.commitTime = 0
	MODERATE_TURN.reset()
	if clearCommitment then
		committedTurnSide = nil
		SHARP_TURN.activeSide = "Left"
	end
end

local function beginTurnFeedbackFadeOut()
	SHARP_TURN.fading = true
	table.clear(SHARP_TURN.cameraSamples)
	table.clear(SHARP_TURN.movementSamples)
end

local function destroyTurnWarningGui()
	if warningGui then
		warningGui:Destroy()
	end
	warningGui = nil
	warningLabel = nil
	warningScale = nil
	SHARP_TURN.edgeFlash = nil
end

local function createTurnWarningGui()
	destroyTurnWarningGui()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local existing = playerGui:FindFirstChild("SlipTurnWarningGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SlipTurnWarningGui"
	gui.DisplayOrder = 25
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "WarningLabel"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.70)
	label.Size = UDim2.new(0.46, 0, 0, 112)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = "↶\nSHARP TURN"
	label.TextColor3 = Color3.fromRGB(255, 214, 48)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(58, 12, 8)
	label.TextStrokeTransparency = 1
	label.TextTransparency = 1
	label.Visible = false
	label.ZIndex = 1
	label.Parent = gui

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MinTextSize = 22
	sizeConstraint.MaxTextSize = 52
	sizeConstraint.Parent = label

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = label

	local edgeFlash = Instance.new("Frame")
	edgeFlash.Name = "LeftOversteerFlash"
	edgeFlash.AnchorPoint = Vector2.new(0, 0.5)
	edgeFlash.Position = UDim2.fromScale(0, 0.5)
	edgeFlash.Size = UDim2.fromScale(0.24, 1)
	edgeFlash.BackgroundColor3 = Color3.fromRGB(255, 38, 25)
	edgeFlash.BackgroundTransparency = 1
	edgeFlash.BorderSizePixel = 0
	edgeFlash.Visible = false
	edgeFlash.ZIndex = 0
	edgeFlash.Parent = gui

	local edgeGradient = Instance.new("UIGradient")
	edgeGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 34, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 36)),
	})
	edgeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	edgeGradient.Parent = edgeFlash

	warningGui = gui
	warningLabel = label
	warningScale = scale
	SHARP_TURN.edgeFlash = edgeFlash
end

function SLIP_CHAIN.hideWarningFeedback()
	SLIP_CHAIN.feedbackKind = nil
	SLIP_CHAIN.feedbackStartTime = 0
	SLIP_CHAIN.wobbleStartTime = 0
	SLIP_CHAIN.wobbleEndTime = 0
	if SLIP_CHAIN.countLabel then
		SLIP_CHAIN.countLabel.Visible = false
	end
	if SLIP_CHAIN.dangerLabel then
		SLIP_CHAIN.dangerLabel.Visible = false
	end
	if SLIP_CHAIN.edgePulse then
		SLIP_CHAIN.edgePulse.Visible = false
	end
	if SLIP_CHAIN.edgeStroke then
		SLIP_CHAIN.edgeStroke.Transparency = 1
	end
	if SLIP_CHAIN.countScale then
		SLIP_CHAIN.countScale.Scale = 1
	end
	if SLIP_CHAIN.dangerScale then
		SLIP_CHAIN.dangerScale.Scale = 1
	end
end

function SLIP_CHAIN.destroyWarningGui()
	SLIP_CHAIN.hideWarningFeedback()
	if SLIP_CHAIN.warningGui then
		SLIP_CHAIN.warningGui:Destroy()
	end
	SLIP_CHAIN.warningGui = nil
	SLIP_CHAIN.countLabel = nil
	SLIP_CHAIN.dangerLabel = nil
	SLIP_CHAIN.countScale = nil
	SLIP_CHAIN.dangerScale = nil
	SLIP_CHAIN.edgePulse = nil
	SLIP_CHAIN.edgeStroke = nil
end

function SLIP_CHAIN.createWarningGui()
	SLIP_CHAIN.destroyWarningGui()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local existing = playerGui:FindFirstChild("SlipChainWarningGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SlipChainWarningGui"
	gui.DisplayOrder = 26
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local edgePulse = Instance.new("Frame")
	edgePulse.Name = "DangerEdgePulse"
	edgePulse.AnchorPoint = Vector2.new(0.5, 0.5)
	edgePulse.Position = UDim2.fromScale(0.5, 0.5)
	edgePulse.Size = UDim2.new(1, -20, 1, -20)
	edgePulse.BackgroundTransparency = 1
	edgePulse.BorderSizePixel = 0
	edgePulse.Active = false
	edgePulse.Visible = false
	edgePulse.ZIndex = 0
	edgePulse.Parent = gui

	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Name = "DangerStroke"
	edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edgeStroke.Color = Color3.fromRGB(255, 55, 28)
	edgeStroke.Thickness = 18
	edgeStroke.Transparency = 1
	edgeStroke.Parent = edgePulse

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	countLabel.Position = UDim2.fromScale(0.5, 0.625)
	countLabel.Size = UDim2.new(0.34, 0, 0, 58)
	countLabel.BackgroundTransparency = 1
	countLabel.Active = false
	countLabel.Font = Enum.Font.GothamBlack
	countLabel.Text = "SLIP 2/3"
	countLabel.TextColor3 = Color3.fromRGB(255, 190, 38)
	countLabel.TextScaled = true
	countLabel.TextStrokeColor3 = Color3.fromRGB(45, 16, 5)
	countLabel.TextStrokeTransparency = 0.06
	countLabel.Visible = false
	countLabel.ZIndex = 2
	countLabel.Parent = gui

	local countConstraint = Instance.new("UITextSizeConstraint")
	countConstraint.MinTextSize = 22
	countConstraint.MaxTextSize = 48
	countConstraint.Parent = countLabel
	local countScale = Instance.new("UIScale")
	countScale.Scale = 1
	countScale.Parent = countLabel

	local dangerLabel = Instance.new("TextLabel")
	dangerLabel.Name = "DangerLabel"
	dangerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	dangerLabel.Position = UDim2.fromScale(0.5, 0.685)
	dangerLabel.Size = UDim2.new(0.38, 0, 0, 54)
	dangerLabel.BackgroundTransparency = 1
	dangerLabel.Active = false
	dangerLabel.Font = Enum.Font.GothamBlack
	dangerLabel.Text = "ONE MORE!"
	dangerLabel.TextColor3 = Color3.fromRGB(255, 205, 65)
	dangerLabel.TextScaled = true
	dangerLabel.TextStrokeColor3 = Color3.fromRGB(45, 16, 5)
	dangerLabel.TextStrokeTransparency = 0.06
	dangerLabel.Visible = false
	dangerLabel.ZIndex = 2
	dangerLabel.Parent = gui

	local dangerConstraint = Instance.new("UITextSizeConstraint")
	dangerConstraint.MinTextSize = 20
	dangerConstraint.MaxTextSize = 44
	dangerConstraint.Parent = dangerLabel
	local dangerScale = Instance.new("UIScale")
	dangerScale.Scale = 1
	dangerScale.Parent = dangerLabel

	SLIP_CHAIN.warningGui = gui
	SLIP_CHAIN.countLabel = countLabel
	SLIP_CHAIN.dangerLabel = dangerLabel
	SLIP_CHAIN.countScale = countScale
	SLIP_CHAIN.dangerScale = dangerScale
	SLIP_CHAIN.edgePulse = edgePulse
	SLIP_CHAIN.edgeStroke = edgeStroke
end

function SLIP_CHAIN.showWarningFeedback(kind: ChainFeedbackKind, now: number)
	local mode = SLIP_CHAIN.mode
	local countLabel = SLIP_CHAIN.countLabel
	local dangerLabel = SLIP_CHAIN.dangerLabel
	if not mode or not countLabel or not dangerLabel then
		return
	end
	local threshold = if mode == "sprint"
		then SPRINT_CHAIN_FALL_COUNT
		else NORMAL_CHAIN_FALL_COUNT
	local isThreshold = kind == "threshold"
	SLIP_CHAIN.feedbackKind = kind
	SLIP_CHAIN.feedbackStartTime = now
	SLIP_CHAIN.wobbleStartTime = now
	SLIP_CHAIN.wobbleEndTime = now + SLIP_CHAIN.warningWobbleDuration
	countLabel.Text = string.format(
		"SLIP %d/%d%s",
		SLIP_CHAIN.count,
		threshold,
		if isThreshold then "!" else ""
	)
	dangerLabel.Text = if isThreshold then "LOST BALANCE!" else "ONE MORE!"
	local color = if isThreshold
		then Color3.fromRGB(255, 72, 35)
		else Color3.fromRGB(255, 190, 38)
	countLabel.TextColor3 = color
	dangerLabel.TextColor3 = if isThreshold
		then Color3.fromRGB(255, 105, 48)
		else Color3.fromRGB(255, 215, 72)
	countLabel.Visible = true
	dangerLabel.Visible = true
end

function SLIP_CHAIN.currentWarningRoll(now: number): number
	if now >= SLIP_CHAIN.wobbleEndTime
		or SLIP_CHAIN.wobbleEndTime <= SLIP_CHAIN.wobbleStartTime
	then
		return 0
	end
	local duration = SLIP_CHAIN.wobbleEndTime - SLIP_CHAIN.wobbleStartTime
	local alpha = math.clamp((now - SLIP_CHAIN.wobbleStartTime) / duration, 0, 1)
	local amplitude = if SLIP_CHAIN.feedbackKind == "threshold"
		then SLIP_CHAIN.thresholdWobbleDegrees
		else SLIP_CHAIN.warningWobbleDegrees
	local envelope = math.sin(alpha * math.pi)
	return math.sin(alpha * math.pi * 4) * envelope * amplitude
end

function SLIP_CHAIN.updateWarningFeedback(now: number)
	local kind = SLIP_CHAIN.feedbackKind
	local countLabel = SLIP_CHAIN.countLabel
	local dangerLabel = SLIP_CHAIN.dangerLabel
	local countScale = SLIP_CHAIN.countScale
	local dangerScale = SLIP_CHAIN.dangerScale
	if not kind or not countLabel or not dangerLabel or not countScale or not dangerScale then
		return
	end
	local age = math.max(now - SLIP_CHAIN.feedbackStartTime, 0)
	if kind == "threshold" then
		local duration = SLIP_CHAIN.thresholdPulseDuration
		if age >= duration then
			SLIP_CHAIN.hideWarningFeedback()
			return
		end
		local alpha = age / duration
		local opacity = math.sin(alpha * math.pi)
		local punch = if alpha < 0.22
			then 0.86 + 0.30 * smoothStep(alpha / 0.22)
			else 1.16 - 0.16 * smoothStep((alpha - 0.22) / 0.78)
		countScale.Scale = punch
		dangerScale.Scale = 0.94 + (punch - 0.94) * 0.88
		countLabel.TextTransparency = 1 - opacity
		dangerLabel.TextTransparency = 1 - opacity
		countLabel.TextStrokeTransparency = 1 - opacity * 0.94
		dangerLabel.TextStrokeTransparency = 1 - opacity * 0.94
		if SLIP_CHAIN.edgePulse and SLIP_CHAIN.edgeStroke then
			SLIP_CHAIN.edgePulse.Visible = true
			SLIP_CHAIN.edgeStroke.Transparency = 1 - opacity * 0.62
		end
		return
	end

	local duration = SLIP_CHAIN.warningPulseDuration
	if age < duration then
		local alpha = age / duration
		local punch = if alpha < 0.18
			then 0.88 + 0.28 * smoothStep(alpha / 0.18)
			else 1.16 - 0.16 * smoothStep((alpha - 0.18) / 0.82)
		countScale.Scale = punch
		dangerScale.Scale = 0.94 + (punch - 0.94) * 0.82
		countLabel.TextTransparency = 0
		dangerLabel.TextTransparency = 0
		countLabel.TextStrokeTransparency = 0.06
		dangerLabel.TextStrokeTransparency = 0.06
	else
		-- Keep a restrained reminder visible until timeout or fall without
		-- replaying the full pulse on duplicate overlap callbacks.
		countScale.Scale = 0.88
		dangerScale.Scale = 0.88
		countLabel.TextTransparency = 0.22
		dangerLabel.TextTransparency = 0.28
		countLabel.TextStrokeTransparency = 0.20
		dangerLabel.TextStrokeTransparency = 0.24
	end
end

local function resolveCharacterWarningJoints(activeCharacter: Model)
	restoreCharacterWarningPose()
	warningRootJoint = nil
	warningWaist = nil
	warningRootBaseC0 = nil
	warningWaistBaseC0 = nil

	for _, descendant in activeCharacter:GetDescendants() do
		if descendant:IsA("Motor6D") then
			if not warningWaist
				and descendant.Name == "Waist"
				and descendant.Part0
				and descendant.Part0.Name == "LowerTorso"
				and descendant.Part1
				and descendant.Part1.Name == "UpperTorso"
			then
				warningWaist = descendant
				warningWaistBaseC0 = descendant.C0
			elseif not warningRootJoint
				and (descendant.Name == "Root" or descendant.Name == "RootJoint")
				and descendant.Part0
				and descendant.Part0.Name == "HumanoidRootPart"
			then
				warningRootJoint = descendant
				warningRootBaseC0 = descendant.C0
			end
		end
	end
end

local function applyCharacterWarning(risk: number)
	local rollDegrees, yawDegrees = warningAngles(risk)
	local directionSign = turnDirectionSign()
	local chainRollDegrees = SLIP_CHAIN.currentWarningRoll(os.clock())
	local rootOffset = CFrame.Angles(
		0,
		math.rad(yawDegrees * 0.15 * directionSign),
		math.rad(
			rollDegrees * 0.18 * directionSign
				+ chainRollDegrees * 0.18
		)
	)
	local waistOffset = CFrame.Angles(
		0,
		math.rad(yawDegrees * 0.85 * directionSign),
		math.rad(
			rollDegrees * 0.82 * directionSign
				+ chainRollDegrees * 0.82
		)
	)

	if warningRootJoint and warningRootJoint.Parent and warningRootBaseC0 then
		warningRootJoint.C0 = warningRootBaseC0 * rootOffset
	end
	if warningWaist and warningWaist.Parent and warningWaistBaseC0 then
		warningWaist.C0 = warningWaistBaseC0 * waistOffset
	end
end

SHARP_TURN.updateGui = function(displayRisk: number)
	local label = warningLabel
	local scale = warningScale
	if not label or not label.Parent or not scale or not scale.Parent then
		return
	end

	local edgeFlash = SHARP_TURN.edgeFlash
	if edgeFlash and edgeFlash.Parent then
		local isRight = SHARP_TURN.activeSide == "Right"
		edgeFlash.Name = if isRight then "RightOversteerFlash" else "LeftOversteerFlash"
		edgeFlash.AnchorPoint = Vector2.new(if isRight then 1 else 0, 0.5)
		edgeFlash.Position = UDim2.fromScale(if isRight then 1 else 0, 0.5)
		local gradient = edgeFlash:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Rotation = if isRight then 180 else 0
		end
	end
	if SHARP_TURN.committed then
		local age = math.max(os.clock() - SHARP_TURN.commitTime, 0)
		local iconAlpha = if age <= 0.22
			then 1
			else 1 - math.clamp((age - 0.22) / 0.10, 0, 1)
		label.Visible = age <= SHARP_TURN.iconDuration
		label.Text = if SHARP_TURN.activeSide == "Right"
			then "↷\nTOO SHARP!"
			else "↶\nTOO SHARP!"
		label.TextColor3 = Color3.fromRGB(255, 72, 38)
		label.TextTransparency = 1 - iconAlpha
		label.TextStrokeTransparency = 1 - iconAlpha * 0.96
		if age <= 0.06 then
			scale.Scale = 0.85 + 0.27 * smoothStep(age / 0.06)
		elseif age <= 0.14 then
			scale.Scale = 1.12 - 0.12 * smoothStep((age - 0.06) / 0.08)
		else
			scale.Scale = 1
		end

		if edgeFlash and edgeFlash.Parent then
			local flashAlpha = if age <= 0.04
				then smoothStep(age / 0.04)
				else 1 - smoothStep(math.clamp(
					(age - 0.04) / (SHARP_TURN.edgeFlashDuration - 0.04),
					0,
					1
				))
			edgeFlash.Visible = age <= SHARP_TURN.edgeFlashDuration
			edgeFlash.BackgroundTransparency = 1 - 0.42 * flashAlpha
		end
		return
	end

	if edgeFlash and edgeFlash.Parent then
		edgeFlash.Visible = false
		edgeFlash.BackgroundTransparency = 1
	end
	local moderateStrength = MODERATE_TURN.feedbackStrength(os.clock())
	if MODERATE_TURN.feedbackTier ~= 2 or moderateStrength <= 0.03 then
		hideTurnWarningGui()
		return
	end
	local opacity = 0.88 * smoothStep(math.clamp(
		math.min(displayRisk, moderateStrength),
		0,
		1
	))
	label.Visible = true
	label.Text = if SHARP_TURN.activeSide == "Right"
		then "↷\nSHARP!"
		else "↶\nSHARP!"
	label.TextColor3 = Color3.fromRGB(255, 214, 48)
	label.TextTransparency = 1 - opacity
	label.TextStrokeTransparency = 1 - opacity * 0.92
	scale.Scale = 1
end

SHARP_TURN.trimSamples = function(samples, now: number)
	while samples[1] and now - samples[1].timestamp > SHARP_TURN.window do
		table.remove(samples, 1)
	end
end

SHARP_TURN.signedYawDegrees = function(fromDirection: Vector3, toDirection: Vector3): number
	local dot = math.clamp(fromDirection:Dot(toDirection), -1, 1)
	-- Roblox's horizontal cross-Y is positive for a geometric left turn from
	-- forward (-Z) toward left (-X). Negate it so the public convention is:
	-- left < 0, right > 0.
	return -math.deg(math.atan2(fromDirection:Cross(toDirection).Y, dot))
end

SHARP_TURN.sampleDirection = function(
	samples,
	now: number,
	direction: Vector3
): (number, number, FallSide?)
	SHARP_TURN.trimSamples(samples, now)
	table.insert(samples, { timestamp = now, direction = direction })
	local strongestAngle = 0
	local strongestWindow = 0
	local strongestSide: FallSide? = nil
	for _, sample in samples do
		local signedYaw = SHARP_TURN.signedYawDegrees(sample.direction, direction)
		local angle = math.abs(signedYaw)
		if angle > strongestAngle then
			strongestAngle = angle
			strongestWindow = now - sample.timestamp
			strongestSide = if signedYaw < 0 then "Left" else "Right"
		end
	end
	return strongestAngle, strongestWindow, strongestSide
end

SHARP_TURN.createFootTrails = function(expectedToken: number)
	local activeCharacter = character
	if not activeCharacter or expectedToken ~= sequenceToken then
		return
	end
	local createdObjects = {} :: { Instance }
	for _, footName in { "LeftFoot", "RightFoot" } do
		local foot = activeCharacter:FindFirstChild(footName, true)
		if foot and foot:IsA("BasePart") then
			local attachment0 = Instance.new("Attachment")
			attachment0.Name = "SharpTurnSkid0"
			attachment0.Position = Vector3.new(-foot.Size.X * 0.32, -foot.Size.Y * 0.45, 0)
			attachment0.Parent = foot
			local attachment1 = Instance.new("Attachment")
			attachment1.Name = "SharpTurnSkid1"
			attachment1.Position = Vector3.new(foot.Size.X * 0.32, -foot.Size.Y * 0.45, 0)
			attachment1.Parent = foot
			local trail = Instance.new("Trail")
			trail.Name = "SharpTurnSkidTrail"
			trail.Attachment0 = attachment0
			trail.Attachment1 = attachment1
			trail.Color = ColorSequence.new(
				Color3.fromRGB(255, 226, 116),
				Color3.fromRGB(255, 92, 42)
			)
			trail.Transparency = NumberSequence.new(0.16, 1)
			trail.Lifetime = 0.16
			trail.MinLength = 0.02
			trail.WidthScale = NumberSequence.new(0.18, 0)
			trail.FaceCamera = true
			trail.Parent = foot
			table.insert(SHARP_TURN.temporaryTrailObjects, trail)
			table.insert(SHARP_TURN.temporaryTrailObjects, attachment0)
			table.insert(SHARP_TURN.temporaryTrailObjects, attachment1)
			table.insert(createdObjects, trail)
			table.insert(createdObjects, attachment0)
			table.insert(createdObjects, attachment1)
		end
	end
	task.delay(SHARP_TURN.trailDuration, function()
		for _, temporaryObject in createdObjects do
			if temporaryObject:IsA("Trail") then
				temporaryObject.Enabled = false
			end
		end
		task.delay(0.20, function()
			for _, temporaryObject in createdObjects do
				if temporaryObject.Parent then
					temporaryObject:Destroy()
				end
			end
		end)
	end)
end

local function turnInputWindowIsActive(): boolean
	local activeHumanoid = humanoid
	return script.Enabled
		and SHARP_TURN.token == sequenceToken
		and slipStartedWhileSprinting
		and not fallDecisionMade
		and not SLIP_CHAIN.fallCommitted
		and (visualState == "SlipStart" or visualState == "SlipStruggle")
		and activeHumanoid ~= nil
		and activeHumanoid.Parent ~= nil
		and activeHumanoid.Health > 0
end

SHARP_TURN.updateDetector = function(now: number, defaultCameraForward: Vector3)
	if committedTurnSide ~= nil
		and SHARP_TURN.token == sequenceToken
		and (visualState == "SlipStart" or visualState == "SlipStruggle")
		and not SHARP_TURN.fading
	then
		SHARP_TURN.activeSide = committedTurnSide :: FallSide
		turnRisk = 1
		return
	end

	if turnInputWindowIsActive() and not SHARP_TURN.fading then
		local activeHumanoid = humanoid :: Humanoid
		local cameraAngle, cameraWindow, cameraSide = SHARP_TURN.sampleDirection(
			SHARP_TURN.cameraSamples,
			now,
			defaultCameraForward
		)
		local movementAngle = 0
		local movementWindow = 0
		local movementSide: FallSide? = nil
		local moveDirection = horizontal(activeHumanoid.MoveDirection)
		if moveDirection.Magnitude >= SHARP_TURN.minimumDirectionMagnitude then
			movementAngle, movementWindow, movementSide = SHARP_TURN.sampleDirection(
				SHARP_TURN.movementSamples,
				now,
				moveDirection.Unit
			)
		else
			SHARP_TURN.trimSamples(SHARP_TURN.movementSamples, now)
		end

		local sharpTurnAngle: number
		local sampleWindow: number
		local source: string
		local detectedSide: FallSide?
		if movementAngle > cameraAngle then
			sharpTurnAngle = movementAngle
			sampleWindow = movementWindow
			source = "movement"
			detectedSide = movementSide
		else
			sharpTurnAngle = cameraAngle
			sampleWindow = cameraWindow
			source = "camera"
			detectedSide = cameraSide
		end
		SHARP_TURN.lastAngle = sharpTurnAngle
		SHARP_TURN.lastSource = source
		if detectedSide then
			SHARP_TURN.activeSide = detectedSide
		end

		if committedTurnSide == nil
			and SLIP_CHAIN.fallCause == nil
			and detectedSide ~= nil
			and sharpTurnAngle >= MODERATE_TURN.SHARP_TURN_FALL_ANGLE
			and sampleWindow <= SHARP_TURN.window
		then
			MODERATE_TURN.cancel("sharpFall")
			SLIP_CHAIN.currentContactEvent = nil
			committedTurnSide = detectedSide
			SLIP_CHAIN.fallCause = "sharpTurn"
			SLIP_CHAIN.fallDirection = if detectedSide == "Right" then "right" else "left"
			SHARP_TURN.activeSide = detectedSide
			SHARP_TURN.committed = true
			SHARP_TURN.commitTime = now
			turnRisk = 1
			SLIP_CHAIN.hideWarningFeedback()
			print(string.format(
				"[SharpTurn] committed side=%s angle=%.1f window=%.3f source=%s",
				detectedSide,
				sharpTurnAngle,
				sampleWindow,
				source
			))
			SHARP_TURN.createFootTrails(sequenceToken)
		else
			MODERATE_TURN.evaluate(now, sharpTurnAngle, detectedSide)
			turnRisk = MODERATE_TURN.feedbackStrength(now)
		end
	else
		turnRisk = 0
		table.clear(SHARP_TURN.cameraSamples)
		table.clear(SHARP_TURN.movementSamples)
	end
end

local function updateTurnWarningRender(deltaTime: number)
	if CINEMATIC_CAMERA.active then
		-- The turn warning has already committed to a lateral fall. Do not let its
		-- post-camera offset or FOV bookkeeping compete with the cinematic owner.
		restoreCharacterWarningPose()
		hideTurnWarningGui()
		return
	end
	local activeCamera = Workspace.CurrentCamera
	if not activeCamera then
		return
	end

	local defaultCameraCFrame = activeCamera.CFrame
	local defaultCameraForward = horizontal(defaultCameraCFrame.LookVector)
	if defaultCameraForward.Magnitude < 0.05 then
		defaultCameraForward = Vector3.zAxis
	else
		defaultCameraForward = defaultCameraForward.Unit
	end

	local now = os.clock()
	SHARP_TURN.updateDetector(now, defaultCameraForward)
	SLIP_CHAIN.updateWarningFeedback(now)
	local responseAlpha = 1 - math.exp(-WARNING_FEEDBACK_RESPONSE * deltaTime)
	displayedTurnRisk += (turnRisk - displayedTurnRisk) * responseAlpha
	if displayedTurnRisk < 0.001 and turnRisk <= 0 then
		displayedTurnRisk = 0
		if SHARP_TURN.fading then
			resetTurnFeedback(false)
		end
	end

	-- This binding runs after the Animator/default camera update. Rebuilding each
	-- C0 from its captured base keeps the warning additive and non-accumulating.
	applyCharacterWarning(displayedTurnRisk)
	SHARP_TURN.updateGui(displayedTurnRisk)

	local yawDegrees, rollDegrees, fovOffset = cameraWarningValues(
		displayedTurnRisk
	)
	local directionSign = turnDirectionSign()
	local cameraOffset = CFrame.Angles(
		0,
		math.rad(yawDegrees * directionSign),
		math.rad(rollDegrees * directionSign)
	)
	lastCameraOffset = cameraOffset
	activeCamera.CFrame = defaultCameraCFrame * cameraOffset

	local observedFov = activeCamera.FieldOfView
	local baseFov = if lastCameraBaseFov
		and math.abs(observedFov - (lastCameraBaseFov + lastCameraFovOffset)) < 0.05
		then lastCameraBaseFov
		else observedFov
	lastCameraBaseFov = baseFov
	lastCameraFovOffset = fovOffset
	activeCamera.FieldOfView = baseFov + fovOffset
end

local function bindTurnWarningRender()
	if turnWarningRenderBound then
		return
	end
	RunService:BindToRenderStep(
		TURN_WARNING_RENDER_BINDING,
		Enum.RenderPriority.Camera.Value + 1,
		updateTurnWarningRender
	)
	turnWarningRenderBound = true
end

local function unbindTurnWarningRender()
	if not turnWarningRenderBound then
		return
	end
	RunService:UnbindFromRenderStep(TURN_WARNING_RENDER_BINDING)
	turnWarningRenderBound = false
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

BASKET_RECOVERY.sinkInput = function(
	_actionName: string,
	_inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

BASKET_RECOVERY.setInputLocked = function(locked: boolean)
	if BASKET_RECOVERY.inputLocked == locked then
		return
	end
	BASKET_RECOVERY.inputLocked = locked
	if locked then
		BASKET_RECOVERY.contextActionService:BindActionAtPriority(
			BASKET_RECOVERY.inputAction,
			BASKET_RECOVERY.sinkInput,
			false,
			BASKET_RECOVERY.inputPriority,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump,
			Enum.KeyCode.LeftShift,
			Enum.KeyCode.RightShift
		)
	else
		BASKET_RECOVERY.contextActionService:UnbindAction(BASKET_RECOVERY.inputAction)
	end
end

BASKET_RECOVERY.disconnectMarkers = function()
	for _, connection in BASKET_RECOVERY.markerConnections do
		connection:Disconnect()
	end
	table.clear(BASKET_RECOVERY.markerConnections)
end

function CHAIN_BACK.disconnectMarkers()
	for _, connection in CHAIN_BACK.markerConnections do
		connection:Disconnect()
	end
	table.clear(CHAIN_BACK.markerConnections)
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
	CINEMATIC_CAMERA.finish()

	stopTrack(slipStartTrack, 0.03)
	stopTrack(slipStruggleTrack, 0.03)
	stopTrack(slipRecoverTrack, 0.03)
	stopTrack(fallBackLeftTrack, 0.03)
	stopTrack(getUpLeftTrack, 0.03)
	stopTrack(fallBackRightTrack, 0.03)
	stopTrack(getUpRightTrack, 0.03)
	stopTrack(CHAIN_BACK.fallTrack, 0.03)
	stopTrack(CHAIN_BACK.getUpTrack, 0.03)
	stopTrack(BASKET_RECOVERY.track, 0.03)
	CHAIN_BACK.disconnectMarkers()
	BASKET_RECOVERY.disconnectMarkers()
	BASKET_RECOVERY.setInputLocked(false)
	BASKET_RECOVERY.moveTarget = nil
	BASKET_RECOVERY.moveToActive = false
	BASKET_RECOVERY.facingActive = false
	BASKET_RECOVERY.pickupCompleteHandled = false
	resetSlipMovementAttributes()
	destroyTrack(slipStartTrack)
	destroyTrack(slipStruggleTrack)
	destroyTrack(slipRecoverTrack)
	destroyTrack(fallBackLeftTrack)
	destroyTrack(getUpLeftTrack)
	destroyTrack(fallBackRightTrack)
	destroyTrack(getUpRightTrack)
	destroyTrack(CHAIN_BACK.fallTrack)
	destroyTrack(CHAIN_BACK.getUpTrack)
	destroyTrack(BASKET_RECOVERY.track)
	destroyAnimation(slipStartAnimation)
	destroyAnimation(slipStruggleAnimation)
	destroyAnimation(slipRecoverAnimation)
	destroyAnimation(fallBackLeftAnimation)
	destroyAnimation(getUpLeftAnimation)
	destroyAnimation(fallBackRightAnimation)
	destroyAnimation(getUpRightAnimation)
	destroyAnimation(CHAIN_BACK.fallAnimation)
	destroyAnimation(CHAIN_BACK.getUpAnimation)
	destroyAnimation(BASKET_RECOVERY.animation)

	slipStartAnimation = nil
	slipStruggleAnimation = nil
	slipRecoverAnimation = nil
	fallBackLeftAnimation = nil
	getUpLeftAnimation = nil
	fallBackRightAnimation = nil
	getUpRightAnimation = nil
	CHAIN_BACK.fallAnimation = nil
	CHAIN_BACK.getUpAnimation = nil
	BASKET_RECOVERY.animation = nil
	slipStartTrack = nil
	slipStruggleTrack = nil
	slipRecoverTrack = nil
	fallBackLeftTrack = nil
	getUpLeftTrack = nil
	fallBackRightTrack = nil
	getUpRightTrack = nil
	CHAIN_BACK.fallTrack = nil
	CHAIN_BACK.getUpTrack = nil
	BASKET_RECOVERY.track = nil
	slipStartLength = nil
	slipStruggleLength = nil
	slipRecoverLength = nil
	fallBackLeftLength = nil
	getUpLeftLength = nil
	fallBackRightLength = nil
	getUpRightLength = nil
	CHAIN_BACK.fallLength = nil
	CHAIN_BACK.getUpLength = nil
	BASKET_RECOVERY.length = nil
	slipStartedWhileSprinting = false
	fallDecisionMade = false
	activeFallSide = nil
	SLIP_CHAIN.fallCause = nil
	SLIP_CHAIN.fallDirection = nil
	resetTurnFeedback(true)
	BASKET_RECOVERY.droppedBasket = nil
end

local function resolveTrackLength(
	track: AnimationTrack,
	clipName: string,
	setupToken: number,
	fallbackLength: number
): number?
	if sequenceToken ~= setupToken or not script.Enabled then
		return nil
	end
	if track.Length <= 0 then
		-- Animation metadata can arrive after PlayerScripts starts. A missing
		-- length must never disable yolk detection or the existing slip tracks.
		warn(string.format(
			"[EggSlipAnim] %s length pending; using %.2fs fallback",
			clipName,
			fallbackLength
		))
		return fallbackLength
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
		and activeCharacter:GetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE) ~= true
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

	-- Remove the controlled slip velocity before normal locomotion resumes.
	endSlip(os.clock(), "finish")
	activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	-- Once controlled slipping has ended and normal locomotion owns the
	-- character again, the completed sequence must not contribute to a future
	-- slip. Active-slip contacts still chain normally before this point.
	SLIP_CHAIN.reset("recovery")

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
		fallDecisionMade = false
		resetTurnFeedback(true)
	end)
	return true
end

local function isFallLockedState(): boolean
	return visualState == "FallBackLeft"
		or visualState == "FallBackRight"
		or visualState == "FallStraightBack"
		or visualState == "FallenHold"
		or visualState == "GetUpLeft"
		or visualState == "GetUpRight"
		or visualState == "GetUpBack"
		or visualState == "StandingNoBasket"
		or visualState == "SeekDroppedBasket"
		or visualState == "BasketPickup"
		or visualState == "BasketHoldTransition"
end

BASKET_RECOVERY.isStationaryLocked = function(): boolean
	return visualState ~= "SeekDroppedBasket" and isFallLockedState()
end

local function stopBasketHoldForFall(animator: Animator)
	for _, track in animator:GetPlayingAnimationTracks() do
		local sourceAnimation = track.Animation
		if track.Name == "BasketHold"
			or (sourceAnimation and sourceAnimation.Name == "BasketHold")
		then
			track:Stop(0.03)
		end
	end
end

local function invokeBasketFallAction(action: string, ...: any): any
	local request = ReplicatedStorage:FindFirstChild(FALL_BASKET_RELEASE_REQUEST_NAME)
	if not request or not request:IsA("RemoteFunction") then
		return nil
	end

	local arguments = { ... }
	local succeeded, result = pcall(function()
		return request:InvokeServer(action, table.unpack(arguments))
	end)
	return if succeeded then result else nil
end

local function requestBasketRelease(direction: FallSide | "Back"): Model?
	local result = invokeBasketFallAction("Release", direction)
	return if typeof(result) == "Instance" and result:IsA("Model")
		then result
		else nil
end

SHARP_TURN.tossReleasedBasket = function(
	basket: Model,
	expectedToken: number,
	side: FallSide
)
	task.defer(function()
		local root = humanoidRootPart
		if expectedToken ~= sequenceToken
			or (visualState ~= "FallBackLeft" and visualState ~= "FallBackRight")
			or not root
			or not root.Parent
			or not basket.Parent
		then
			return
		end
		local basketRoot = basket.PrimaryPart
			or basket:FindFirstChildWhichIsA("BasePart", true)
		if not basketRoot then
			return
		end
		local sideDirection = horizontal(root.CFrame.RightVector)
		sideDirection = if sideDirection.Magnitude > 0.05
			then sideDirection.Unit
			else Vector3.xAxis
		if side == "Left" then
			sideDirection = -sideDirection
		end
		local forward = horizontal(capturedSlideDirection)
		forward = if forward.Magnitude > 0.05
			then forward.Unit
			else horizontal(root.CFrame.LookVector).Unit
		local currentVelocity = basketRoot.AssemblyLinearVelocity
		local launchHorizontal = horizontal(currentVelocity)
			+ sideDirection * 11.5
			+ forward * 3.0
		if launchHorizontal.Magnitude > 17.5 then
			launchHorizontal = launchHorizontal.Unit * 17.5
		end
		basketRoot.AssemblyLinearVelocity = launchHorizontal
			+ Vector3.yAxis * math.max(currentVelocity.Y, 4.0)
		local spin = Vector3.new(1.2, -3.4, 1.8)
		if side == "Right" then
			spin = Vector3.new(spin.X, -spin.Y, -spin.Z)
		end
		basketRoot.AssemblyAngularVelocity += spin
	end)
end

local function requestBasketRestore(): boolean
	return invokeBasketFallAction("Restore") == true
end

BASKET_RECOVERY.requestCurrentBasket = function(): Model?
	local result = invokeBasketFallAction("GetDropped")
	return if typeof(result) == "Instance" and result:IsA("Model")
		then result
		else nil
end

BASKET_RECOVERY.requestStage = function(action: string, basket: Model): boolean
	return invokeBasketFallAction(action, basket) == true
end

BASKET_RECOVERY.requestDebugSnapshot = function(): { [string]: any }?
	local result = invokeBasketFallAction("DebugSnapshot")
	return if typeof(result) == "table" then result else nil
end

BASKET_RECOVERY.requestEmergencyReposition = function(
	basket: Model,
	reason: string
): Model?
	local result = invokeBasketFallAction("EmergencyReposition", basket, reason)
	return if typeof(result) == "Instance" and result:IsA("Model")
		then result
		else nil
end

local function fallSideForThisSlip(): FallSide?
	if SLIP_CHAIN.fallCause == "sharpTurn" and SLIP_CHAIN.fallDirection == "left" then
		return "Left"
	elseif SLIP_CHAIN.fallCause == "sharpTurn" and SLIP_CHAIN.fallDirection == "right" then
		return "Right"
	end
	return nil
end

function SLIP_CHAIN.warningCount(): number
	return if SLIP_CHAIN.mode == "sprint"
		then SPRINT_CHAIN_WARNING_COUNT
		else NORMAL_CHAIN_WARNING_COUNT
end

function SLIP_CHAIN.fallCount(): number
	return if SLIP_CHAIN.mode == "sprint"
		then SPRINT_CHAIN_FALL_COUNT
		else NORMAL_CHAIN_FALL_COUNT
end

function SLIP_CHAIN.captureLateralInput(now: number)
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	if not activeHumanoid or not root or not IsSlipping then
		return
	end
	local moveDirection = horizontal(activeHumanoid.MoveDirection)
	local localRight = horizontal(root.CFrame.RightVector)
	if moveDirection.Magnitude < 0.20 or localRight.Magnitude < 0.05 then
		return
	end
	local signedLateral = moveDirection.Unit:Dot(localRight.Unit)
	if math.abs(signedLateral) < 0.20 then
		return
	end
	SLIP_CHAIN.recentLateralSide = if signedLateral < 0 then "Left" else "Right"
	SLIP_CHAIN.recentLateralTime = now
end

function SLIP_CHAIN.commitFall(now: number): boolean
	if SLIP_CHAIN.fallCommitted
		or SLIP_CHAIN.fallCause ~= nil
		or fallDecisionMade
		or SHARP_TURN.committed
		or committedTurnSide ~= nil
	then
		return false
	end
	local mode = SLIP_CHAIN.mode
	if not mode then
		return false
	end
	SLIP_CHAIN.fallCommitted = true
	SLIP_CHAIN.currentContactEvent = nil
	SLIP_CHAIN.fallCommitTime = now
	SLIP_CHAIN.fallWindowWait = 0
	SLIP_CHAIN.generation += 1
	SLIP_CHAIN.resetDeadline = nil
	SLIP_CHAIN.fallCause = "chain"
	SLIP_CHAIN.fallDirection = "back"
	MODERATE_TURN.cancel("chainFall")
	resetTurnFeedback(true)
	SLIP_CHAIN.showWarningFeedback("threshold", now)
	print(string.format(
		"[ChainBackFall] committed mode=%s count=%d",
		mode,
		SLIP_CHAIN.count
	))
	return true
end

function SLIP_CHAIN.handleCountChanged(now: number): boolean
	local mode = SLIP_CHAIN.mode
	if not mode then
		return false
	end
	local warningCount = SLIP_CHAIN.warningCount()
	local fallCount = SLIP_CHAIN.fallCount()
	if SLIP_CHAIN.count >= fallCount then
		if SHARP_TURN.committed
			or committedTurnSide ~= nil
			or (fallDecisionMade and visualState ~= "SlipRecover")
		then
			SLIP_CHAIN.hideWarningFeedback()
			return false
		end
		return SLIP_CHAIN.commitFall(now)
	end
	if SLIP_CHAIN.count == warningCount and not SLIP_CHAIN.warningShown then
		SLIP_CHAIN.warningShown = true
		SLIP_CHAIN.showWarningFeedback("warning", now)
		print(string.format(
			"[ChainBackFall] warning mode=%s count=%d",
			mode,
			SLIP_CHAIN.count
		))
	end
	return false
end

function SLIP_CHAIN.scheduleRecovery(token: number)
	local struggleTrack = slipStruggleTrack
	local recoverTrack = slipRecoverTrack
	local recoverLength = slipRecoverLength
	if not struggleTrack or not recoverTrack or not recoverLength then
		return
	end

	local attemptRecovery: (() -> ())?
	attemptRecovery = function()
		if not visualSequenceIsCurrent(token, "SlipStruggle") then
			return
		end
		local remaining = SLIP_CHAIN.recoverNotBefore - os.clock()
		if remaining > 0 then
			task.delay(remaining, attemptRecovery :: () -> ())
			return
		end
		-- A late sharp turn owns the next safe transition exactly as before.
		if SLIP_CHAIN.fallCause ~= nil and not fallDecisionMade then
			return
		end
		if not fallDecisionMade then
			fallDecisionMade = true
			MODERATE_TURN.cancel("recover")
			beginTurnFeedbackFadeOut()
			print("[SharpTurn] result=SlipRecover")
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
	end
	task.defer(attemptRecovery :: () -> ())
end

function SLIP_CHAIN.monitorStruggle(token: number)
	local struggleTrack = slipStruggleTrack
	local struggleLength = slipStruggleLength
	if not struggleTrack or not struggleLength then
		return
	end

	task.spawn(function()
		local decisionTime = math.max(
			MIN_VISIBLE_STRUGGLE_TIME,
			SLIP_STRUGGLE_LATE_LEFT_FALL_TIME
		)
		local compatiblePhase = math.clamp(
			math.max(decisionTime - 0.08, struggleLength * 0.55),
			0,
			math.max(struggleLength - SLIP_STRUGGLE_TRANSITION_LEAD - 0.04, 0)
		)
		while visualSequenceIsCurrent(token, "SlipStruggle") and not fallDecisionMade do
			local fallSide = fallSideForThisSlip()
			local now = os.clock()
			local chainOwnsFall = SLIP_CHAIN.fallCommitted
				and SLIP_CHAIN.fallCause == "chain"
				and SLIP_CHAIN.fallDirection == "back"
			local chainFallReady = false
			if chainOwnsFall then
				local visibleAge = math.max(now - SLIP_CHAIN.struggleVisibleSince, 0)
				local commitAge = math.max(now - SLIP_CHAIN.fallCommitTime, 0)
				chainFallReady = visibleAge >= MIN_VISIBLE_STRUGGLE_TIME
					and visibleAge >= CHAIN_FALL_MIN_STRUGGLE_TIME
					and (
						commitAge >= SLIP_CHAIN.minimumChainFallCommitTime
						or commitAge >= SLIP_CHAIN.maximumChainFallWait
					)
			end

			local sharpTurnReady = not chainOwnsFall
				and struggleTrack.TimePosition >= decisionTime
				and fallSide ~= nil
				and now - SHARP_TURN.commitTime
					>= SHARP_TURN.minimumCommittedFeedbackTime
			if chainFallReady or sharpTurnReady then
				fallDecisionMade = true
				if chainOwnsFall then
					print("[ChainBackFall] transition=FallStraightBack")
					CHAIN_BACK.beginFall(token)
				else
					beginTurnFeedbackFadeOut()
					print("[SharpTurn] result=FallBack" .. (fallSide :: FallSide))
					resetTurnFeedback(false)
					beginFallBack(fallSide :: FallSide, token)
				end
				return
			end

			if struggleTrack.TimePosition
				>= struggleLength - SLIP_STRUGGLE_TRANSITION_LEAD
			then
				if os.clock() < SLIP_CHAIN.recoverNotBefore or SLIP_CHAIN.fallCause ~= nil then
					-- Keep one track alive at a compatible late struggle phase. This
					-- avoids a neutral frame without stacking or restarting SlipStart.
					if not struggleTrack.IsPlaying then
						struggleTrack:Play(0.04, 1, SLIP_STRUGGLE_PLAYBACK_SPEED)
					end
					struggleTrack.TimePosition = compatiblePhase
				elseif SLIP_CHAIN.fallCause == nil then
					return
				end
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

function SLIP_CHAIN.startStruggle(token: number, resumedFromRecovery: boolean)
	local startTrack = slipStartTrack
	local struggleTrack = slipStruggleTrack
	local recoverTrack = slipRecoverTrack
	local struggleLength = slipStruggleLength
	if not startTrack or not struggleTrack or not recoverTrack or not struggleLength then
		return
	end
	local expectedState: VisualState = if resumedFromRecovery
		then "SlipRecover"
		else "SlipStart"
	if not visualSequenceIsCurrent(token, expectedState) then
		return
	end

	visualState = "SlipStruggle"
	SLIP_CHAIN.struggleVisibleSince = os.clock()
	struggleTrack:Play(
		if resumedFromRecovery then SLIP_STRUGGLE_CROSSFADE else SLIP_START_CROSSFADE,
		1,
		SLIP_STRUGGLE_PLAYBACK_SPEED
	)
	if resumedFromRecovery then
		local resumePhase = math.clamp(
			struggleLength * 0.55,
			0,
			math.max(struggleLength - SLIP_STRUGGLE_TRANSITION_LEAD - 0.04, 0)
		)
		struggleTrack.TimePosition = resumePhase
		recoverTrack:Stop(SLIP_STRUGGLE_CROSSFADE)
	else
		startTrack:Stop(SLIP_START_CROSSFADE)
		SLIP_CHAIN.recoverNotBefore = os.clock()
			+ math.max(struggleLength - SLIP_STRUGGLE_TRANSITION_LEAD, 0)
			+ SLIP_CHAIN.totalExtension
	end

	SLIP_CHAIN.monitorStruggle(token)
	SLIP_CHAIN.scheduleRecovery(token)
end

function SLIP_CHAIN.interruptRecovery()
	if not IsSlipping or visualState ~= "SlipRecover" then
		return
	end
	-- A committed chain fall keeps ownership on the current sequence token.
	-- Changing state is sufficient to invalidate the older recovery callback.
	if not SLIP_CHAIN.fallCommitted then
		sequenceToken += 1
	end
	local token = sequenceToken
	SHARP_TURN.token = token
	fallDecisionMade = false
	SLIP_CHAIN.startStruggle(token, true)
	print(string.format(
		"[SlipChain] recovery interrupted count=%d",
		SLIP_CHAIN.count
	))
end

local function beginSlipVisual()
	-- A fresh yolk contact may happen while the previous post-slip multiplier
	-- is still restoring. Restarting the visual sequence increments the shared
	-- token below, which cancels that older restoration without stacking loops.
	if character and character:GetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE) == true then
		return
	end
	if visualState ~= "Idle" and visualState ~= "PostSlipSlow" then
		return
	end
	if not animationTracksReady then
		warn("[EggSlipAnim] Cannot start because animation tracks are not ready")
		return
	end

	local startTrack = slipStartTrack
	local startLength = slipStartLength
	if not startTrack
		or not startLength
		or not slipStruggleTrack
		or not slipRecoverTrack
		or not slipStruggleLength
		or not slipRecoverLength
	then
		warn("[EggSlipAnim] Cannot start because an animation track length is unavailable")
		return
	end

	sequenceToken += 1
	local token = sequenceToken
	SHARP_TURN.token = token
	stopTrack(startTrack, 0.02)
	stopTrack(slipStruggleTrack, 0.02)
	stopTrack(slipRecoverTrack, 0.02)

	visualState = "SlipStart"
	startTrack:Play(0.03, 1, 1)

	task.delay(math.max(startLength - SLIP_START_TRANSITION_LEAD, 0), function()
		if not visualSequenceIsCurrent(token, "SlipStart") then
			return
		end
		SLIP_CHAIN.startStruggle(token, false)
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
	local fallAnimation = Instance.new("Animation")
	fallAnimation.Name = "FallBackLeftAnimation"
	fallAnimation.AnimationId = FALL_BACK_LEFT_ANIMATION_ID
	local getUpAnimation = Instance.new("Animation")
	getUpAnimation.Name = "GetUpLeftAnimation"
	getUpAnimation.AnimationId = GET_UP_LEFT_ANIMATION_ID
	local fallRightAnimation = Instance.new("Animation")
	fallRightAnimation.Name = "FallBackRightAnimation"
	fallRightAnimation.AnimationId = FALL_BACK_RIGHT_ANIMATION_ID
	local getUpRightClip = Instance.new("Animation")
	getUpRightClip.Name = "GetUpRightAnimation"
	getUpRightClip.AnimationId = GET_UP_RIGHT_ANIMATION_ID
	local fallStraightBackClip = Instance.new("Animation")
	fallStraightBackClip.Name = "FallStraightBackAnimation"
	fallStraightBackClip.AnimationId = FALL_STRAIGHT_BACK_ANIMATION_ID
	local getUpBackClip = Instance.new("Animation")
	getUpBackClip.Name = "GetUpBackAnimation"
	getUpBackClip.AnimationId = GET_UP_BACK_ANIMATION_ID
	local pickupAnimation = Instance.new("Animation")
	pickupAnimation.Name = "BasketPickupAnimation"
	pickupAnimation.AnimationId = BASKET_RECOVERY.animationId

	slipStartAnimation = startAnimation
	slipStruggleAnimation = struggleAnimation
	slipRecoverAnimation = recoverAnimation
	fallBackLeftAnimation = fallAnimation
	getUpLeftAnimation = getUpAnimation
	fallBackRightAnimation = fallRightAnimation
	getUpRightAnimation = getUpRightClip
	CHAIN_BACK.fallAnimation = fallStraightBackClip
	CHAIN_BACK.getUpAnimation = getUpBackClip
	BASKET_RECOVERY.animation = pickupAnimation

	local startTrack = animator:LoadAnimation(startAnimation)
	local struggleTrack = animator:LoadAnimation(struggleAnimation)
	local recoverTrack = animator:LoadAnimation(recoverAnimation)
	local fallTrack = animator:LoadAnimation(fallAnimation)
	local getUpTrack = animator:LoadAnimation(getUpAnimation)
	local fallRightTrack = animator:LoadAnimation(fallRightAnimation)
	local getUpRightClipTrack = animator:LoadAnimation(getUpRightClip)
	local fallStraightBackClipTrack = animator:LoadAnimation(fallStraightBackClip)
	local getUpBackClipTrack = animator:LoadAnimation(getUpBackClip)
	local pickupTrack = animator:LoadAnimation(pickupAnimation)
	startTrack.Priority = Enum.AnimationPriority.Action
	struggleTrack.Priority = Enum.AnimationPriority.Action
	recoverTrack.Priority = Enum.AnimationPriority.Action
	fallTrack.Priority = Enum.AnimationPriority.Action4
	getUpTrack.Priority = Enum.AnimationPriority.Action4
	fallRightTrack.Priority = Enum.AnimationPriority.Action4
	getUpRightClipTrack.Priority = Enum.AnimationPriority.Action4
	fallStraightBackClipTrack.Priority = Enum.AnimationPriority.Action4
	getUpBackClipTrack.Priority = Enum.AnimationPriority.Action4
	pickupTrack.Priority = Enum.AnimationPriority.Action4
	startTrack.Looped = false
	struggleTrack.Looped = false
	recoverTrack.Looped = false
	fallTrack.Looped = false
	getUpTrack.Looped = false
	fallRightTrack.Looped = false
	getUpRightClipTrack.Looped = false
	fallStraightBackClipTrack.Looped = false
	getUpBackClipTrack.Looped = false
	pickupTrack.Looped = false

	slipStartTrack = startTrack
	slipStruggleTrack = struggleTrack
	slipRecoverTrack = recoverTrack
	fallBackLeftTrack = fallTrack
	getUpLeftTrack = getUpTrack
	fallBackRightTrack = fallRightTrack
	getUpRightTrack = getUpRightClipTrack
	CHAIN_BACK.fallTrack = fallStraightBackClipTrack
	CHAIN_BACK.getUpTrack = getUpBackClipTrack
	BASKET_RECOVERY.track = pickupTrack

	local resolvedStartLength = resolveTrackLength(
		startTrack, "SlipStart", setupToken, BASKET_RECOVERY.defaultLengths.SlipStart
	)
	local resolvedStruggleLength = resolveTrackLength(
		struggleTrack, "SlipStruggle", setupToken, BASKET_RECOVERY.defaultLengths.SlipStruggle
	)
	local resolvedRecoverLength = resolveTrackLength(
		recoverTrack, "SlipRecover", setupToken, BASKET_RECOVERY.defaultLengths.SlipRecover
	)
	local resolvedFallLength = resolveTrackLength(
		fallTrack, "FallBackLeft", setupToken, BASKET_RECOVERY.defaultLengths.FallBackLeft
	)
	local resolvedGetUpLength = resolveTrackLength(
		getUpTrack, "GetUpLeft", setupToken, BASKET_RECOVERY.defaultLengths.GetUpLeft
	)
	local resolvedFallRightLength = resolveTrackLength(
		fallRightTrack,
		"FallBackRight",
		setupToken,
		BASKET_RECOVERY.defaultLengths.FallBackRight
	)
	local resolvedGetUpRightLength = resolveTrackLength(
		getUpRightClipTrack,
		"GetUpRight",
		setupToken,
		BASKET_RECOVERY.defaultLengths.GetUpRight
	)
	local resolvedFallStraightBackLength = resolveTrackLength(
		fallStraightBackClipTrack,
		"FallStraightBack",
		setupToken,
		BASKET_RECOVERY.defaultLengths.FallStraightBack
	)
	local resolvedGetUpBackLength = resolveTrackLength(
		getUpBackClipTrack,
		"GetUpBack",
		setupToken,
		BASKET_RECOVERY.defaultLengths.GetUpBack
	)
	local resolvedPickupLength = resolveTrackLength(
		pickupTrack, "BasketPickup", setupToken, BASKET_RECOVERY.defaultLengths.BasketPickup
	)
	if sequenceToken ~= setupToken
		or not resolvedStartLength
		or not resolvedStruggleLength
		or not resolvedRecoverLength
		or not resolvedFallLength
		or not resolvedGetUpLength
		or not resolvedFallRightLength
		or not resolvedGetUpRightLength
		or not resolvedFallStraightBackLength
		or not resolvedGetUpBackLength
		or not resolvedPickupLength
	then
		return false
	end

	slipStartLength = resolvedStartLength
	slipStruggleLength = resolvedStruggleLength
	slipRecoverLength = resolvedRecoverLength
	fallBackLeftLength = resolvedFallLength
	getUpLeftLength = resolvedGetUpLength
	fallBackRightLength = resolvedFallRightLength
	getUpRightLength = resolvedGetUpRightLength
	CHAIN_BACK.fallLength = resolvedFallStraightBackLength
	CHAIN_BACK.getUpLength = resolvedGetUpBackLength
	BASKET_RECOVERY.length = resolvedPickupLength
	animationTracksReady = true
	script:SetAttribute("FallLeftBranchTimestamp", SLIP_STRUGGLE_LATE_LEFT_FALL_TIME)
	script:SetAttribute("FallLeftBranchCatchLeg", "Left")
	script:SetAttribute("FallBackLeftTrackLength", resolvedFallLength)
	script:SetAttribute("GetUpLeftTrackLength", resolvedGetUpLength)
	script:SetAttribute("FallRightBranchTimestamp", SLIP_STRUGGLE_LATE_RIGHT_FALL_TIME)
	script:SetAttribute("FallRightBranchCatchLeg", "Right")
	script:SetAttribute("FallBackRightTrackLength", resolvedFallRightLength)
	script:SetAttribute("GetUpRightTrackLength", resolvedGetUpRightLength)
	script:SetAttribute("FallStraightBackTrackLength", resolvedFallStraightBackLength)
	script:SetAttribute("GetUpBackTrackLength", resolvedGetUpBackLength)
	script:SetAttribute("BasketPickupTrackLength", resolvedPickupLength)
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

endSlip = function(now: number, reason: string?)
	if not IsSlipping then
		destroySlipMovement()
		restoreHumanoidState()
		return
	end

	local root = humanoidRootPart
	local finalObservedSpeed = if root and root.Parent
		then horizontal(root.AssemblyLinearVelocity).Magnitude
		else lastControlledSlideSpeed
	maxObservedSlipSpeed = math.max(maxObservedSlipSpeed, finalObservedSpeed)
	if reason == nil or reason == "finish" then
		print(string.format(
			"[SlipSpeed] finish entry=%.2f maxObserved=%.2f final=%.2f",
			slipEntrySpeed,
			maxObservedSlipSpeed,
			finalObservedSpeed
		))
	else
		print(string.format("[SlipSpeed] cancelled reason=%s", reason))
	end
	if reason and reason ~= "finish" then
		MODERATE_TURN.cancel(reason)
	end
	IsSlipping = false
	LastSlipTime = now
	destroySlipMovement()
	restoreHumanoidState()
	activeSlipProfile = nil
	lastControlledSlideSpeed = 0
	maxObservedSlipSpeed = 0
	slipSpeedWarningPrinted = false
end

local function enforceFallMovementLock()
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	if not activeHumanoid or not root then
		return
	end

	activeHumanoid.WalkSpeed = 0
	activeHumanoid.AutoRotate = false
	activeHumanoid:Move(Vector3.zero, false)
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
	root.AssemblyAngularVelocity = Vector3.zero
end

local function restoreFallTestState(restoreBasket: boolean)
	local activeCharacter = character
	local activeHumanoid = humanoid

	if restoreBasket and fallBasketReleased and activeCharacter and activeCharacter.Parent then
		requestBasketRestore()
	end
	fallBasketReleased = false
	BASKET_RECOVERY.droppedBasket = nil

	if activeCharacter and activeCharacter.Parent then
		activeCharacter:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, false)
		activeCharacter:SetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE, false)
		activeCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
		activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	end
	if activeHumanoid and activeHumanoid.Parent and activeHumanoid.Health > 0 then
		if fallSavedWalkSpeed ~= nil then
			activeHumanoid.WalkSpeed = fallSavedWalkSpeed
		end
		if fallSavedAutoRotate ~= nil then
			activeHumanoid.AutoRotate = fallSavedAutoRotate
		end
	end

	fallSavedWalkSpeed = nil
	fallSavedAutoRotate = nil
	fallDecisionMade = false
	CINEMATIC_CAMERA.finish()
	activeFallSide = nil
	SLIP_CHAIN.fallCause = nil
	SLIP_CHAIN.fallDirection = nil
	resetTurnFeedback(true)
end

BASKET_RECOVERY.getBottom = function(basket: Model?): BasePart?
	if not basket or not basket.Parent then
		return nil
	end
	local bottom = basket:FindFirstChild("Bottom")
	return if bottom and bottom:IsA("BasePart") then bottom else nil
end

BASKET_RECOVERY.stopMove = function()
	BASKET_RECOVERY.moveTarget = nil
	BASKET_RECOVERY.moveToActive = false
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	if activeHumanoid and root and activeHumanoid.Parent and root.Parent then
		activeHumanoid:MoveTo(root.Position)
		activeHumanoid:Move(Vector3.zero, false)
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

BASKET_RECOVERY.commandMove = function(activeHumanoid: Humanoid, target: Vector3)
	BASKET_RECOVERY.moveTarget = target
	BASKET_RECOVERY.moveToActive = true
	activeHumanoid:MoveTo(target)
end

BASKET_RECOVERY.abort = function(token: number)
	if sequenceToken ~= token then
		return
	end
	BASKET_RECOVERY.disconnectMarkers()
	BASKET_RECOVERY.facingActive = false
	BASKET_RECOVERY.pickupCompleteHandled = false
	stopTrack(BASKET_RECOVERY.track, 0.05)
	BASKET_RECOVERY.stopMove()
	BASKET_RECOVERY.setInputLocked(false)
	requestBasketRestore()
	fallBasketReleased = false
	BASKET_RECOVERY.droppedBasket = nil
	local activeCharacter = character
	local activeHumanoid = humanoid
	if activeCharacter and activeCharacter.Parent then
		activeCharacter:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, false)
		activeCharacter:SetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE, false)
		activeCharacter:SetAttribute(IS_SPRINTING_ATTRIBUTE, false)
		activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	end
	if activeHumanoid and activeHumanoid.Parent and activeHumanoid.Health > 0 then
		activeHumanoid.WalkSpeed = BASKET_RECOVERY.normalWalkSpeed
		activeHumanoid.AutoRotate = if fallSavedAutoRotate ~= nil
			then fallSavedAutoRotate
			else true
	end
	fallSavedWalkSpeed = nil
	fallSavedAutoRotate = nil
	visualState = "Idle"
	CINEMATIC_CAMERA.finish()
	activeFallSide = nil
	SLIP_CHAIN.fallCause = nil
	SLIP_CHAIN.fallDirection = nil
end

BASKET_RECOVERY.calculateStandoff = function(
	activeCharacter: Model,
	root: BasePart,
	basket: Model
): (Vector3?, string?)
	local bottom = BASKET_RECOVERY.getBottom(basket)
	if not bottom then
		return nil, "basket_missing"
	end
	local basketPosition = bottom.Position
	local towardCharacter = horizontal(root.Position - basketPosition)
	if towardCharacter.Magnitude < 0.05 then
		towardCharacter = -horizontal(root.CFrame.LookVector)
	end
	if towardCharacter.Magnitude < 0.05 then
		towardCharacter = Vector3.zAxis
	else
		towardCharacter = towardCharacter.Unit
	end
	local desired = basketPosition + towardCharacter * BASKET_RECOVERY.standoff

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { activeCharacter, basket }
	params.IgnoreWater = false
	params.RespectCanCollide = true
	local result = Workspace:Raycast(
		desired + Vector3.new(0, 7, 0),
		Vector3.new(0, -20, 0),
		params
	)
	if not result or not result.Instance.CanCollide then
		return nil, "no_valid_ground"
	end
	return result.Position, nil
end

BASKET_RECOVERY.moveIsCurrent = function(token: number): boolean
	return visualSequenceIsCurrent(token, "SeekDroppedBasket")
		and BASKET_RECOVERY.inputLocked
end

BASKET_RECOVERY.reachedHorizontal = function(
	root: BasePart,
	target: Vector3,
	radius: number
): boolean
	return horizontal(root.Position - target).Magnitude <= radius
end

BASKET_RECOVERY.moveDirectly = function(
	token: number,
	activeHumanoid: Humanoid,
	root: BasePart,
	basket: Model,
	deadline: number
): (boolean, Vector3?, string?)
	local directDeadline = math.min(deadline, os.clock() + BASKET_RECOVERY.directMoveTime)
	local activeCharacter = character
	if not activeCharacter then
		return false, nil, "character_missing"
	end
	-- The standoff side is chosen once. Recomputing it from the moving avatar
	-- makes the destination orbit the basket and produces a music-box turn.
	local target, failureReason = BASKET_RECOVERY.calculateStandoff(
		activeCharacter,
		root,
		basket
	)
	if not target then
		return false, nil, failureReason
	end
	BASKET_RECOVERY.commandMove(activeHumanoid, target)
	while BASKET_RECOVERY.moveIsCurrent(token) and os.clock() < directDeadline do
		if BASKET_RECOVERY.reachedHorizontal(root, target, BASKET_RECOVERY.reachedDistance) then
			return true, target, nil
		end
		RunService.Heartbeat:Wait()
	end
	return false, target, "direct_move_incomplete"
end

BASKET_RECOVERY.followPath = function(
	token: number,
	activeHumanoid: Humanoid,
	root: BasePart,
	basket: Model,
	deadline: number
): (boolean, Vector3?, string?)
	local activeCharacter = character
	if not activeCharacter then
		return false, nil, "character_missing"
	end
	local target, targetFailure = BASKET_RECOVERY.calculateStandoff(activeCharacter, root, basket)
	if not target then
		return false, nil, targetFailure
	end

	local path = BASKET_RECOVERY.pathfindingService:CreatePath({
		AgentCanJump = false,
		WaypointSpacing = 3,
	})
	local computed = pcall(function()
		path:ComputeAsync(root.Position, target)
	end)
	if not computed or path.Status ~= Enum.PathStatus.Success then
		return false, target, "no_path"
	end

	local waypoints = path:GetWaypoints()
	local finalWaypointIndex = math.min(#waypoints, 7)
	for index = 2, finalWaypointIndex do
		if not BASKET_RECOVERY.moveIsCurrent(token) or os.clock() >= deadline then
			return false, target, "path_timeout"
		end
		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			return false, target, "path_requires_jump"
		end
		BASKET_RECOVERY.commandMove(activeHumanoid, waypoint.Position)
		while BASKET_RECOVERY.moveIsCurrent(token)
			and os.clock() < deadline
			and not BASKET_RECOVERY.reachedHorizontal(root, waypoint.Position, 0.75)
		do
			RunService.Heartbeat:Wait()
		end
	end

	if BASKET_RECOVERY.moveIsCurrent(token) then
		BASKET_RECOVERY.commandMove(activeHumanoid, target)
		while os.clock() < deadline
			and BASKET_RECOVERY.moveIsCurrent(token)
			and not BASKET_RECOVERY.reachedHorizontal(root, target, BASKET_RECOVERY.reachedDistance)
		do
			RunService.Heartbeat:Wait()
		end
	end
	return BASKET_RECOVERY.reachedHorizontal(root, target, BASKET_RECOVERY.reachedDistance),
		target,
		"path_timeout"
end

BASKET_RECOVERY.faceBasket = function(token: number, basket: Model): boolean
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	local bottom = BASKET_RECOVERY.getBottom(basket)
	if not activeHumanoid or not root or not bottom then
		BASKET_RECOVERY.facingActive = false
		return false
	end
	BASKET_RECOVERY.facingActive = true
	activeHumanoid.WalkSpeed = 0
	activeHumanoid.AutoRotate = false
	BASKET_RECOVERY.stopMove()
	local startRotation = root.CFrame.Rotation
	local flatTarget = Vector3.new(bottom.Position.X, root.Position.Y, bottom.Position.Z)
	if (flatTarget - root.Position).Magnitude < 0.05 then
		BASKET_RECOVERY.facingActive = false
		return true
	end
	local targetRotation = CFrame.lookAt(root.Position, flatTarget).Rotation
	local elapsed = 0
	while elapsed < BASKET_RECOVERY.faceDuration do
		local deltaTime = RunService.Heartbeat:Wait()
		if not BASKET_RECOVERY.moveIsCurrent(token) then
			BASKET_RECOVERY.facingActive = false
			return false
		end
		elapsed = math.min(elapsed + deltaTime, BASKET_RECOVERY.faceDuration)
		local alpha = smoothStep(elapsed / BASKET_RECOVERY.faceDuration)
		root.CFrame = CFrame.new(root.Position) * startRotation:Lerp(targetRotation, alpha)
	end
	BASKET_RECOVERY.facingActive = false
	return true
end

BASKET_RECOVERY.restoreMovement = function(token: number)
	if not visualSequenceIsCurrent(token, "BasketHoldTransition") then
		return
	end
	local activeCharacter = character
	local activeHumanoid = humanoid
	if not activeCharacter or not activeHumanoid then
		return
	end
	BASKET_RECOVERY.stopMove()
	BASKET_RECOVERY.facingActive = false
	activeCharacter:SetAttribute(IS_SPRINTING_ATTRIBUTE, false)
	activeCharacter:SetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE, false)
	activeCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
	activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	activeHumanoid.WalkSpeed = BASKET_RECOVERY.normalWalkSpeed
	activeHumanoid.AutoRotate = if fallSavedAutoRotate ~= nil
		then fallSavedAutoRotate
		else true
	local completedChainBackFall = SLIP_CHAIN.fallCause == "chain"
		and SLIP_CHAIN.fallDirection == "back"
	visualState = "Idle"
	activeCharacter:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, false)
	BASKET_RECOVERY.setInputLocked(false)
	fallSavedWalkSpeed = nil
	fallSavedAutoRotate = nil
	fallBasketReleased = false
	BASKET_RECOVERY.droppedBasket = nil
	fallDecisionMade = false
	CINEMATIC_CAMERA.finish()
	activeFallSide = nil
	SLIP_CHAIN.fallCause = nil
	SLIP_CHAIN.fallDirection = nil
	SLIP_CHAIN.reset("recovery")
	resetTurnFeedback(true)
	print("[BasketRecovery] state=Idle")
	if completedChainBackFall then
		print("[ChainBackFall] recovery complete")
	end
end

BASKET_RECOVERY.beginPickup = function(expectedToken: number)
	if not visualSequenceIsCurrent(expectedToken, "SeekDroppedBasket") then
		return
	end
	local basket = BASKET_RECOVERY.droppedBasket
	local activeHumanoid = humanoid
	local track = BASKET_RECOVERY.track
	local resolvedLength = BASKET_RECOVERY.length
	if not basket
		or not basket.Parent
		or not activeHumanoid
		or not track
		or not resolvedLength
	then
		BASKET_RECOVERY.abort(expectedToken)
		return
	end
	local activeBasket = basket :: Model

	BASKET_RECOVERY.pickupCompleteHandled = false
	if BASKET_RECOVERY.facingActive then
		warn("[BasketRecovery] facing controller was still active at BasketPickup start")
		BASKET_RECOVERY.facingActive = false
	end
	visualState = "BasketPickup"
	local activeCharacter = character
	if activeCharacter and activeCharacter.Parent then
		-- Keep the shared fall lock released throughout recovery. Its other
		-- consumer always forces WalkSpeed=0 and can also restore a stale
		-- AutoRotate value. This controller's input sink and stationary branch own
		-- BasketPickup until PickupComplete.
		activeCharacter:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, false)
		activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, true)
	end
	activeHumanoid.WalkSpeed = 0
	activeHumanoid.AutoRotate = false
	BASKET_RECOVERY.stopMove()
	BASKET_RECOVERY.disconnectMarkers()
	local grabbed = false
	local overhead = false
	local completed = false

	local function executeGrab()
		if grabbed or not visualSequenceIsCurrent(expectedToken, "BasketPickup") then
			return
		end
		grabbed = true
		if not BASKET_RECOVERY.requestStage("Grab", activeBasket) then
			local repositioned = BASKET_RECOVERY.requestEmergencyReposition(activeBasket, "grab_rejected")
			if not repositioned or not BASKET_RECOVERY.requestStage("Grab", activeBasket) then
					BASKET_RECOVERY.abort(expectedToken)
			end
		end
		print("[BasketRecovery] marker=GrabBasket")
	end

	local function executeOverhead()
		if overhead or not visualSequenceIsCurrent(expectedToken, "BasketPickup") then
			return
		end
		if not grabbed then
			executeGrab()
		end
		if not visualSequenceIsCurrent(expectedToken, "BasketPickup") then
			return
		end
		overhead = true
		if not BASKET_RECOVERY.requestStage("Overhead", activeBasket) then
			BASKET_RECOVERY.abort(expectedToken)
			return
		end
		print("[BasketRecovery] marker=BasketOverhead")
	end

	local function executeComplete()
		if completed
			or BASKET_RECOVERY.pickupCompleteHandled
			or not visualSequenceIsCurrent(expectedToken, "BasketPickup")
		then
			return
		end
		if not overhead then
			executeOverhead()
		end
		if not visualSequenceIsCurrent(expectedToken, "BasketPickup") then
			return
		end
		completed = true
		BASKET_RECOVERY.pickupCompleteHandled = true
		print("[BasketRecovery] marker=PickupComplete")
		BASKET_RECOVERY.disconnectMarkers()
		BASKET_RECOVERY.facingActive = false
		BASKET_RECOVERY.stopMove()
		visualState = "BasketHoldTransition"
		track:AdjustWeight(0, BASKET_RECOVERY.holdTransitionDuration)
		task.delay(BASKET_RECOVERY.holdTransitionDuration, function()
			if not visualSequenceIsCurrent(expectedToken, "BasketHoldTransition") then
				return
			end
			track:Stop(0)
			track:AdjustWeight(0, 0)
			if track.IsPlaying then
				warn("[BasketRecovery] BasketPickup remained playing after forced stop")
				track:Stop(0)
			end
			if not BASKET_RECOVERY.requestStage("Complete", activeBasket) then
				BASKET_RECOVERY.abort(expectedToken)
				return
			end
			local root = humanoidRootPart
			local startLook = root and horizontal(root.CFrame.LookVector) or Vector3.zAxis
			BASKET_RECOVERY.restoreMovement(expectedToken)
			task.delay(1, function()
				if sequenceToken ~= expectedToken or not root or not root.Parent then
					return
				end
				local postSnapshot = BASKET_RECOVERY.requestDebugSnapshot()
				local currentLook = horizontal(root.CFrame.LookVector)
				local yawDelta = 0
				if startLook.Magnitude > 0.001 and currentLook.Magnitude > 0.001 then
					yawDelta = math.deg(math.acos(math.clamp(
						startLook.Unit:Dot(currentLook.Unit),
						-1,
						1
					)))
				end
				local rootAngularSpeed = root.AssemblyAngularVelocity.Magnitude
				local basketAngularSpeed = postSnapshot and postSnapshot.basketAngularSpeed or -1
				local tempGrips = postSnapshot and postSnapshot.tempGrips or -1
				local overheadAttachments = postSnapshot and postSnapshot.overheadAttachments or -1
				local mountPositionError = postSnapshot and postSnapshot.mountPositionError or -1
				local mountAngleError = postSnapshot and postSnapshot.mountAngleError or -1
				if track.IsPlaying then
					warn("[BasketRecovery] BasketPickup still playing one second after completion")
				end
				if rootAngularSpeed > 0.05 or yawDelta > 1 then
					warn(string.format(
						"[BasketRecovery] unexpected post-pickup rotation angular=%.4f yaw=%.3f",
						rootAngularSpeed,
						yawDelta
					))
				end
				if basketAngularSpeed > 0.05 then
					warn(string.format(
						"[BasketRecovery] recovered basket retained angular speed %.4f",
						basketAngularSpeed
					))
				end
				if postSnapshot and not postSnapshot.holdPlaying then
					warn("[BasketRecovery] BasketHold was not playing one second after completion")
				end
				if tempGrips ~= 0 or overheadAttachments ~= 1 then
					warn(string.format(
						"[BasketRecovery] invalid attachment counts temp=%d overhead=%d",
						tempGrips,
						overheadAttachments
					))
				end
				if postSnapshot and postSnapshot.carriedPhysicsInvalid then
					warn("[BasketRecovery] carried basket retained collision or non-massless parts")
				end
				if mountPositionError > 0.10 then
					warn(string.format(
						"[BasketRecovery] recovered basket mount position error %.4f studs",
						mountPositionError
					))
				end
				if mountAngleError > 1 then
					warn(string.format(
						"[BasketRecovery] recovered basket mount angle error %.3f degrees",
						mountAngleError
					))
				end
			end)
		end)
	end

	table.insert(
		BASKET_RECOVERY.markerConnections,
		track:GetMarkerReachedSignal("GrabBasket"):Connect(executeGrab)
	)
	table.insert(
		BASKET_RECOVERY.markerConnections,
		track:GetMarkerReachedSignal("BasketOverhead"):Connect(executeOverhead)
	)
	table.insert(
		BASKET_RECOVERY.markerConnections,
		track:GetMarkerReachedSignal("PickupComplete"):Connect(executeComplete)
	)

	if track.IsPlaying then
		track:Stop(0)
	end
	track.TimePosition = 0
	track:Play(BASKET_RECOVERY.pickupFade, 1, 1)
	track:AdjustSpeed(1)
	print("[BasketRecovery] state=BasketPickup")

	task.spawn(function()
		local observedPlaying = false
		while visualSequenceIsCurrent(expectedToken, "BasketPickup")
			and track == BASKET_RECOVERY.track
		do
			observedPlaying = observedPlaying or track.IsPlaying
			local actualLength = if track.Length > 0 then track.Length else resolvedLength
			local normalized = if actualLength > 0 then track.TimePosition / actualLength else 0
			if not grabbed and normalized >= BASKET_RECOVERY.grabNormalizedTime then
				executeGrab()
			end
			if not overhead and normalized >= BASKET_RECOVERY.overheadNormalizedTime then
				executeOverhead()
			end
			if not completed and (
				track.TimePosition >= math.max(actualLength - BASKET_RECOVERY.completeEndOffset, 0)
				or (observedPlaying and not track.IsPlaying)
			)
			then
				executeComplete()
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

BASKET_RECOVERY.beginSeek = function(expectedToken: number)
	local getUpState = visualState
	if getUpState ~= "GetUpLeft"
		and getUpState ~= "GetUpRight"
		and getUpState ~= "GetUpBack"
	then
		return
	end
	if not visualSequenceIsCurrent(expectedToken, getUpState) then
		return
	end
	local activeCharacter = character
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	local getUpTrack = if getUpState == "GetUpBack"
		then CHAIN_BACK.getUpTrack
		elseif getUpState == "GetUpRight"
		then getUpRightTrack
		else getUpLeftTrack
	if not activeCharacter or not activeHumanoid or not root then
		BASKET_RECOVERY.abort(expectedToken)
		return
	end

	local basket = BASKET_RECOVERY.droppedBasket
	if not basket or not basket.Parent then
		basket = BASKET_RECOVERY.requestCurrentBasket()
		BASKET_RECOVERY.droppedBasket = basket
	end
	local bottom = BASKET_RECOVERY.getBottom(basket)
	if not basket or not bottom then
		BASKET_RECOVERY.abort(expectedToken)
		return
	end
	local activeBasket = basket :: Model

	visualState = "SeekDroppedBasket"
	BASKET_RECOVERY.setInputLocked(true)
	activeCharacter:SetAttribute(IS_SPRINTING_ATTRIBUTE, false)
	-- FallMovementLocked is also consumed by ShiftSprintController, which
	-- intentionally forces WalkSpeed=0. Seek has its own high-priority input
	-- sink, so release that stationary lock only for the automatic walk and
	-- mark movement as controller-owned to prevent normal/sprint speed writes.
	activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, true)
	activeCharacter:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, false)
	activeHumanoid.WalkSpeed = BASKET_RECOVERY.walkSpeed
	activeHumanoid.AutoRotate = true
	if getUpTrack then
		getUpTrack:Stop(0.10)
	end
	local initialDistance = horizontal(bottom.Position - root.Position).Magnitude
	print(string.format("[BasketRecovery] state=SeekDroppedBasket distance=%.2f", initialDistance))
	if SLIP_CHAIN.fallCause == "chain" and SLIP_CHAIN.fallDirection == "back" then
		print("[ChainBackFall] state=SeekDroppedBasket")
	end

	task.spawn(function()
		local settled = false
		local settleDeadline = os.clock() + BASKET_RECOVERY.settleTimeout
		while BASKET_RECOVERY.moveIsCurrent(expectedToken) and os.clock() < settleDeadline do
			local activeBottom = BASKET_RECOVERY.getBottom(activeBasket)
			if not activeBottom then
				BASKET_RECOVERY.abort(expectedToken)
				return
			end
			if activeBottom.AssemblyLinearVelocity.Magnitude <= BASKET_RECOVERY.settleLinearSpeed
				and activeBottom.AssemblyAngularVelocity.Magnitude <= BASKET_RECOVERY.settleAngularSpeed
			then
				settled = true
				break
			end
			RunService.Heartbeat:Wait()
		end
		if not BASKET_RECOVERY.moveIsCurrent(expectedToken) then
			return
		end
		print(string.format("[BasketRecovery] basket settled=%s", tostring(settled)))

		-- Establish the approach heading once, quickly, before Humanoid movement
		-- begins. Without this short pre-alignment AutoRotate can spend most of the
		-- approach slowly steering around the basket, which reads like an orbit.
		if not BASKET_RECOVERY.faceBasket(expectedToken, activeBasket) then
			BASKET_RECOVERY.abort(expectedToken)
			return
		end
		if not BASKET_RECOVERY.moveIsCurrent(expectedToken) then
			return
		end
		activeHumanoid.WalkSpeed = BASKET_RECOVERY.walkSpeed
		activeHumanoid.AutoRotate = true

		local activeBottom = BASKET_RECOVERY.getBottom(activeBasket)
		if not activeBottom then
			BASKET_RECOVERY.abort(expectedToken)
			return
		end
		local distance = horizontal(activeBottom.Position - root.Position).Magnitude
		local emergencyReason: string? = nil
		if activeBottom.Position.Y < Workspace.FallenPartsDestroyHeight + 5 then
			emergencyReason = "below_playable_area"
		elseif distance > BASKET_RECOVERY.hardRadius then
			emergencyReason = "excessive_distance"
		elseif distance > BASKET_RECOVERY.maxRadius then
			emergencyReason = "outside_recovery_radius"
		end

		local reached = false
		local target: Vector3? = nil
		if not emergencyReason then
			local deadline = os.clock() + BASKET_RECOVERY.approachTimeout
			local directReason: string?
			reached, target, directReason = BASKET_RECOVERY.moveDirectly(
				expectedToken,
				activeHumanoid,
				root,
				activeBasket,
				deadline
			)
			if not reached and BASKET_RECOVERY.moveIsCurrent(expectedToken) then
				local pathReason: string?
				reached, target, pathReason = BASKET_RECOVERY.followPath(
					expectedToken,
					activeHumanoid,
					root,
					activeBasket,
					deadline
				)
				emergencyReason = if reached then nil else (pathReason or directReason or "approach_timeout")
			end
		end

		if not BASKET_RECOVERY.moveIsCurrent(expectedToken) then
			return
		end
		if not reached then
			local repositioned = BASKET_RECOVERY.requestEmergencyReposition(
				activeBasket,
				emergencyReason or "approach_timeout"
			)
			if not repositioned then
				BASKET_RECOVERY.abort(expectedToken)
				return
			end
			BASKET_RECOVERY.droppedBasket = repositioned
			activeBasket = repositioned
			local repositionTarget = BASKET_RECOVERY.calculateStandoff(activeCharacter, root, activeBasket)
			if not repositionTarget then
				BASKET_RECOVERY.abort(expectedToken)
				return
			end
			BASKET_RECOVERY.commandMove(activeHumanoid, repositionTarget)
			local repositionDeadline = os.clock() + 0.75
			while BASKET_RECOVERY.moveIsCurrent(expectedToken)
				and os.clock() < repositionDeadline
				and not BASKET_RECOVERY.reachedHorizontal(root, repositionTarget, BASKET_RECOVERY.reachedDistance)
			do
				RunService.Heartbeat:Wait()
			end
			reached = BASKET_RECOVERY.reachedHorizontal(
				root,
				repositionTarget,
				BASKET_RECOVERY.reachedDistance
			)
			if not reached then
				-- Never weld a basket to a hand while the avatar is still too far
				-- away; that preserved offset is what made the lift look detached.
				BASKET_RECOVERY.abort(expectedToken)
				return
			end
		end

		if not BASKET_RECOVERY.moveIsCurrent(expectedToken) then
			return
		end
		print("[BasketRecovery] approach complete")
		if not BASKET_RECOVERY.faceBasket(expectedToken, activeBasket) then
			BASKET_RECOVERY.abort(expectedToken)
			return
		end
		BASKET_RECOVERY.beginPickup(expectedToken)
	end)
end

function CHAIN_BACK.monitorFall(
	fallToken: number,
	track: AnimationTrack,
	resolvedLength: number
)
	CHAIN_BACK.disconnectMarkers()
	local basketReleased = false
	local backImpactHandled = false
	local fallCompleteHandled = false

	local function executeBasketRelease()
		if basketReleased
			or not visualSequenceIsCurrent(fallToken, "FallStraightBack")
			or track ~= CHAIN_BACK.fallTrack
		then
			return
		end
		basketReleased = true
		if not fallBasketReleased then
			BASKET_RECOVERY.droppedBasket = requestBasketRelease("Back")
			fallBasketReleased = BASKET_RECOVERY.droppedBasket ~= nil
		end
		print("[ChainBackFall] marker=BasketRelease")
	end

	local function executeBackImpact()
		if backImpactHandled
			or not visualSequenceIsCurrent(fallToken, "FallStraightBack")
			or track ~= CHAIN_BACK.fallTrack
		then
			return
		end
		backImpactHandled = true
		enforceFallMovementLock()
		SLIP_CHAIN.hideWarningFeedback()
		print("[ChainBackFall] marker=BackImpact")
	end

	local function executeFallComplete()
		if fallCompleteHandled
			or not visualSequenceIsCurrent(fallToken, "FallStraightBack")
			or track ~= CHAIN_BACK.fallTrack
		then
			return
		end
		fallCompleteHandled = true
		if not basketReleased then
			executeBasketRelease()
		end
		if not backImpactHandled then
			executeBackImpact()
		end
		CHAIN_BACK.disconnectMarkers()
		local actualLength = if track.Length > 0 then track.Length else resolvedLength
		local holdPosition = math.max(actualLength - FALL_FINAL_HOLD_OFFSET, 0)
		if not track.IsPlaying then
			track:Play(0, 1, 1)
		end
		track.TimePosition = holdPosition
		track:AdjustSpeed(0)
		visualState = "FallenHold"
		enforceFallMovementLock()
		print("[ChainBackFall] state=FallenHold")
		task.delay(FALLEN_HOLD_DURATION, function()
			if visualSequenceIsCurrent(fallToken, "FallenHold")
				and SLIP_CHAIN.fallCause == "chain"
				and SLIP_CHAIN.fallDirection == "back"
			then
				beginGetUp(fallToken)
			end
		end)
	end

	table.insert(
		CHAIN_BACK.markerConnections,
		track:GetMarkerReachedSignal("BasketRelease"):Connect(executeBasketRelease)
	)
	table.insert(
		CHAIN_BACK.markerConnections,
		track:GetMarkerReachedSignal("BackImpact"):Connect(executeBackImpact)
	)
	table.insert(
		CHAIN_BACK.markerConnections,
		track:GetMarkerReachedSignal("FallComplete"):Connect(executeFallComplete)
	)

	task.spawn(function()
		local observedPlaying = false
		while visualSequenceIsCurrent(fallToken, "FallStraightBack")
			and track == CHAIN_BACK.fallTrack
		do
			observedPlaying = observedPlaying or track.IsPlaying
			local actualLength = if track.Length > 0 then track.Length else resolvedLength
			local normalized = if actualLength > 0 then track.TimePosition / actualLength else 0
			if not basketReleased
				and normalized >= CHAIN_BACK.fallBasketReleaseNormalizedTime
			then
				executeBasketRelease()
			end
			if not backImpactHandled
				and normalized >= CHAIN_BACK.fallBackImpactNormalizedTime
			then
				executeBackImpact()
			end
			if not fallCompleteHandled and (
				track.TimePosition >= math.max(actualLength - FALL_FINAL_HOLD_OFFSET, 0)
				or (observedPlaying and not track.IsPlaying)
			) then
				executeFallComplete()
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

function CHAIN_BACK.monitorGetUp(
	getUpToken: number,
	track: AnimationTrack,
	resolvedLength: number
)
	CHAIN_BACK.disconnectMarkers()
	local handPlantHandled = false
	local halfKneelHandled = false
	local getUpCompleteHandled = false

	local function executeHandPlant()
		if handPlantHandled
			or not visualSequenceIsCurrent(getUpToken, "GetUpBack")
			or track ~= CHAIN_BACK.getUpTrack
		then
			return
		end
		handPlantHandled = true
		enforceFallMovementLock()
	end

	local function executeHalfKneel()
		if halfKneelHandled
			or not visualSequenceIsCurrent(getUpToken, "GetUpBack")
			or track ~= CHAIN_BACK.getUpTrack
		then
			return
		end
		halfKneelHandled = true
		enforceFallMovementLock()
	end

	local function executeGetUpComplete()
		if getUpCompleteHandled
			or not visualSequenceIsCurrent(getUpToken, "GetUpBack")
			or track ~= CHAIN_BACK.getUpTrack
		then
			return
		end
		getUpCompleteHandled = true
		CHAIN_BACK.disconnectMarkers()
		track:AdjustWeight(0, GET_UP_TRANSITION_FADE)
		task.delay(GET_UP_TRANSITION_FADE, function()
			if not visualSequenceIsCurrent(getUpToken, "GetUpBack") then
				return
			end
			track:Stop(0)
			track:AdjustWeight(0, 0)
			BASKET_RECOVERY.beginSeek(getUpToken)
		end)
	end

	table.insert(
		CHAIN_BACK.markerConnections,
		track:GetMarkerReachedSignal("HandPlant"):Connect(executeHandPlant)
	)
	table.insert(
		CHAIN_BACK.markerConnections,
		track:GetMarkerReachedSignal("HalfKneel"):Connect(executeHalfKneel)
	)
	table.insert(
		CHAIN_BACK.markerConnections,
		track:GetMarkerReachedSignal("GetUpComplete"):Connect(executeGetUpComplete)
	)

	task.spawn(function()
		local observedPlaying = false
		while visualSequenceIsCurrent(getUpToken, "GetUpBack")
			and track == CHAIN_BACK.getUpTrack
		do
			observedPlaying = observedPlaying or track.IsPlaying
			local actualLength = if track.Length > 0 then track.Length else resolvedLength
			local normalized = if actualLength > 0 then track.TimePosition / actualLength else 0
			if not handPlantHandled
				and normalized >= CHAIN_BACK.getUpHandPlantNormalizedTime
			then
				executeHandPlant()
			end
			if not halfKneelHandled
				and normalized >= CHAIN_BACK.getUpHalfKneelNormalizedTime
			then
				executeHalfKneel()
			end
			if not getUpCompleteHandled and (
				track.TimePosition >= math.max(actualLength - GET_UP_FINAL_HOLD_OFFSET, 0)
				or (observedPlaying and not track.IsPlaying)
			) then
				executeGetUpComplete()
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

function CHAIN_BACK.beginGetUp(expectedToken: number)
	if not visualSequenceIsCurrent(expectedToken, "FallenHold")
		or SLIP_CHAIN.fallCause ~= "chain"
		or SLIP_CHAIN.fallDirection ~= "back"
	then
		return
	end
	local animator = characterAnimator
	local fallTrack = CHAIN_BACK.fallTrack
	local getUpTrack = CHAIN_BACK.getUpTrack
	local getUpLength = CHAIN_BACK.getUpLength
	if not animator or not fallTrack or not getUpTrack or not getUpLength then
		return
	end

	visualState = "GetUpBack"
	enforceFallMovementLock()
	stopBasketHoldForFall(animator)
	if getUpTrack.IsPlaying then
		getUpTrack:Stop(0)
	end
	getUpTrack.TimePosition = 0
	CHAIN_BACK.monitorGetUp(expectedToken, getUpTrack, getUpLength)
	getUpTrack:Play(GET_UP_TRANSITION_FADE, 1, 1)
	getUpTrack:AdjustSpeed(1)
	fallTrack:Stop(GET_UP_TRANSITION_FADE)
	print("[ChainBackFall] transition=GetUpBack")
end

function CHAIN_BACK.beginFall(expectedToken: number)
	if SLIP_CHAIN.fallCause ~= "chain"
		or SLIP_CHAIN.fallDirection ~= "back"
		or not SLIP_CHAIN.fallCommitted
		or not visualSequenceIsCurrent(expectedToken, "SlipStruggle")
	then
		return
	end
	local activeCharacter = character
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	local animator = characterAnimator
	local struggleTrack = slipStruggleTrack
	local fallTrack = CHAIN_BACK.fallTrack
	local fallLength = CHAIN_BACK.fallLength
	if not activeCharacter
		or not activeHumanoid
		or not root
		or not animator
		or not struggleTrack
		or not fallTrack
		or not fallLength
	then
		return
	end

	SLIP_CHAIN.reset("fall")
	sequenceToken += 1
	local fallToken = sequenceToken
	activeFallSide = nil
	visualState = "FallStraightBack"
	CINEMATIC_CAMERA.begin()
	if fallSavedWalkSpeed == nil then
		fallSavedWalkSpeed = BASKET_RECOVERY.normalWalkSpeed
	end
	if fallSavedAutoRotate == nil then
		fallSavedAutoRotate = if originalAutoRotate ~= nil
			then originalAutoRotate
			else activeHumanoid.AutoRotate
	end

	activeCharacter:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, true)
	activeCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
	activeCharacter:SetAttribute(IS_SPRINTING_ATTRIBUTE, false)
	endSlip(os.clock(), "fall")
	activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	enforceFallMovementLock()
	stopBasketHoldForFall(animator)
	stopTrack(slipStartTrack, FALL_TRANSITION_FADE)
	stopTrack(slipRecoverTrack, FALL_TRANSITION_FADE)
	stopTrack(CHAIN_BACK.getUpTrack, 0)
	if fallTrack.IsPlaying then
		fallTrack:Stop(0)
	end
	fallTrack.Priority = struggleTrack.Priority
	fallTrack.TimePosition = 0
	CHAIN_BACK.monitorFall(fallToken, fallTrack, fallLength)
	fallTrack:Play(FALL_TRANSITION_FADE, 1, 1)
	fallTrack:AdjustSpeed(1)
	struggleTrack:Stop(FALL_TRANSITION_FADE)
	task.delay(FALL_TRANSITION_FADE, function()
		if sequenceToken == fallToken
			and fallTrack == CHAIN_BACK.fallTrack
			and visualState == "FallStraightBack"
		then
			fallTrack.Priority = Enum.AnimationPriority.Action4
		end
	end)
end

local function monitorAndHoldFallFinalPose(
	fallToken: number,
	fallTrack: AnimationTrack,
	resolvedLength: number,
	side: FallSide
)
	local fallState: VisualState = if side == "Right" then "FallBackRight" else "FallBackLeft"
	local expectedTrack = if side == "Right" then fallBackRightTrack else fallBackLeftTrack
	task.spawn(function()
		local observedPlaying = false
		while visualSequenceIsCurrent(fallToken, fallState)
			and fallTrack == expectedTrack
		do
			observedPlaying = observedPlaying or fallTrack.IsPlaying
			local actualLength = if fallTrack.Length > 0
				then fallTrack.Length
				else resolvedLength
			local holdPosition = math.max(actualLength - FALL_FINAL_HOLD_OFFSET, 0)
			local reachedNearEnd = fallTrack.IsPlaying
				and fallTrack.TimePosition >= math.max(
					holdPosition - FALL_FINAL_HOLD_POLL_MARGIN,
					0
				)
			local endedBeforePoll = observedPlaying and not fallTrack.IsPlaying

			if reachedNearEnd or endedBeforePoll then
				-- The normal path freezes before Stopped. The replay fallback covers a
				-- frame-rate hitch that lets the non-looping track stop between polls.
				if not fallTrack.IsPlaying then
					fallTrack:Play(0, 1, 1)
				end
				fallTrack.TimePosition = holdPosition
				fallTrack:AdjustSpeed(0)
				visualState = "FallenHold"
				enforceFallMovementLock()
				task.delay(FALLEN_HOLD_DURATION, function()
					if visualSequenceIsCurrent(fallToken, "FallenHold") then
						beginGetUp(fallToken)
					end
				end)
				return
			end

			RunService.Heartbeat:Wait()
		end
	end)
end

local function monitorAndHoldGetUpFinalPose(
	getUpToken: number,
	getUpTrack: AnimationTrack,
	resolvedLength: number,
	side: FallSide
)
	local getUpState: VisualState = if side == "Right" then "GetUpRight" else "GetUpLeft"
	local expectedTrack = if side == "Right" then getUpRightTrack else getUpLeftTrack
	task.spawn(function()
		local observedPlaying = false
		while visualSequenceIsCurrent(getUpToken, getUpState)
			and getUpTrack == expectedTrack
		do
			observedPlaying = observedPlaying or getUpTrack.IsPlaying
			local actualLength = if getUpTrack.Length > 0
				then getUpTrack.Length
				else resolvedLength
			local holdPosition = math.max(actualLength - GET_UP_FINAL_HOLD_OFFSET, 0)
			local reachedNearEnd = getUpTrack.IsPlaying
				and getUpTrack.TimePosition >= math.max(
					holdPosition - FALL_FINAL_HOLD_POLL_MARGIN,
					0
				)
			local endedBeforePoll = observedPlaying and not getUpTrack.IsPlaying

			if reachedNearEnd or endedBeforePoll then
				if not getUpTrack.IsPlaying then
					getUpTrack:Play(0, 1, 1)
				end
				getUpTrack.TimePosition = holdPosition
				getUpTrack:AdjustSpeed(0)
				enforceFallMovementLock()
				BASKET_RECOVERY.beginSeek(getUpToken)
				return
			end

			RunService.Heartbeat:Wait()
		end
	end)
end

beginGetUp = function(expectedToken: number)
	if not visualSequenceIsCurrent(expectedToken, "FallenHold") then
		return
	end
	if SLIP_CHAIN.fallCause == "chain" and SLIP_CHAIN.fallDirection == "back" then
		CHAIN_BACK.beginGetUp(expectedToken)
		return
	end
	local side = activeFallSide
	if not side then
		return
	end

	local animator = characterAnimator
	local fallTrack = if side == "Right" then fallBackRightTrack else fallBackLeftTrack
	local getUpTrack = if side == "Right" then getUpRightTrack else getUpLeftTrack
	local getUpLength = if side == "Right" then getUpRightLength else getUpLeftLength
	if not animator or not fallTrack or not getUpTrack or not getUpLength then
		return
	end

	visualState = if side == "Right" then "GetUpRight" else "GetUpLeft"
	enforceFallMovementLock()
	stopBasketHoldForFall(animator)
	if getUpTrack.IsPlaying then
		getUpTrack:Stop(0)
	end
	getUpTrack.TimePosition = 0
	getUpTrack:Play(GET_UP_TRANSITION_FADE, 1, 1)
	getUpTrack:AdjustSpeed(1)
	fallTrack:Stop(GET_UP_TRANSITION_FADE)
	monitorAndHoldGetUpFinalPose(expectedToken, getUpTrack, getUpLength, side)
end

local function scheduleBasketRelease(
	fallToken: number,
	fallTrack: AnimationTrack,
	side: FallSide
)
	local fallState: VisualState = if side == "Right" then "FallBackRight" else "FallBackLeft"
	local expectedTrack = if side == "Right" then fallBackRightTrack else fallBackLeftTrack
	task.spawn(function()
		local releaseTimePosition = FALL_ENTRY_TIME_POSITION + FALL_BASKET_RELEASE_DELAY
		while visualSequenceIsCurrent(fallToken, fallState)
			and fallTrack == expectedTrack
			and fallTrack.IsPlaying
			and fallTrack.TimePosition < releaseTimePosition
		do
			RunService.Heartbeat:Wait()
		end

		if not visualSequenceIsCurrent(fallToken, fallState)
			or fallTrack ~= expectedTrack
			or fallBasketReleased
		then
			return
		end

		BASKET_RECOVERY.droppedBasket = requestBasketRelease(side)
		fallBasketReleased = BASKET_RECOVERY.droppedBasket ~= nil
		if BASKET_RECOVERY.droppedBasket then
			SHARP_TURN.tossReleasedBasket(
				BASKET_RECOVERY.droppedBasket,
				fallToken,
				side
			)
		end
	end)
end

beginFallBack = function(side: FallSide, expectedToken: number)
	if fallSideForThisSlip() ~= side
		or not visualSequenceIsCurrent(expectedToken, "SlipStruggle")
	then
		return
	end

	local activeCharacter = character
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	local animator = characterAnimator
	local struggleTrack = slipStruggleTrack
	local fallTrack = if side == "Right" then fallBackRightTrack else fallBackLeftTrack
	local fallLength = if side == "Right" then fallBackRightLength else fallBackLeftLength
	if not activeCharacter
		or not activeHumanoid
		or not root
		or not animator
		or not struggleTrack
		or not fallTrack
		or not fallLength
	then
		return
	end
	SLIP_CHAIN.reset("fall")

	-- Invalidate the already-scheduled SlipStruggle -> SlipRecover callback.
	sequenceToken += 1
	local fallToken = sequenceToken
	activeFallSide = side
	visualState = if side == "Right" then "FallBackRight" else "FallBackLeft"
	CINEMATIC_CAMERA.begin()

	if fallSavedWalkSpeed == nil then
		fallSavedWalkSpeed = BASKET_RECOVERY.normalWalkSpeed
	end
	if fallSavedAutoRotate == nil then
		fallSavedAutoRotate = if originalAutoRotate ~= nil
			then originalAutoRotate
			else activeHumanoid.AutoRotate
	end

	-- Publish the lock before clearing the slip flag so ShiftSprintController
	-- cannot restore movement between the two states.
	activeCharacter:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, true)
	activeCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
	endSlip(os.clock(), "fall")
	activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	enforceFallMovementLock()

	stopBasketHoldForFall(animator)
	stopTrack(slipStartTrack, FALL_TRANSITION_FADE)
	stopTrack(slipRecoverTrack, FALL_TRANSITION_FADE)
	if fallTrack.IsPlaying then
		fallTrack:Stop(0)
	end
	-- Blend on the same priority as SlipStruggle so the lateral
	-- imbalance remains visible throughout the crossfade. Promote to Action4
	-- only after the selected fall track has reached full weight.
	fallTrack.Priority = struggleTrack.Priority
	fallTrack:Play(FALL_TRANSITION_FADE, 1, 1)
	fallTrack.TimePosition = math.min(FALL_ENTRY_TIME_POSITION, math.max(fallLength - 0.02, 0))
	fallTrack:AdjustSpeed(1)
	struggleTrack:Stop(FALL_TRANSITION_FADE)
	task.delay(FALL_TRANSITION_FADE, function()
		local expectedTrack = if side == "Right" then fallBackRightTrack else fallBackLeftTrack
		if sequenceToken == fallToken
			and fallTrack == expectedTrack
			and isFallLockedState()
		then
			fallTrack.Priority = Enum.AnimationPriority.Action4
		end
	end)

	scheduleBasketRelease(fallToken, fallTrack, side)

	-- TEMPORARY until a dedicated fallen idle exists: stop before the animation can
	-- expose its end/neutral pose and keep the Action4 weight active.
	monitorAndHoldFallFinalPose(fallToken, fallTrack, fallLength, side)
end

local function cancelSlipForFall(now: number)
	SLIP_CHAIN.reset("cancel")
	CHAIN_BACK.disconnectMarkers()
	endSlip(now, "fall")
	if visualState ~= "Idle" then
		sequenceToken += 1
		visualState = "Idle"
		stopTrack(slipStartTrack, 0.03)
		stopTrack(slipStruggleTrack, 0.03)
		stopTrack(slipRecoverTrack, 0.03)
	end
	local activeCharacter = character
	if activeCharacter and activeCharacter.Parent then
		activeCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
		activeCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	end
	fallDecisionMade = false
	SLIP_CHAIN.fallCause = nil
	SLIP_CHAIN.fallDirection = nil
	CINEMATIC_CAMERA.finish()
	resetTurnFeedback(true)
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

local function clearCharacter(restoreBasket: boolean?, cancellationReason: string?)
	SLIP_CHAIN.reset(cancellationReason or "cancel")
	local wasFallTestActive = isFallLockedState()
	if wasFallTestActive then
		IsSlipping = false
		destroySlipMovement()
		originalAutoRotate = nil
		restoreFallTestState(restoreBasket == true)
	else
		endSlip(os.clock(), cancellationReason or "reset")
	end
	destroySlipMovement()
	restoreHumanoidState()
	disconnectCharacterConnections()
	clearSlipAnimations()
	destroyTurnWarningGui()
	SLIP_CHAIN.destroyWarningGui()
	warningRootJoint = nil
	warningWaist = nil
	warningRootBaseC0 = nil
	warningWaistBaseC0 = nil
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
	if entrySpeed >= SLIP_CHAIN.minimumValidEntrySpeed then
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

local function beginSlip(now: number, ignoreCooldown: boolean?): boolean
	local activeHumanoid = humanoid
	local root = humanoidRootPart
	if IsSlipping
		or (visualState ~= "Idle" and visualState ~= "PostSlipSlow")
		or not activeHumanoid
		or not root
		or activeHumanoid.Health <= 0
		or (character and character:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) == true)
		or (character and character:GetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE) == true)
		or (not ignoreCooldown and now - LastSlipTime < SLIP_CHAIN.slipCooldown)
	then
		return false
	end

	local entryDirection, entrySpeed = chooseEntryDirection(activeHumanoid, root)
	slipStartedWhileSprinting = character ~= nil
		and character:GetAttribute(IS_SPRINTING_ATTRIBUTE) == true
	local profile = if slipStartedWhileSprinting
		then SPRINT_SLIP_PROFILE
		else NORMAL_SLIP_PROFILE
	SLIP_CHAIN.totalExtension = 0
	SLIP_CHAIN.recoverNotBefore = 0
	resetTurnFeedback(true)
	fallDecisionMade = false
	capturedSlideDirection = entryDirection
	IsSlipping = true
	if character then
		character:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, true)
	end
	slipStartTime = now
	slipEntrySpeed = entrySpeed
	slideDirection = entryDirection
	activeSlipProfile = profile
	lastControlledSlideSpeed = computeSingleSlipSpeed(0, entrySpeed, profile)
	maxObservedSlipSpeed = entrySpeed
	slipSpeedWarningPrinted = false
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
		slideDirection.X * lastControlledSlideSpeed,
		slideDirection.Z * lastControlledSlideSpeed
	)
	linearVelocity.ForceLimitsEnabled = false
	linearVelocity.Parent = root
	slipLinearVelocity = linearVelocity
	print(string.format(
		"[SlipSpeed] begin mode=%s entry=%.2f",
		profile.mode,
		entrySpeed
	))
	print(string.format(
		"[SlipSpeed] profile duration=%.2f startRatio=%.2f endRatio=%.2f",
		profile.duration,
		profile.initialSpeedRatio,
		profile.endSpeedRatio
	))
	print(
		"[SlipChainDebug] rootSlideOwner=EggSlipController.LinearVelocity "
			.. "walkSpeedOwner=ShiftSprintController.Humanoid.WalkSpeed"
	)
	return true
end

local function currentSlideSpeed(now: number): number
	local profile = activeSlipProfile
	if not profile then
		return 0
	end
	local computedSpeed = computeSingleSlipSpeed(
		math.max(now - slipStartTime - SLIP_CHAIN.totalExtension, 0),
		slipEntrySpeed,
		profile
	)
	-- Floating-point or timing irregularities may never make a later frame
	-- faster than an earlier controlled frame.
	lastControlledSlideSpeed = math.min(
		lastControlledSlideSpeed,
		computedSpeed,
		slipEntrySpeed
	)
	lastControlledSlideSpeed = MODERATE_TURN.speedCap(
		now,
		lastControlledSlideSpeed
	)
	return lastControlledSlideSpeed
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
	local previousZones = touchingSlipZones
	local currentZones: { [BasePart]: boolean } = {}
	local orderedZones: { { zone: BasePart, distance: number } } = {}
	local root = humanoidRootPart

	for _, zone in zones do
		currentZones[zone] = true
		if root then
			table.insert(orderedZones, {
				zone = zone,
				distance = (zone.Position - root.Position).Magnitude,
			})
		end
	end

	touchingSlipZones = currentZones
	table.sort(orderedZones, function(left, right)
		return left.distance < right.distance
	end)
	for _, entry in orderedZones do
		if SLIP_CHAIN.fallCommitted then
			break
		end
		local yolkIdentity = SLIP_CHAIN.resolveYolkIdentity(entry.zone)
		if yolkIdentity then
			SLIP_CHAIN.expireElapsedGrace(now)
			if SLIP_CHAIN.contactedYolks[yolkIdentity] then
				SLIP_CHAIN.register(yolkIdentity, now)
				-- contactedYolks is a chain-count dedupe set, not a movement
				-- immunity list. A real leave-and-reenter edge on an already-counted
				-- puddle must still produce another physical slip, while keeping the
				-- existing count, extension, warning, and threshold unchanged.
				if not IsSlipping and not previousZones[entry.zone] then
					if beginSlip(now, true) then
						beginSlipVisual()
					else
						-- Preserve the entry edge through a brief visual/character lock so
						-- detection can retry as soon as that temporary gate clears.
						touchingSlipZones[entry.zone] = nil
					end
				end
			elseif IsSlipping
				and (visualState == "SlipStart"
					or visualState == "SlipStruggle"
					or visualState == "SlipRecover")
			then
				if SLIP_CHAIN.register(yolkIdentity, now) then
					local chainFallCommitted = SLIP_CHAIN.handleCountChanged(now)
					local extension = if SLIP_CHAIN.fallCommitted
						then 0
						else SLIP_CHAIN.extendActive(now)
					print(string.format(
						"[SlipChain] active distinct count=%d yolk=%s extension=%.2f",
						SLIP_CHAIN.count,
						yolkIdentity:GetFullName(),
						extension
					))
					if visualState == "SlipRecover"
						and (extension > 0 or chainFallCommitted)
					then
						SLIP_CHAIN.interruptRecovery()
					end
				end
			elseif SLIP_CHAIN.count > 0
				and (visualState == "Idle" or visualState == "PostSlipSlow")
			then
				-- A distinct post-recovery contact owns the chain immediately,
				-- invalidating the old grace timeout before starting its new slip.
				if SLIP_CHAIN.register(yolkIdentity, now) then
					if beginSlip(now, true) then
						beginSlipVisual()
						SLIP_CHAIN.handleCountChanged(now)
					end
				end
			elseif not previousZones[entry.zone] then
				if beginSlip(now) then
					if SLIP_CHAIN.register(yolkIdentity, now) then
						SLIP_CHAIN.handleCountChanged(now)
					end
					beginSlipVisual()
				else
					-- Do not consume the physical entry edge when a temporary
					-- non-chain gate prevents the ordinary first slip from starting.
					touchingSlipZones[entry.zone] = nil
				end
			end
		end
	end
end

local function updateSlip(now: number, _deltaTime: number)
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
		endSlip(now, if activeHumanoid and activeHumanoid.Health <= 0 then "death" else "reset")
		return
	end

	local observedSpeed = horizontal(root.AssemblyLinearVelocity).Magnitude
	maxObservedSlipSpeed = math.max(maxObservedSlipSpeed, observedSpeed)
	if not slipSpeedWarningPrinted
		and observedSpeed > slipEntrySpeed + SLIP_CHAIN.speedTolerance
	then
		slipSpeedWarningPrinted = true
		warn(string.format(
			"[SlipSpeed] observed speed exceeded entry entry=%.2f observed=%.2f",
			slipEntrySpeed,
			observedSpeed
		))
	end

	local slideSpeed = currentSlideSpeed(now)
	linearVelocity.PlaneVelocity = Vector2.new(
		slideDirection.X * slideSpeed,
		slideDirection.Z * slideSpeed
	)
end

local function setupCharacter(newCharacter: Model)
	clearCharacter(false, "respawn")
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
	BASKET_RECOVERY.normalWalkSpeed = foundHumanoid.WalkSpeed
	resolveCharacterWarningJoints(newCharacter)
	createTurnWarningGui()
	SLIP_CHAIN.createWarningGui()
	newCharacter:SetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE, 1)
	newCharacter:SetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE, false)
	newCharacter:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, false)
	newCharacter:SetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE, false)
	SLIP_CHAIN.publish()
	local setupToken = sequenceToken
	if not loadSlipAnimations(foundAnimator, setupToken) then
		if sequenceToken == setupToken and character == newCharacter then
			clearCharacter(false, "cancel")
		end
		return
	end
	if sequenceToken ~= setupToken
		or newCharacter ~= player.Character
		or foundHumanoid.Health <= 0
	then
		if sequenceToken == setupToken and character == newCharacter then
			clearCharacter(false, "cancel")
		end
		return
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { newCharacter }
	params.MaxParts = 32
	overlapParams = params

	characterDiedConnection = foundHumanoid.Died:Connect(function()
		clearCharacter(false, "death")
	end)
	characterAncestryConnection = newCharacter.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearCharacter(false, "respawn")
		end
	end)
	rootAncestryConnection = foundRoot.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearCharacter(false, "respawn")
		end
	end)
end

player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(function(removingCharacter)
	if removingCharacter == character then
		clearCharacter(false, "respawn")
	end
end)

script.Destroying:Connect(function()
	clearCharacter(true, "cancel")
	unbindTurnWarningRender()
end)
script:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not script.Enabled then
		clearCharacter(true, "cancel")
		unbindTurnWarningRender()
	else
		bindTurnWarningRender()
	end
end)

bindTurnWarningRender()

RunService.PreSimulation:Connect(function(deltaTime: number)
	if not script.Enabled then
		return
	end
	local now = os.clock()
	if character
		and humanoid
		and visualState == "Idle"
		and character:GetAttribute(IS_SPRINTING_ATTRIBUTE) ~= true
		and humanoid.WalkSpeed > 0
	then
		BASKET_RECOVERY.normalWalkSpeed = humanoid.WalkSpeed
	end
	-- SeekDroppedBasket deliberately releases FallMovementLocked because the
	-- sprint controller interprets that shared attribute as an unconditional
	-- WalkSpeed=0. Manual input is still sunk by BASKET_RECOVERY, while this
	-- branch exclusively supplies the automatic walk direction.
	if visualState == "SeekDroppedBasket" and BASKET_RECOVERY.inputLocked then
		if humanoid and humanoid.AutoRotate then
			humanoid.WalkSpeed = BASKET_RECOVERY.walkSpeed
			local root = humanoidRootPart
			local target = BASKET_RECOVERY.moveTarget
			if root and target then
				local direction = horizontal(target - root.Position)
				humanoid:Move(
					if direction.Magnitude > 0.05 then direction.Unit else Vector3.zero,
					false
				)
			end
		elseif humanoid then
			enforceFallMovementLock()
		end
		table.clear(touchingSlipZones)
		detectionAccumulator = 0
		return
	elseif BASKET_RECOVERY.inputLocked and BASKET_RECOVERY.isStationaryLocked() then
		enforceFallMovementLock()
		table.clear(touchingSlipZones)
		detectionAccumulator = 0
		return
	elseif character and character:GetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE) == true then
		if BASKET_RECOVERY.isStationaryLocked() then
			enforceFallMovementLock()
		else
			cancelSlipForFall(now)
		end
		table.clear(touchingSlipZones)
		detectionAccumulator = 0
		return
	end
	if character and character:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) == true then
		SLIP_CHAIN.reset("cancel")
		endSlip(now, "reset")
		resetTurnFeedback(true)
		table.clear(touchingSlipZones)
		detectionAccumulator = 0
		return
	end
	SLIP_CHAIN.captureLateralInput(now)

	detectionAccumulator += deltaTime
	if detectionAccumulator >= SLIP_CHAIN.detectionInterval then
		detectionAccumulator %= SLIP_CHAIN.detectionInterval
		updateDetection(now)
	end
	updateSlip(now, deltaTime)
end)

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
