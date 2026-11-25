--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return
end

local PREVIEW_KEY = Enum.KeyCode.B
local FALL_FINAL_TIME = 1.155
local FALLEN_POSE_HOLD = 0.14
local FALL_FADE_IN = 0.02
local GET_UP_FADE_IN = 0.06
local TRANSITION_FADE = 0.08
local LOCOMOTION_FADE = 0.16
local GET_UP_DURATION = 1.35
local FALL_MOVEMENT_LOCK_ATTRIBUTE = "FallMovementLocked"
local FALL_BASKET_RELEASE_REMOTE_NAME = "FallBasketReleasePreview"
local FALL_BACK_LEFT_ANIMATION_ID = "rbxassetid://137848365560941"
local GET_UP_LEFT_ANIMATION_ID = "rbxassetid://83463696986246"
local BASKET_IK_NAMES: { [string]: boolean } = {
	BasketRightArmIK = true,
	BasketLeftArmIK = true,
	BasketRightHandRotationIK = true,
	BasketLeftHandRotationIK = true,
}

local player = Players.LocalPlayer
local basketReleaseRemote = ReplicatedStorage:WaitForChild(
	FALL_BASKET_RELEASE_REMOTE_NAME,
	10
)
local currentCharacter: Model? = nil
local fallAnimation: Animation? = nil
local getUpAnimation: Animation? = nil
local fallPoseTrack: AnimationTrack? = nil
local getUpTrack: AnimationTrack? = nil
local setupGeneration = 0
local playGeneration = 0

local function setMovementLocked(character: Model, locked: boolean)
	character:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, locked)
	if locked then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Move(Vector3.zero, false)
		end
	end
end

local function cleanTracks()
	playGeneration += 1
	if fallPoseTrack then
		fallPoseTrack:Stop(0)
		fallPoseTrack:Destroy()
		fallPoseTrack = nil
	end
	if getUpTrack then
		getUpTrack:Stop(0)
		getUpTrack:Destroy()
		getUpTrack = nil
	end
	if fallAnimation then
		fallAnimation:Destroy()
		fallAnimation = nil
	end
	if getUpAnimation then
		getUpAnimation:Destroy()
		getUpAnimation = nil
	end
	if currentCharacter and currentCharacter.Parent then
		setMovementLocked(currentCharacter, false)
	end
	currentCharacter = nil
end

local function setupCharacter(character: Model)
	setupGeneration += 1
	local generation = setupGeneration
	cleanTracks()

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local animator = humanoid:WaitForChild("Animator", 10)
	if not animator or not animator:IsA("Animator") then
		return
	end
	if generation ~= setupGeneration or character ~= player.Character then
		return
	end

	local newFallAnimation = Instance.new("Animation")
	newFallAnimation.Name = "FallBackLeftFinalPose_BPreview"
	newFallAnimation.AnimationId = FALL_BACK_LEFT_ANIMATION_ID
	local newFallTrack = animator:LoadAnimation(newFallAnimation)
	newFallTrack.Name = "FallBackLeftFinalPoseBPreviewTrack"
	newFallTrack.Priority = Enum.AnimationPriority.Action4
	newFallTrack.Looped = false

	local newGetUpAnimation = Instance.new("Animation")
	newGetUpAnimation.Name = "GetUpLeft_Published_BPreview"
	newGetUpAnimation.AnimationId = GET_UP_LEFT_ANIMATION_ID
	local newGetUpTrack = animator:LoadAnimation(newGetUpAnimation)
	newGetUpTrack.Name = "GetUpLeftBPreviewTrack"
	newGetUpTrack.Priority = Enum.AnimationPriority.Action4
	newGetUpTrack.Looped = false

	currentCharacter = character
	fallAnimation = newFallAnimation
	getUpAnimation = newGetUpAnimation
	fallPoseTrack = newFallTrack
	getUpTrack = newGetUpTrack
	print("[GetUpLeftPreview] B preview ready")
end

local function stopConflictingPreviewTracks(humanoid: Humanoid, animator: Animator)
	for _, track in animator:GetPlayingAnimationTracks() do
		local sourceAnimation = track.Animation
		local isBasketHold = track.Name == "BasketHold"
			or (sourceAnimation and sourceAnimation.Name == "BasketHold")
		if track ~= fallPoseTrack and track ~= getUpTrack and (isBasketHold or (
			track.Name == "SlipStartZPreview"
			or track.Name == "SlipStruggleXPreview"
			or track.Name == "SlipStrugglePreviewTrack"
			or track.Name == "FallBackLeftPreviewTrack"
			or track.Name == "FallBackLeftFinalPoseBPreviewTrack"
			or track.Name == "GetUpLeftBPreviewTrack"
		)) then
			-- BasketHold must disappear immediately at release. A crossfade here
			-- would average its raised-arm pose with GetUpLeft's floor-support pose.
			track:Stop(if isBasketHold then 0 else TRANSITION_FADE)
		end
	end

	-- The current basket service normally removes these on the server. Disable
	-- any replicated controls locally as well so the very first preview frame
	-- cannot be pulled back toward the old overhead basket targets.
	for _, child in humanoid:GetChildren() do
		if child:IsA("IKControl") and BASKET_IK_NAMES[child.Name] then
			child.Enabled = false
		end
	end
end

local function playPreview()
	local character = currentCharacter
	local holdTrack = fallPoseTrack
	local riseTrack = getUpTrack
	if not character or not holdTrack or not riseTrack then
		warn("[GetUpLeftPreview] Character tracks are not ready")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then
		warn("[GetUpLeftPreview] Animator is not ready")
		return
	end

	playGeneration += 1
	local generation = playGeneration
	stopConflictingPreviewTracks(humanoid, animator)
	riseTrack:Stop(0)
	holdTrack:Stop(0)
	setMovementLocked(character, true)
	if basketReleaseRemote and basketReleaseRemote:IsA("RemoteEvent") then
		basketReleaseRemote:FireServer()
	end

	-- Establish the exact final FallBackLeft pose first. This avoids blending the
	-- get-up draft directly from an upright idle pose when B is tested by itself.
	holdTrack:Play(FALL_FADE_IN, 1, 1)
	holdTrack.TimePosition = FALL_FINAL_TIME
	holdTrack:AdjustSpeed(0)
	print("[GetUpLeftPreview] B staged the exact FallBackLeft final pose")

	task.delay(FALLEN_POSE_HOLD, function()
		if generation ~= playGeneration
			or character ~= currentCharacter
			or holdTrack ~= fallPoseTrack
			or riseTrack ~= getUpTrack
			or not character.Parent
		then
			return
		end

		riseTrack.TimePosition = 0
		riseTrack:Play(GET_UP_FADE_IN, 1, 1)
		riseTrack:AdjustSpeed(1)
		holdTrack:Stop(TRANSITION_FADE)
		print("[GetUpLeftPreview] GetUpLeft started from the fallen-left pose")

		task.delay(GET_UP_DURATION, function()
			if generation ~= playGeneration
				or character ~= currentCharacter
				or riseTrack ~= getUpTrack
				or not character.Parent
			then
				return
			end
			setMovementLocked(character, false)
			if riseTrack.IsPlaying then
				riseTrack:Stop(LOCOMOTION_FADE)
			end
			print("[GetUpLeftPreview] B preview complete; movement restored")
		end)
	end)
end

player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(function(character)
	if character == currentCharacter then
		setupGeneration += 1
		cleanTracks()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == PREVIEW_KEY then
		playPreview()
	end
end)

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
