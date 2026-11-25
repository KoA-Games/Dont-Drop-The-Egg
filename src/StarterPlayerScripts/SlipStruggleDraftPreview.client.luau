--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return
end

local PREVIEW_KEY = Enum.KeyCode.X
local ANIMATION_ID = "rbxassetid://77524598504382"
local WALK_BLEND_TIME = 0.18

local player = Players.LocalPlayer
local currentTrack: AnimationTrack? = nil
local generation = 0

local function isSlipStruggleTrack(track: AnimationTrack): boolean
	if track.Name == "SlipStruggleXPreview" or track.Name == "SlipStrugglePreviewTrack" then
		return true
	end
	local sourceAnimation = track.Animation
	return sourceAnimation ~= nil and sourceAnimation.AnimationId == ANIMATION_ID
end

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
	animation.Name = "SlipStruggle"
	animation.AnimationId = ANIMATION_ID
	local track = animator:LoadAnimation(animation)
	animation:Destroy()
	track.Name = "SlipStruggleXPreview"
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	currentTrack = track
	print("[SlipPreview] X ready (published SlipStruggle)")
end

local function playPreview()
	local track = currentTrack
	if not track then
		warn("[SlipPreview] X track is not ready")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, otherTrack in animator:GetPlayingAnimationTracks() do
			if otherTrack ~= track and (
				otherTrack.Name == "SlipStartZPreview"
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
		-- Begin releasing Action4 shortly before the published clip ends. The
		-- character's normal Animate tracks keep running underneath, so fading the
		-- struggle track reveals the appropriate walk/run/idle pose without a snap.
		task.wait(math.max(track.Length - WALK_BLEND_TIME, 0))
		if playGeneration == generation and track == currentTrack and track.IsPlaying then
			-- The restored place contains an older X preview that can load the same
			-- published clip and freeze its own track. Release every copy of this
			-- animation so no stale Action4 layer can keep the character posed.
			local activeCharacter = player.Character
			local activeHumanoid = activeCharacter and activeCharacter:FindFirstChildOfClass("Humanoid")
			local activeAnimator = activeHumanoid and activeHumanoid:FindFirstChildOfClass("Animator")
			if activeAnimator then
				for _, activeTrack in activeAnimator:GetPlayingAnimationTracks() do
					if isSlipStruggleTrack(activeTrack) then
						activeTrack:Stop(WALK_BLEND_TIME)
					end
				end
			else
				track:Stop(WALK_BLEND_TIME)
			end
			print(string.format(
				"[SlipPreview] X blending back to locomotion over %.2fs",
				WALK_BLEND_TIME
			))
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
