--!strict

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")

-- Measured from Workspace.Rig.Head:ToObjectSpace(Workspace.Rig.Basket:GetPivot()).
-- This moves only the generated gameplay basket; the preview Basket is not copied.
-- BasketHold tilts Head slightly backward. Counter-pitch the Head-attached
-- basket forward so it appears level in the authored gameplay pose.
local BASKET_FORWARD_PITCH_DEGREES = -2.4
local BASKET_OFFSET = CFrame.new(
	0.0020941495895385742,
	0.6161737442016602,
	-0.11329696327447891
) * CFrame.Angles(math.rad(BASKET_FORWARD_PITCH_DEGREES), 0, 0)

local BASKET_HOLD_ANIMATION_ID = "rbxassetid://78788082464822"

local BASKET_HOLD_ANIMATION_TEMPLATE = Instance.new("Animation")
BASKET_HOLD_ANIMATION_TEMPLATE.Name = "BasketHold"
BASKET_HOLD_ANIMATION_TEMPLATE.AnimationId = BASKET_HOLD_ANIMATION_ID
BASKET_HOLD_ANIMATION_TEMPLATE.Parent = script

-- Load the authored pose before any gameplay basket is attached. This prevents
-- a visible basket/default-arms gap while Roblox fetches the animation asset.
local basketHoldPreloaded, basketHoldPreloadError = pcall(function()
	ContentProvider:PreloadAsync({ BASKET_HOLD_ANIMATION_TEMPLATE })
end)
if not basketHoldPreloaded then
	warn("BasketAttachmentService: BasketHold preload failed: " .. tostring(basketHoldPreloadError))
end

local BASKET_NAME = "Basket"
local LEGACY_BASKET_NAME = "TemporaryBasket"
local BASKET_COLOR = Color3.fromRGB(151, 105, 54)
local BASKET_MATERIAL = Enum.Material.Wood

local RIGHT_IK_NAME = "BasketRightArmIK"
local LEFT_IK_NAME = "BasketLeftArmIK"
local RIGHT_ROTATION_IK_NAME = "BasketRightHandRotationIK"
local LEFT_ROTATION_IK_NAME = "BasketLeftHandRotationIK"

-- Temporary test switch: keep the basket attached while the avatar uses its
-- normal default arm animations. Set this back to true to restore the pose.
local ARM_IK_ENABLED = false

type BasketHoldState = {
	track: AnimationTrack,
	animation: Animation,
	connections: { RBXScriptConnection },
	cleaning: boolean,
}

local activeBasketHolds: { [Model]: BasketHoldState } = {}

-- Adjust these CFrames to move or rotate the two basket grip points.
-- Position is relative to Basket.Bottom. The orientation makes the fingers
-- point upward while the visible palms face inward toward the basket.
local RIGHT_GRIP_TARGET_OFFSET = CFrame.lookAt(
	Vector3.new(1.08, -0.11, 0),
	Vector3.new(0.08, -0.11, 0),
	Vector3.new(0, -1, 0)
)
local LEFT_GRIP_TARGET_OFFSET = CFrame.lookAt(
	Vector3.new(-1.08, -0.11, 0),
	Vector3.new(-0.08, -0.11, 0),
	Vector3.new(0, -1, 0)
)

-- Pole targets keep the elbows slightly outside the hands.
local RIGHT_ELBOW_POLE_OFFSET = CFrame.new(2.0, -1.2, 0.35)
local LEFT_ELBOW_POLE_OFFSET = CFrame.new(-2.0, -1.2, 0.35)

type BasketPartDefinition = {
	name: string,
	size: Vector3,
	offset: CFrame,
}

local BASKET_PARTS: { BasketPartDefinition } = {
	{
		name = "Bottom",
		size = Vector3.new(2.4, 0.2, 1.8),
		offset = CFrame.new(0, 0, 0),
	},
	{
		name = "FrontWall",
		size = Vector3.new(2.4, 0.65, 0.18),
		offset = CFrame.new(0, 0.425, -0.81),
	},
	{
		name = "BackWall",
		size = Vector3.new(2.4, 0.65, 0.18),
		offset = CFrame.new(0, 0.425, 0.81),
	},
	{
		name = "LeftWall",
		size = Vector3.new(0.18, 0.65, 1.8),
		offset = CFrame.new(-1.11, 0.425, 0),
	},
	{
		name = "RightWall",
		size = Vector3.new(0.18, 0.65, 1.8),
		offset = CFrame.new(1.11, 0.425, 0),
	},
}

local function configureBasketPart(part: Part)
	part.Color = BASKET_COLOR
	part.Material = BASKET_MATERIAL
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function createBasketPart(
	definition: BasketPartDefinition,
	basketPivot: CFrame,
	basket: Model
): Part
	local part = Instance.new("Part")
	part.Name = definition.name
	part.Size = definition.size
	configureBasketPart(part)
	part.CFrame = basketPivot * definition.offset
	part.Parent = basket

	return part
end

local function weldParts(part0: BasePart, part1: BasePart, name: string)
	local weld = Instance.new("WeldConstraint")
	weld.Name = name
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
end

local function createHandTarget(bottom: BasePart, name: string, targetCFrame: CFrame): Attachment
	local target = Instance.new("Attachment")
	target.Name = name
	target.CFrame = targetCFrame
	target.Parent = bottom

	return target
end

local function createHandContactAttachment(
	hand: BasePart,
	sourceGrip: Attachment,
	name: string
): Attachment
	local existing = hand:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local contact = Instance.new("Attachment")
	contact.Name = name
	-- Put the IK pivot near the upper palm/fingers, not at the hand center.
	-- This lets short R15 arms visibly touch the basket without stretching limbs.
	local contactPosition = Vector3.new(
		sourceGrip.Position.X,
		hand.Size.Y * 0.45,
		sourceGrip.Position.Z
	)
	contact.CFrame = CFrame.new(contactPosition) * sourceGrip.CFrame.Rotation
	contact.Parent = hand
	return contact
end

local function createArmIK(
	humanoid: Humanoid,
	name: string,
	ikType: Enum.IKControlType,
	chainRoot: Instance,
	endEffector: Instance,
	target: Attachment,
	pole: Attachment?,
	priority: number
)
	local existing = humanoid:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local ik = Instance.new("IKControl")
	ik.Name = name
	ik.Type = ikType
	ik.ChainRoot = chainRoot
	ik.EndEffector = endEffector
	ik.Target = target
	if pole then
		ik.Pole = pole
	end
	ik.Priority = priority
	ik.Weight = 1
	ik.SmoothTime = 0
	ik.Parent = humanoid
end

local function removeArmIKControls(humanoid: Humanoid)
	for _, ikName in {
		RIGHT_IK_NAME,
		LEFT_IK_NAME,
		RIGHT_ROTATION_IK_NAME,
		LEFT_ROTATION_IK_NAME,
	} do
		local existing = humanoid:FindFirstChild(ikName)
		if existing and existing:IsA("IKControl") then
			existing:Destroy()
		end
	end
end

local function stopBasketHoldAnimation(character: Model)
	local state = activeBasketHolds[character]
	if not state or state.cleaning then
		return
	end

	state.cleaning = true
	activeBasketHolds[character] = nil

	for _, connection in state.connections do
		connection:Disconnect()
	end

	if state.track.IsPlaying then
		state.track:Stop(0.1)
	end
	state.track:Destroy()
	state.animation:Destroy()
end

local function playBasketHoldAnimation(
	character: Model,
	humanoid: Humanoid,
	basket: Model
)
	stopBasketHoldAnimation(character)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Clean up a matching track that may have survived a script hot reload.
	for _, existingTrack in animator:GetPlayingAnimationTracks() do
		local existingAnimation = existingTrack.Animation
		if existingAnimation and existingAnimation.AnimationId == BASKET_HOLD_ANIMATION_ID then
			existingTrack:Stop(0)
			existingTrack:Destroy()
		end
	end

	local animation = BASKET_HOLD_ANIMATION_TEMPLATE:Clone()
	animation.Parent = basket

	local loaded, loadedTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not loaded then
		animation:Destroy()
		warn("BasketAttachmentService: BasketHold failed to load: " .. tostring(loadedTrack))
		return
	end

	local track = loadedTrack :: AnimationTrack
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action4

	local state: BasketHoldState = {
		track = track,
		animation = animation,
		connections = {},
		cleaning = false,
	}
	activeBasketHolds[character] = state

	local function cleanUp()
		stopBasketHoldAnimation(character)
	end

	table.insert(state.connections, basket.Destroying:Connect(cleanUp))
	table.insert(state.connections, basket.AncestryChanged:Connect(function()
		if not basket:IsDescendantOf(character) then
			cleanUp()
		end
	end))
	table.insert(state.connections, humanoid.Died:Connect(cleanUp))
	table.insert(state.connections, character.Destroying:Connect(cleanUp))

	-- No blend-in: apply the published BasketHold keys at full weight exactly as authored.
	track:Play(0, 1, 1)
	track:AdjustWeight(1, 0)
end

local function addR15HoldingPose(character: Model, humanoid: Humanoid, bottom: BasePart)
	local rightUpperArm = character:FindFirstChild("RightUpperArm")
	local rightLowerArm = character:FindFirstChild("RightLowerArm")
	local rightHand = character:FindFirstChild("RightHand")
	local leftUpperArm = character:FindFirstChild("LeftUpperArm")
	local leftLowerArm = character:FindFirstChild("LeftLowerArm")
	local leftHand = character:FindFirstChild("LeftHand")

	if not (
		rightUpperArm and rightUpperArm:IsA("BasePart")
		and rightLowerArm and rightLowerArm:IsA("BasePart")
		and rightHand and rightHand:IsA("BasePart")
		and leftUpperArm and leftUpperArm:IsA("BasePart")
		and leftLowerArm and leftLowerArm:IsA("BasePart")
		and leftHand and leftHand:IsA("BasePart")
	) then
		warn("BasketAttachmentService: R15 arm parts were not available")
		return
	end

	local rightHandGrip = rightHand:FindFirstChild("RightGripAttachment")
	local leftHandGrip = leftHand:FindFirstChild("LeftGripAttachment")
	if not (
		rightHandGrip and rightHandGrip:IsA("Attachment")
		and leftHandGrip and leftHandGrip:IsA("Attachment")
	) then
		warn("BasketAttachmentService: R15 hand GripAttachments were not available")
		return
	end

	local rightTarget = createHandTarget(bottom, "RightGripTarget", RIGHT_GRIP_TARGET_OFFSET)
	local leftTarget = createHandTarget(bottom, "LeftGripTarget", LEFT_GRIP_TARGET_OFFSET)
	local rightPole = createHandTarget(bottom, "RightElbowPole", RIGHT_ELBOW_POLE_OFFSET)
	local leftPole = createHandTarget(bottom, "LeftElbowPole", LEFT_ELBOW_POLE_OFFSET)
	local rightContact = createHandContactAttachment(
		rightHand,
		rightHandGrip,
		"RightBasketHandContact"
	)
	local leftContact = createHandContactAttachment(
		leftHand,
		leftHandGrip,
		"LeftBasketHandContact"
	)

	-- Solve contact first, then rotate only the hand. A single Transform solve
	-- cannot satisfy both on short-arm R15 proportions without leaving a gap.
	createArmIK(
		humanoid,
		RIGHT_IK_NAME,
		Enum.IKControlType.Position,
		rightUpperArm,
		rightContact,
		rightTarget,
		rightPole,
		20
	)
	createArmIK(
		humanoid,
		LEFT_IK_NAME,
		Enum.IKControlType.Position,
		leftUpperArm,
		leftContact,
		leftTarget,
		leftPole,
		20
	)
	createArmIK(
		humanoid,
		RIGHT_ROTATION_IK_NAME,
		Enum.IKControlType.Rotation,
		rightLowerArm,
		rightHand,
		rightTarget,
		nil,
		10
	)
	createArmIK(
		humanoid,
		LEFT_ROTATION_IK_NAME,
		Enum.IKControlType.Rotation,
		leftLowerArm,
		leftHand,
		leftTarget,
		nil,
		10
	)
end

local function clearOldBasket(character: Model)
	for _, basketName in { BASKET_NAME, LEGACY_BASKET_NAME } do
		local existing = character:FindFirstChild(basketName)
		if existing then
			existing:Destroy()
		end
	end
end

local function attachBasket(character: Model)
	clearOldBasket(character)

	local head = character:WaitForChild("Head", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not head or not head:IsA("BasePart") then
		warn("BasketAttachmentService: character Head was not available")
		return
	end
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn("BasketAttachmentService: character Humanoid was not available")
		return
	end

	local basket = Instance.new("Model")
	basket.Name = BASKET_NAME

	local basketPivot = head.CFrame * BASKET_OFFSET
	local bottom: Part? = nil

	for _, definition in BASKET_PARTS do
		local part = createBasketPart(definition, basketPivot, basket)
		if definition.name == "Bottom" then
			bottom = part
		end
	end

	if not bottom then
		basket:Destroy()
		warn("BasketAttachmentService: basket Bottom was not created")
		return
	end

	basket.PrimaryPart = bottom

	for _, child in basket:GetChildren() do
		if child:IsA("BasePart") and child ~= bottom then
			weldParts(bottom, child, "BottomWeld")
		end
	end
	weldParts(head, bottom, "HeadWeld")

	basket.Parent = character

	-- Always clear controls left by an earlier version/hot reload. During this
	-- test createArmIK is unreachable, so the avatar keeps its default arms.
	removeArmIKControls(humanoid)

	if ARM_IK_ENABLED and humanoid.RigType == Enum.HumanoidRigType.R15 then
		addR15HoldingPose(character, humanoid, bottom)
	elseif ARM_IK_ENABLED then
		warn("BasketAttachmentService: the temporary holding pose currently requires an R15 avatar")
	end

	playBasketHoldAnimation(character, humanoid, basket)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(attachBasket)

	if player.Character then
		task.spawn(attachBasket, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
