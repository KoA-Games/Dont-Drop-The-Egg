--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Normal movement is 60% of the original Roblox speed. Holding either Shift
-- key restores the original speed. Roblox's default Animate script drives its
-- walk/run playback rate from actual Humanoid movement speed, so walking at
-- 9.6 also plays the locomotion animation at the matching slower rate.
local ORIGINAL_RUN_SPEED = 16
local WALK_SPEED_MULTIPLIER = 0.60
local WALK_SPEED = ORIGINAL_RUN_SPEED * WALK_SPEED_MULTIPLIER
local EGG_SPAWN_LOCK_ATTRIBUTE = "EggSpawnMovementLocked"
local POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE = "PostSlipSpeedMultiplier"
local EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE = "EggSlipMovementActive"

local character: Model? = nil
local humanoid: Humanoid? = nil
local isShiftHeld = false
local applyingSpeed = false
local lastObservedPostSlipMultiplier = 1
local characterConnections: { RBXScriptConnection } = {}

local function disconnectCharacterConnections()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function isMovementLocked(): boolean
	return character ~= nil
		and character:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) == true
end

local function isSlipMovementActive(): boolean
	return character ~= nil
		and character:GetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE) == true
end

local function postSlipSpeedMultiplier(): number
	local activeCharacter = character
	if not activeCharacter then
		return 1
	end

	local value = activeCharacter:GetAttribute(POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE)
	if typeof(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(value, 0, 1)
end

local function desiredSpeed(): number
	return if isShiftHeld then ORIGINAL_RUN_SPEED else WALK_SPEED
end

local function movementMode(): string
	return if isShiftHeld then "sprint" else "normal"
end

local function applyMovementSpeed(logSnapshot: boolean?)
	local activeHumanoid = humanoid
	if not activeHumanoid
		or not activeHumanoid.Parent
		or activeHumanoid.Health <= 0
		or isMovementLocked()
		or isSlipMovementActive()
	then
		return
	end

	local baseSpeed = desiredSpeed()
	local multiplier = postSlipSpeedMultiplier()
	local targetSpeed = baseSpeed * multiplier
	if math.abs(activeHumanoid.WalkSpeed - targetSpeed) > 0.001 then
		applyingSpeed = true
		activeHumanoid.WalkSpeed = targetSpeed
		applyingSpeed = false
	end

	if logSnapshot then
		print(string.format(
			"[EggSlipSpeed] mode=%s base=%.2f multiplier=%.2f final=%.2f",
			movementMode(),
			baseSpeed,
			multiplier,
			targetSpeed
		))
	end
end

local function refreshShiftState()
	local wasShiftHeld = isShiftHeld
	isShiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	local modeChangedDuringPenalty = wasShiftHeld ~= isShiftHeld
		and postSlipSpeedMultiplier() < 1
	applyMovementSpeed(modeChangedDuringPenalty)
end

local function clearCharacter()
	disconnectCharacterConnections()
	character = nil
	humanoid = nil
	applyingSpeed = false
	lastObservedPostSlipMultiplier = 1
end

local function setupCharacter(newCharacter: Model)
	clearCharacter()

	local foundHumanoid = newCharacter:WaitForChild("Humanoid", 10)
	if not foundHumanoid
		or not foundHumanoid:IsA("Humanoid")
		or newCharacter ~= player.Character
	then
		return
	end

	character = newCharacter
	humanoid = foundHumanoid
	lastObservedPostSlipMultiplier = postSlipSpeedMultiplier()
	refreshShiftState()

	table.insert(characterConnections, newCharacter:GetAttributeChangedSignal(
		EGG_SPAWN_LOCK_ATTRIBUTE
	):Connect(function()
		if newCharacter:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) ~= true then
			-- EggBasketSpawnService restores its saved speed immediately after
			-- clearing the lock. Apply again on the next task turn so the current
			-- Shift state wins regardless of replication order.
			task.defer(applyMovementSpeed)
		end
	end))

	table.insert(characterConnections, newCharacter:GetAttributeChangedSignal(
		POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE
	):Connect(function()
		local previousMultiplier = lastObservedPostSlipMultiplier
		local currentMultiplier = postSlipSpeedMultiplier()
		lastObservedPostSlipMultiplier = currentMultiplier
		local penaltyStarted = previousMultiplier >= 1 and currentMultiplier < 1
		local penaltyEnded = previousMultiplier < 1 and currentMultiplier >= 1
		task.defer(function()
			if character == newCharacter then
				applyMovementSpeed(penaltyStarted or penaltyEnded)
			end
		end)
	end))

	table.insert(characterConnections, newCharacter:GetAttributeChangedSignal(
		EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE
	):Connect(function()
		if newCharacter:GetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE) ~= true then
			task.defer(applyMovementSpeed)
		end
	end))

	table.insert(characterConnections, foundHumanoid:GetPropertyChangedSignal(
		"WalkSpeed"
	):Connect(function()
		if not applyingSpeed and not isMovementLocked() then
			task.defer(applyMovementSpeed)
		end
	end))

	table.insert(characterConnections, foundHumanoid.Died:Connect(clearCharacter))
	table.insert(characterConnections, newCharacter.AncestryChanged:Connect(function(_, parent)
		if parent == nil and character == newCharacter then
			clearCharacter()
		end
	end))
end

UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.KeyCode ~= Enum.KeyCode.LeftShift
		and input.KeyCode ~= Enum.KeyCode.RightShift
	then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end

	isShiftHeld = true
	applyMovementSpeed(postSlipSpeedMultiplier() < 1)
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode ~= Enum.KeyCode.LeftShift
		and input.KeyCode ~= Enum.KeyCode.RightShift
	then
		return
	end

	refreshShiftState()
end)

UserInputService.WindowFocusReleased:Connect(function()
	local modeChangedDuringPenalty = isShiftHeld and postSlipSpeedMultiplier() < 1
	isShiftHeld = false
	applyMovementSpeed(modeChangedDuringPenalty)
end)

player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(function(removingCharacter)
	if removingCharacter == character then
		clearCharacter()
	end
end)

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
