--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return
end

local PREVIEW_KEY = Enum.KeyCode.V
local SLIP_STRUGGLE_ANIMATION_ID = "rbxassetid://77524598504382"
local FALL_BACK_LEFT_ANIMATION_ID = "rbxassetid://137848365560941"
local FADE_IN = 0.02
local FADE_OUT = 0.05
local FREEZE_DELAY = 1.12
local FINAL_TIME = 1.155
local BASKET_RELEASE_TIME = 0.25
local MOVEMENT_LOCK_TIME = 0.62
local FALL_MOVEMENT_LOCK_ATTRIBUTE = "FallMovementLocked"
local FALL_BASKET_RELEASE_REMOTE_NAME = "FallBasketReleasePreview"

local player = Players.LocalPlayer

local currentCharacter: Model? = nil
local currentAnimation: Animation? = nil
local currentTrack: AnimationTrack? = nil
local pausedBasketTracks: { AnimationTrack } = {}
local setupGeneration = 0
local playGeneration = 0
local basketReleaseRemote = ReplicatedStorage:WaitForChild(
	FALL_BASKET_RELEASE_REMOTE_NAME,
	10
)

local function restoreBasketTracks()
	for _, basketTrack in pausedBasketTracks do
		pcall(function()
			basketTrack:Play(0.05, 1, 1)
		end)
	end
	table.clear(pausedBasketTracks)
end

local function cleanTrack()
	playGeneration += 1
	if currentTrack then
		if currentTrack.IsPlaying then
			currentTrack:Stop(FADE_OUT)
		end
		currentTrack:Destroy()
		currentTrack = nil
	end
	if currentAnimation then
		currentAnimation:Destroy()
		currentAnimation = nil
	end
	currentCharacter = nil
	restoreBasketTracks()
end

local function setupCharacter(character: Model)
	setupGeneration += 1
	local generation = setupGeneration
	cleanTrack()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator") :: Animator
	if generation ~= setupGeneration or character.Parent == nil then
		return
	end

	local animation = Instance.new("Animation")
	animation.Name = "FallBackLeft_Published_VPreview"
	animation.AnimationId = FALL_BACK_LEFT_ANIMATION_ID

	local track = animator:LoadAnimation(animation)
	track.Name = "FallBackLeftPreviewTrack"
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false

	currentCharacter = character
	currentAnimation = animation
	currentTrack = track
	print("[FallBackLeftPreview] V preview ready")
end

local function pauseBasketHold(animator: Animator)
	restoreBasketTracks()
	for _, track in animator:GetPlayingAnimationTracks() do
		local sourceAnimation = track.Animation
		if track.Name == "BasketHold" or (sourceAnimation and sourceAnimation.Name == "BasketHold") then
			table.insert(pausedBasketTracks, track)
			track:Stop(FADE_OUT)
		end
	end
end

local function isSlipStruggleTrack(track: AnimationTrack): boolean
	if track.Name == "SlipStruggleXPreview" or track.Name == "SlipStrugglePreviewTrack" then
		return true
	end
	local sourceAnimation = track.Animation
	return sourceAnimation ~= nil and sourceAnimation.AnimationId == SLIP_STRUGGLE_ANIMATION_ID
end

local function partBottomY(part: BasePart): number
	local halfHeight = math.abs(part.CFrame.RightVector.Y) * part.Size.X * 0.5
		+ math.abs(part.CFrame.UpVector.Y) * part.Size.Y * 0.5
		+ math.abs(part.CFrame.LookVector.Y) * part.Size.Z * 0.5
	return part.Position.Y - halfHeight
end

local function logFinalGroundContact(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), params)
	if not hit then
		warn("[FallBackLeftPreview] No ground found below final pose")
		return
	end
	local readings = {}
	for _, partName in {
		"LeftFoot",
		"RightFoot",
		"LeftUpperLeg",
		"LowerTorso",
		"UpperTorso",
	} do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			table.insert(readings, string.format("%s=%.3f", partName, partBottomY(part) - hit.Position.Y))
		end
	end
	print(string.format("[FallBackLeftPreview] Ground contact offsets (studs): %s", table.concat(readings, ", ")))
end

local function playPreview()
	local track = currentTrack
	local character = currentCharacter
	if not track or not character then
		warn("[FallBackLeftPreview] Character track is not ready")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn("[FallBackLeftPreview] Animator is not ready")
		return
	end

	pauseBasketHold(animator)
	for _, otherTrack in animator:GetPlayingAnimationTracks() do
		if otherTrack.Name == "SlipStartZPreview"
			or isSlipStruggleTrack(otherTrack)
		then
			otherTrack:Stop(FADE_OUT)
		end
	end
	playGeneration += 1
	local generation = playGeneration
	if track.IsPlaying then
		track:Stop(FADE_OUT)
	end
	track.TimePosition = 0
	track:Play(FADE_IN, 1, 1)
	track:AdjustSpeed(1)
	print("[FallBackLeftPreview] V preview played")

	task.delay(BASKET_RELEASE_TIME, function()
		if generation ~= playGeneration or track ~= currentTrack or not character.Parent then
			return
		end
		if basketReleaseRemote and basketReleaseRemote:IsA("RemoteEvent") then
			basketReleaseRemote:FireServer()
			print("[FallBackLeftPreview] Basket release requested at 0.25")
		else
			warn("[FallBackLeftPreview] Basket release remote is unavailable")
		end
	end)

	task.delay(MOVEMENT_LOCK_TIME, function()
		if generation ~= playGeneration or track ~= currentTrack or not character.Parent then
			return
		end
		character:SetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE, true)
		local activeHumanoid = character:FindFirstChildOfClass("Humanoid")
		if activeHumanoid then
			activeHumanoid:Move(Vector3.zero, false)
		end
		print("[FallBackLeftPreview] Fallen movement locked at first ground impact")
	end)

	task.delay(FREEZE_DELAY, function()
		if generation ~= playGeneration or track ~= currentTrack or not track.IsPlaying then
			return
		end
		track.TimePosition = math.min(FINAL_TIME, math.max(track.Length - 0.005, 0))
		track:AdjustSpeed(0)
		print(string.format("[FallBackLeftPreview] Final pose held at %.3f", track.TimePosition))
		task.defer(function()
			RunService.RenderStepped:Wait()
			RunService.RenderStepped:Wait()
			if generation == playGeneration and character == currentCharacter then
				logFinalGroundContact(character)
			end
		end)
	end)
end

player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(function(character)
	if character == currentCharacter then
		setupGeneration += 1
		cleanTrack()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if input.KeyCode ~= PREVIEW_KEY then
		return
	end
	playPreview()
end)

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
