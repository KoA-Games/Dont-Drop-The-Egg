--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local FALL_MOVEMENT_LOCK_ATTRIBUTE = "FallMovementLocked"
local POST_SLIP_SPEED_MULTIPLIER_ATTRIBUTE = "PostSlipSpeedMultiplier"
local EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE = "EggSlipMovementActive"
local IS_SPRINTING_ATTRIBUTE = "IsSprinting"

local character: Model? = nil
local humanoid: Humanoid? = nil
local isShiftHeld = false
local applyingSpeed = false
local lastObservedPostSlipMultiplier = 1
local autoRotateBeforeFallLock: boolean? = nil
local characterConnections: { RBXScriptConnection } = {}

local function disconnectCharacterConnections()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function isMovementLocked(): boolean
	return character ~= nil
		and (character:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) == true
			or character:GetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE) == true)
end

local function isFallMovementLocked(): boolean
	return character ~= nil
		and character:GetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE) == true
end

local function isSlipMovementActive(): boolean
	return character ~= nil
		and character:GetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE) == true
end

local function publishSprintState()
	local activeCharacter = character
	if not activeCharacter or not activeCharacter.Parent then
		return
	end

	-- This is the movement mode owned by this controller, not a raw Shift-key
	-- query from EggSlipController. Locks and controlled slip movement suppress
	-- the published sprint mode immediately.
	activeCharacter:SetAttribute(
		IS_SPRINTING_ATTRIBUTE,
		isShiftHeld and not isMovementLocked() and not isSlipMovementActive()
	)
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
	publishSprintState()
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

local function applyFallMovementLock()
	local activeHumanoid = humanoid
	local activeCharacter = character
	if not activeHumanoid or not activeCharacter or not activeHumanoid.Parent then
		return
	end

	if activeCharacter:GetAttribute(FALL_MOVEMENT_LOCK_ATTRIBUTE) == true then
		if autoRotateBeforeFallLock == nil then
			-- EggSlipController temporarily disables AutoRotate while sliding. If the
			-- fall branches out of that state, remember the normal post-slip value
			-- instead of preserving the transient false value for the future get-up.
			autoRotateBeforeFallLock = if isSlipMovementActive()
				then true
				else activeHumanoid.AutoRotate
		end
		applyingSpeed = true
		activeHumanoid.WalkSpeed = 0
		applyingSpeed = false
		activeHumanoid.AutoRotate = false
		activeHumanoid:Move(Vector3.zero, false)
	else
		if autoRotateBeforeFallLock ~= nil then
			activeHumanoid.AutoRotate = autoRotateBeforeFallLock
			autoRotateBeforeFallLock = nil
		end
		applyMovementSpeed()
	end
	publishSprintState()
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
	if character and character.Parent then
		character:SetAttribute(IS_SPRINTING_ATTRIBUTE, false)
	end
	disconnectCharacterConnections()
	character = nil
	humanoid = nil
	applyingSpeed = false
	lastObservedPostSlipMultiplier = 1
	autoRotateBeforeFallLock = nil
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
	newCharacter:SetAttribute(IS_SPRINTING_ATTRIBUTE, false)
	lastObservedPostSlipMultiplier = postSlipSpeedMultiplier()
	refreshShiftState()
	applyFallMovementLock()

	table.insert(characterConnections, newCharacter:GetAttributeChangedSignal(
		EGG_SPAWN_LOCK_ATTRIBUTE
	):Connect(function()
		publishSprintState()
		if newCharacter:GetAttribute(EGG_SPAWN_LOCK_ATTRIBUTE) ~= true then
			-- EggBasketSpawnService restores its saved speed immediately after
			-- clearing the lock. Apply again on the next task turn so the current
			-- Shift state wins regardless of replication order.
			task.defer(applyMovementSpeed)
		end
	end))

	table.insert(characterConnections, newCharacter:GetAttributeChangedSignal(
		FALL_MOVEMENT_LOCK_ATTRIBUTE
	):Connect(function()
		task.defer(function()
			if character == newCharacter then
				applyFallMovementLock()
			end
		end)
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
		publishSprintState()
		if newCharacter:GetAttribute(EGG_SLIP_MOVEMENT_ACTIVE_ATTRIBUTE) ~= true then
			task.defer(applyMovementSpeed)
		end
	end))

	table.insert(characterConnections, foundHumanoid:GetPropertyChangedSignal(
		"WalkSpeed"
	):Connect(function()
		if applyingSpeed then
			return
		end
		if isFallMovementLocked() then
			task.defer(applyFallMovementLock)
		elseif not isMovementLocked() then
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

	local modeChanged = not isShiftHeld
	isShiftHeld = true
	publishSprintState()
	applyMovementSpeed(modeChanged and postSlipSpeedMultiplier() < 1)
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
	publishSprintState()
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

RunService.PreSimulation:Connect(function()
	if not isFallMovementLocked() then
		return
	end
	local activeHumanoid = humanoid
	local activeCharacter = character
	if not activeHumanoid or not activeCharacter then
		return
	end
	activeHumanoid:Move(Vector3.zero, false)
	activeHumanoid.AutoRotate = false
	if activeHumanoid.WalkSpeed ~= 0 then
		applyingSpeed = true
		activeHumanoid.WalkSpeed = 0
		applyingSpeed = false
	end
	local root = activeCharacter:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		root.AssemblyAngularVelocity = Vector3.zero
	end
end)
