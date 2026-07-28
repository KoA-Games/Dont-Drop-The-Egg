--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- Keep the completed prototype controller available for later experiments,
-- but the current game design intentionally does not allow carrying jumps.
local JUMP_ENABLED = false

-- Variable-height jump tuning. Upward speed always decreases during ascent:
-- the hold assistance stays below Workspace gravity and ramps in smoothly.
local INITIAL_JUMP_SPEED = 18
local HOLD_UPWARD_ACCELERATION = 170
local HOLD_BOOST_RAMP_TIME = 0.08
local MAX_HOLD_TIME = 0.38
local EARLY_RELEASE_MULTIPLIER = 0.55
local EGG_TAKEOFF_INHERITANCE = 0.98
local EGG_RELEASE_INHERITANCE = 0.92
local GROUND_REENTRY_DELAY = 0.08
local IDLE_AIR_HORIZONTAL_DAMPING = 16

-- Prototype carried-egg bounds in Basket.Bottom local space.
local CARRIED_EGG_MAX_LOCAL_X = 1.10
local CARRIED_EGG_MAX_LOCAL_Z = 0.80
local CARRIED_EGG_MIN_LOCAL_Y = -0.40
local CARRIED_EGG_MAX_LOCAL_Y = 1.35

local ACTION_NAME = "KoAVariableJump"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 1000
local BASKET_NAME = "Basket"
local MOUNT_READY_ATTRIBUTE = "BasketMountReady"
local FORCE_ATTACHMENT_NAME = "VariableJumpAttachment"
local HOLD_FORCE_NAME = "VariableJumpHoldForce"

type CharacterState = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	attachment: Attachment,
	holdForce: VectorForce,
	connections: { RBXScriptConnection },
	jumpActive: boolean,
	isHoldingJump: boolean,
	leftGround: boolean,
	releaseApplied: boolean,
	pressTime: number,
	lastLandingTime: number,
	idleTakeoff: boolean,
}

local state: CharacterState? = nil

local MOVEMENT_KEYS: { Enum.KeyCode } = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
}

local function hasKeyboardMovementInput(): boolean
	for _, keyCode in MOVEMENT_KEYS do
		if UserInputService:IsKeyDown(keyCode) then
			return true
		end
	end
	return false
end

local function zeroHoldForce(current: CharacterState)
	current.holdForce.Force = Vector3.zero
	current.holdForce.Enabled = false
end

local function isGrounded(current: CharacterState): boolean
	if current.humanoid.Health <= 0 then
		return false
	end

	local humanoidState = current.humanoid:GetState()
	return current.humanoid.FloorMaterial ~= Enum.Material.Air
		and humanoidState ~= Enum.HumanoidStateType.Jumping
		and humanoidState ~= Enum.HumanoidStateType.Freefall
		and humanoidState ~= Enum.HumanoidStateType.FallingDown
		and humanoidState ~= Enum.HumanoidStateType.Dead
end

local function getBasketBottom(current: CharacterState): BasePart?
	local basket = current.character:FindFirstChild(BASKET_NAME)
	if not basket or not basket:IsA("Model")
		or basket:GetAttribute(MOUNT_READY_ATTRIBUTE) ~= true
	then
		return nil
	end

	local bottom = basket:FindFirstChild("Bottom")
	if bottom and bottom:IsA("BasePart") then
		return bottom
	end
	return nil
end

local function applyVerticalDeltaToBasket(current: CharacterState, deltaY: number)
	local bottom = getBasketBottom(current)
	if not bottom or math.abs(deltaY) <= 0.0001 then
		return
	end

	local velocity = bottom.AssemblyLinearVelocity
	bottom.AssemblyLinearVelocity = Vector3.new(
		velocity.X,
		velocity.Y + deltaY,
		velocity.Z
	)
end

local function isInsideCarriedBounds(bottom: BasePart, collider: BasePart): boolean
	local localPosition = bottom.CFrame:PointToObjectSpace(collider.Position)
	return math.abs(localPosition.X) <= CARRIED_EGG_MAX_LOCAL_X
		and math.abs(localPosition.Z) <= CARRIED_EGG_MAX_LOCAL_Z
		and localPosition.Y >= CARRIED_EGG_MIN_LOCAL_Y
		and localPosition.Y <= CARRIED_EGG_MAX_LOCAL_Y
end

local function applyVerticalDeltaToCarriedEggs(current: CharacterState, deltaY: number)
	if math.abs(deltaY) <= 0.0001 then
		return
	end

	local bottom = getBasketBottom(current)
	if not bottom then
		return
	end

	for _, instance in Workspace:GetChildren() do
		if instance:IsA("Model")
			and instance:GetAttribute("IsBasketEgg") == true
			and instance:GetAttribute("OwnerUserId") == player.UserId
		then
			local collider = instance:FindFirstChild("Collider")
			if collider and collider:IsA("BasePart") and isInsideCarriedBounds(bottom, collider) then
				local velocity = collider.AssemblyLinearVelocity
				collider.AssemblyLinearVelocity = Vector3.new(
					velocity.X,
					velocity.Y + deltaY,
					velocity.Z
				)
			end
		end
	end
end

local function disconnectCharacterState()
	local current = state
	state = nil
	if not current then
		return
	end

	zeroHoldForce(current)
	if current.holdForce.Parent then
		current.holdForce:Destroy()
	end
	if current.attachment.Parent then
		current.attachment:Destroy()
	end
	for _, connection in current.connections do
		connection:Disconnect()
	end
end

local function beginJump(current: CharacterState)
	if not JUMP_ENABLED
		or current.jumpActive
		or not isGrounded(current)
		or os.clock() - current.lastLandingTime < GROUND_REENTRY_DELAY
	then
		return
	end

	current.jumpActive = true
	current.isHoldingJump = true
	current.leftGround = false
	current.releaseApplied = false
	current.pressTime = os.clock()
	current.idleTakeoff = not hasKeyboardMovementInput()

	-- Change state first, then seed the physical basket with the same takeoff
	-- delta so its hand follower never catches up explosively. Nearby owned eggs
	-- inherit only the configured fraction, leaving natural relative reaction.
	current.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	local rootVelocity = current.root.AssemblyLinearVelocity
	local jumpDeltaY = INITIAL_JUMP_SPEED - rootVelocity.Y
	current.root.AssemblyLinearVelocity = Vector3.new(
		if current.idleTakeoff then 0 else rootVelocity.X,
		INITIAL_JUMP_SPEED,
		if current.idleTakeoff then 0 else rootVelocity.Z
	)
	applyVerticalDeltaToBasket(current, jumpDeltaY)
	applyVerticalDeltaToCarriedEggs(
		current,
		jumpDeltaY * EGG_TAKEOFF_INHERITANCE
	)
end

local function applyEarlyRelease(current: CharacterState)
	if not current.jumpActive or current.releaseApplied then
		return
	end

	current.releaseApplied = true
	current.isHoldingJump = false
	zeroHoldForce(current)
	local rootVelocity = current.root.AssemblyLinearVelocity
	if rootVelocity.Y <= 0 then
		return
	end

	local newRootY = rootVelocity.Y * EARLY_RELEASE_MULTIPLIER
	local releaseDeltaY = newRootY - rootVelocity.Y
	current.root.AssemblyLinearVelocity = Vector3.new(
		rootVelocity.X,
		newRootY,
		rootVelocity.Z
	)
	applyVerticalDeltaToBasket(current, releaseDeltaY)
	-- Share most of the basket's one-time release slowdown with eggs that are
	-- still inside. The remaining 8% restores a visible inertial rise while the
	-- low collision rim prevents ordinary jumps from shedding most of the load.
	applyVerticalDeltaToCarriedEggs(
		current,
		releaseDeltaY * EGG_RELEASE_INHERITANCE
	)
end

local function handleJumpAction(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	local current = state
	if current then
		if inputState == Enum.UserInputState.Begin then
			beginJump(current)
		elseif inputState == Enum.UserInputState.End
			or inputState == Enum.UserInputState.Cancel
		then
			applyEarlyRelease(current)
		end
	end

	-- Consume every state so PlayerModule cannot add a second default jump.
	return Enum.ContextActionResult.Sink
end

local function attachCharacter(character: Model)
	disconnectCharacterState()

	local humanoidInstance = character:WaitForChild("Humanoid", 15)
	local rootInstance = character:WaitForChild("HumanoidRootPart", 15)
	if not humanoidInstance or not humanoidInstance:IsA("Humanoid") then
		warn("[VariableJump] Humanoid was not available")
		return
	end
	if not rootInstance or not rootInstance:IsA("BasePart") then
		warn("[VariableJump] HumanoidRootPart was not available")
		return
	end

	-- Remove objects left by the old continuous-force implementation.
	local oldForce = rootInstance:FindFirstChild(HOLD_FORCE_NAME)
	if oldForce then
		oldForce:Destroy()
	end
	local oldAttachment = rootInstance:FindFirstChild(FORCE_ATTACHMENT_NAME)
	if oldAttachment then
		oldAttachment:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = FORCE_ATTACHMENT_NAME
	attachment.Position = Vector3.zero
	attachment.Parent = rootInstance

	local holdForce = Instance.new("VectorForce")
	holdForce.Name = HOLD_FORCE_NAME
	holdForce.Attachment0 = attachment
	holdForce.RelativeTo = Enum.ActuatorRelativeTo.World
	holdForce.ApplyAtCenterOfMass = true
	holdForce.Force = Vector3.zero
	holdForce.Enabled = false
	holdForce.Parent = rootInstance

	humanoidInstance.UseJumpPower = true
	humanoidInstance.JumpPower = 0
	humanoidInstance.AutoJumpEnabled = false
	humanoidInstance.Jump = false

	local current: CharacterState = {
		character = character,
		humanoid = humanoidInstance,
		root = rootInstance,
		attachment = attachment,
		holdForce = holdForce,
		connections = {},
		jumpActive = false,
		isHoldingJump = false,
		leftGround = false,
		releaseApplied = false,
		pressTime = 0,
		lastLandingTime = -math.huge,
		idleTakeoff = false,
	}
	state = current

	table.insert(current.connections, humanoidInstance.StateChanged:Connect(function(
		_previousState: Enum.HumanoidStateType,
		newState: Enum.HumanoidStateType
	)
		if state ~= current or not current.jumpActive then
			return
		end

		if newState == Enum.HumanoidStateType.Jumping
			or newState == Enum.HumanoidStateType.Freefall
		then
			current.leftGround = true
		elseif current.leftGround
			and (newState == Enum.HumanoidStateType.Landed
				or newState == Enum.HumanoidStateType.Running
				or newState == Enum.HumanoidStateType.RunningNoPhysics)
		then
			zeroHoldForce(current)
			current.jumpActive = false
			current.isHoldingJump = false
			current.leftGround = false
			current.releaseApplied = false
			current.lastLandingTime = os.clock()
			current.idleTakeoff = false
		end
	end))

	table.insert(current.connections, humanoidInstance.Died:Connect(function()
		if state == current then
			zeroHoldForce(current)
			current.jumpActive = false
			current.isHoldingJump = false
			current.leftGround = false
			current.releaseApplied = false
			current.idleTakeoff = false
		end
	end))

	table.insert(current.connections, character.Destroying:Connect(function()
		if state == current then
			disconnectCharacterState()
		end
	end))

	print(
		"[VariableJump] Ready",
		"jumpEnabled=" .. tostring(JUMP_ENABLED),
		"initialSpeed=" .. tostring(INITIAL_JUMP_SPEED),
		"holdAcceleration=" .. tostring(HOLD_UPWARD_ACCELERATION),
		"maxHoldTime=" .. tostring(MAX_HOLD_TIME),
		"earlyReleaseMultiplier=" .. tostring(EARLY_RELEASE_MULTIPLIER),
		"eggTakeoffInheritance=" .. tostring(EGG_TAKEOFF_INHERITANCE),
		"eggReleaseInheritance=" .. tostring(EGG_RELEASE_INHERITANCE)
	)
end

ContextActionService:UnbindAction(ACTION_NAME)
ContextActionService:BindActionAtPriority(
	ACTION_NAME,
	handleJumpAction,
	false,
	ACTION_PRIORITY,
	Enum.KeyCode.Space
)

player.CharacterAdded:Connect(attachCharacter)
player.CharacterRemoving:Connect(function(character: Model)
	if state and state.character == character then
		disconnectCharacterState()
	end
end)

if player.Character then
	task.spawn(attachCharacter, player.Character)
end

RunService.PreSimulation:Connect(function(deltaTime: number)
	local current = state
	if not current
		or not current.character.Parent
		or current.humanoid.Health <= 0
	then
		if current then
			zeroHoldForce(current)
		end
		return
	end

	-- Roblox can leave a tiny X/Z assembly velocity on an otherwise stationary
	-- takeoff. A long hold makes that residual look like an unexplained sideways
	-- launch. Stabilize only jumps that began with no movement input; the moment
	-- WASD is used, normal horizontal movement is left completely untouched.
	if current.jumpActive and current.idleTakeoff then
		if hasKeyboardMovementInput() then
			current.idleTakeoff = false
		else
			local velocity = current.root.AssemblyLinearVelocity
			local dampingAlpha = 1 - math.exp(-IDLE_AIR_HORIZONTAL_DAMPING * deltaTime)
			current.root.AssemblyLinearVelocity = Vector3.new(
				velocity.X * (1 - dampingAlpha),
				velocity.Y,
				velocity.Z * (1 - dampingAlpha)
			)
		end
	end

	if not current.jumpActive or not current.isHoldingJump then
		zeroHoldForce(current)
		return
	end

	local elapsed = os.clock() - current.pressTime
	if elapsed >= MAX_HOLD_TIME or current.root.AssemblyLinearVelocity.Y <= 0 then
		current.isHoldingJump = false
		current.releaseApplied = true
		zeroHoldForce(current)
		return
	end

	local alpha = math.clamp(elapsed / HOLD_BOOST_RAMP_TIME, 0, 1)
	local smoothRamp = alpha * alpha * (3 - 2 * alpha)
	current.holdForce.Force = Vector3.new(
		0,
		current.root.AssemblyMass * HOLD_UPWARD_ACCELERATION * smoothRamp,
		0
	)
	current.holdForce.Enabled = true
end)
