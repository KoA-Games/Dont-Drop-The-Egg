--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- Keyboard-only five-egg tuning for this milestone.
local INITIAL_JUMP_SPEED = 24
local HOLD_UPWARD_ACCELERATION = 110
local MAX_HOLD_TIME = 0.35
local EARLY_RELEASE_MULTIPLIER = 0.55

local ACTION_NAME = "KoAVariableJump"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 1000
local FORCE_ATTACHMENT_NAME = "VariableJumpAttachment"
local HOLD_FORCE_NAME = "VariableJumpHoldForce"
local BASKET_NAME = "Basket"
local BASKET_TARGET_NAME = "BasketTarget"
local BASKET_ATTACHMENT_NAME = "BasketAttachment"

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
	pressTime: number,
	holdDuration: number,
	startHeight: number,
	maximumHeight: number,
	maximumBasketLag: number,
}

local state: CharacterState? = nil
local defaultJumpConsumed = false

local function zeroHoldForce(current: CharacterState)
	current.holdForce.Force = Vector3.zero
	current.holdForce.Enabled = false
end

local function getBasketLag(current: CharacterState): number?
	local basket = current.character:FindFirstChild(BASKET_NAME)
	if not basket or not basket:IsA("Model") then
		return nil
	end
	local bottom = basket:FindFirstChild("Bottom")
	local basketTarget = current.root:FindFirstChild(BASKET_TARGET_NAME)
	if not bottom or not bottom:IsA("BasePart") then
		return nil
	end
	local basketAttachment = bottom:FindFirstChild(BASKET_ATTACHMENT_NAME)
	if not basketAttachment or not basketAttachment:IsA("Attachment") then
		return nil
	end
	if not basketTarget or not basketTarget:IsA("Attachment") then
		return nil
	end

	return (basketAttachment.WorldPosition - basketTarget.WorldPosition).Magnitude
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

local function disconnectCharacterState()
	local current = state
	state = nil
	if not current then
		return
	end

	if current.holdForce.Parent then
		zeroHoldForce(current)
		current.holdForce:Destroy()
	end
	if current.attachment.Parent then
		current.attachment:Destroy()
	end
	for _, connection in current.connections do
		connection:Disconnect()
	end
end

local function classifyJump(holdDuration: number): string
	if holdDuration < MAX_HOLD_TIME * 0.30 then
		return "TAP"
	elseif holdDuration < MAX_HOLD_TIME * 0.95 then
		return "MEDIUM"
	end
	return "MAX"
end

local function stopHolding(current: CharacterState)
	if not current.isHoldingJump then
		return
	end

	current.isHoldingJump = false
	current.holdDuration = math.min(os.clock() - current.pressTime, MAX_HOLD_TIME)
	zeroHoldForce(current)
end

local function beginJump(current: CharacterState)
	if current.jumpActive or not isGrounded(current) then
		return
	end

	current.jumpActive = true
	current.isHoldingJump = true
	current.leftGround = false
	current.pressTime = os.clock()
	current.holdDuration = 0
	current.startHeight = current.root.Position.Y
	current.maximumHeight = current.startHeight
	current.maximumBasketLag = 0

	-- The default Space action is sunk, so this is the only launch request.
	-- Change state for normal Humanoid behavior, then set the launch velocity once.
	current.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	local velocity = current.root.AssemblyLinearVelocity
	current.root.AssemblyLinearVelocity = Vector3.new(
		velocity.X,
		INITIAL_JUMP_SPEED,
		velocity.Z
	)
end

local function releaseJump(current: CharacterState)
	if not current.isHoldingJump then
		return
	end

	local releasedEarly = os.clock() - current.pressTime < MAX_HOLD_TIME
	stopHolding(current)

	if releasedEarly then
		local velocity = current.root.AssemblyLinearVelocity
		if velocity.Y > 0 then
			current.root.AssemblyLinearVelocity = Vector3.new(
				velocity.X,
				velocity.Y * EARLY_RELEASE_MULTIPLIER,
				velocity.Z
			)
		end
	end
end

local function finishLanding(current: CharacterState)
	stopHolding(current)
	current.jumpActive = false
	current.leftGround = false

	print(
		"[VariableJump] Landing",
		"hold=" .. string.format("%.3f", current.holdDuration),
		"category=" .. classifyJump(current.holdDuration),
		"maxHeight=" .. string.format(
			"%.3f",
			math.max(current.maximumHeight - current.startHeight, 0)
		),
		"defaultConsumed=" .. tostring(defaultJumpConsumed),
		"clientBasketLag=" .. string.format("%.3f", current.maximumBasketLag)
	)
end

local function handleJumpAction(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	defaultJumpConsumed = true
	local current = state

	if current then
		if inputState == Enum.UserInputState.Begin then
			beginJump(current)
		elseif inputState == Enum.UserInputState.End then
			releaseJump(current)
		elseif inputState == Enum.UserInputState.Cancel then
			stopHolding(current)
		end
	end

	-- Sink every state so the default PlayerModule jump cannot execute under
	-- this controller. Keyboard Space is the only bound input in this milestone.
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

	-- Space is sunk at high priority; launch velocity is set directly on Begin.
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
		pressTime = 0,
		holdDuration = 0,
		startHeight = rootInstance.Position.Y,
		maximumHeight = rootInstance.Position.Y,
		maximumBasketLag = 0,
	}
	state = current

	table.insert(current.connections, humanoidInstance.StateChanged:Connect(function(
		_previousState: Enum.HumanoidStateType,
		newState: Enum.HumanoidStateType
	)
		if state ~= current then
			return
		end

		if current.jumpActive
			and (newState == Enum.HumanoidStateType.Jumping
				or newState == Enum.HumanoidStateType.Freefall)
		then
			current.leftGround = true
		elseif current.jumpActive
			and current.leftGround
			and (newState == Enum.HumanoidStateType.Landed
				or newState == Enum.HumanoidStateType.Running
				or newState == Enum.HumanoidStateType.RunningNoPhysics)
		then
			finishLanding(current)
		end
	end))

	table.insert(current.connections, humanoidInstance.Died:Connect(function()
		if state == current then
			stopHolding(current)
			current.jumpActive = false
		end
	end))

	table.insert(current.connections, character.Destroying:Connect(function()
		if state == current then
			disconnectCharacterState()
		end
	end))

	print(
		"[VariableJump] Ready",
		"gravity=" .. tostring(Workspace.Gravity),
		"jumpPower=" .. tostring(humanoidInstance.JumpPower),
		"spacePriority=" .. tostring(ACTION_PRIORITY),
		"defaultConsumedBySink=true",
		"releaseMode=forceOnlyNoVelocityCut",
		"physicsMode=restoredNativeEggBaseline"
	)
end

-- Rebinding the same action name first removes any stale copy of this custom
-- controller. No ButtonA or touch action is added during keyboard tuning.
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

RunService.PreSimulation:Connect(function()
	local current = state
	if not current or not current.character.Parent or current.humanoid.Health <= 0 then
		return
	end

	if current.jumpActive then
		current.maximumHeight = math.max(
			current.maximumHeight,
			current.root.Position.Y
		)
		local basketLag = getBasketLag(current)
		if basketLag then
			current.maximumBasketLag = math.max(current.maximumBasketLag, basketLag)
		end
	end

	if not current.jumpActive or not current.isHoldingJump then
		zeroHoldForce(current)
		return
	end

	local elapsed = os.clock() - current.pressTime
	if elapsed >= MAX_HOLD_TIME then
		-- Reaching the time cap ends assistance without changing velocity.
		-- Character, basket, and eggs keep continuous trajectories while natural
		-- gravity completes the jump.
		stopHolding(current)
		return
	end

	current.holdForce.Force = Vector3.new(
		0,
		current.root.AssemblyMass * HOLD_UPWARD_ACCELERATION,
		0
	)
	current.holdForce.Enabled = true
end)

if player.Character then
	task.spawn(attachCharacter, player.Character)
end
