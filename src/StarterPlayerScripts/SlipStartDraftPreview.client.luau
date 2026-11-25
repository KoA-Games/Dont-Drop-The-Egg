--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return
end

local PREVIEW_KEY = Enum.KeyCode.Z
local ANIMATION_ID = "rbxassetid://125100082914442"
local HOLD_LEAD = 0.015

local player = Players.LocalPlayer
local currentTrack: AnimationTrack? = nil
local generation = 0

local function cleanTrack()
	generation += 1
	if currentTrack then
		currentTrack:Stop(0.03)
		currentTrack:Destroy()
		currentTrack = nil
	end
end

local function setupCharacter(character: Model)
	cleanTrack()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or character ~= player.Character then
		return
	end
	local animator = humanoid:WaitForChild("Animator", 10)
	if not animator or not animator:IsA("Animator") or character ~= player.Character then
		return
	end

	local animation = Instance.new("Animation")
	animation.Name = "SlipStart"
	animation.AnimationId = ANIMATION_ID
	local track = animator:LoadAnimation(animation)
	animation:Destroy()
	track.Name = "SlipStartZPreview"
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	currentTrack = track
	print("[SlipPreview] Z ready (published SlipStart)")
end

local function playPreview()
	local track = currentTrack
	if not track then
		warn("[SlipPreview] Z track is not ready")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, otherTrack in animator:GetPlayingAnimationTracks() do
			if otherTrack ~= track and (
				otherTrack.Name == "SlipStruggleXPreview"
				or otherTrack.Name == "FallBackLeftPreviewTrack"
			) then
				otherTrack:Stop(0.03)
			end
		end
	end
	generation += 1
	local playGeneration = generation
	track:Stop(0.02)
	track.TimePosition = 0
	track:Play(0.02, 1, 1)
	track:AdjustSpeed(1)

	task.spawn(function()
		local deadline = os.clock() + 5
		while track.Length <= 0 and os.clock() < deadline do
			RunService.Heartbeat:Wait()
		end
		if playGeneration ~= generation or track ~= currentTrack or track.Length <= 0 then
			return
		end
		task.wait(math.max(track.Length - HOLD_LEAD, 0))
		if playGeneration == generation and track == currentTrack and track.IsPlaying then
			track.TimePosition = math.max(track.Length - 0.005, 0)
			track:AdjustSpeed(0)
			print("[SlipPreview] Z final pose held")
		end
	end)
end

player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(function(character)
	if character == player.Character then
		cleanTrack()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.KeyCode == PREVIEW_KEY and not UserInputService:GetFocusedTextBox() then
		playPreview()
	end
end)

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
