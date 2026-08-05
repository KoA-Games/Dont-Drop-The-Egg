--!strict

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local IMPORTED_VISUAL_TEMPLATE_NAME = "DefaultBasketVisualTemplate"
local IMPORTED_VISUAL_SOURCE_NAMES = {
	"LowWideWovenBasket_RobloxTextured",
	"LowWideWovenBasket_RobloxOptimized",
	"BasketVisualTemplate",
}

-- Remove the full-size FBX import from the spawn area before any yielding
-- operation (including animation preloading) can allow a character to spawn on
-- it. Preserve one private copy for the carried basket visual.
do
	local template = ServerStorage:FindFirstChild(IMPORTED_VISUAL_TEMPLATE_NAME)
	for _, descendant in Workspace:GetDescendants() do
		local isNamedImport = table.find(IMPORTED_VISUAL_SOURCE_NAMES, descendant.Name) ~= nil
		local containsMesh = descendant:IsA("BasePart")
			or (descendant:IsA("Model")
				and descendant:FindFirstChildWhichIsA("BasePart", true) ~= nil)
		if isNamedImport and containsMesh then
			if not template then
				template = descendant:Clone()
				template.Name = IMPORTED_VISUAL_TEMPLATE_NAME
				template.Parent = ServerStorage
			end
			descendant:Destroy()
		end
	end
end

-- Measured from Workspace.Rig.Head:ToObjectSpace(Workspace.Rig.Basket:GetPivot()).
-- This moves only the generated gameplay basket; the preview Basket is not copied.
-- Keep the authored placement neutral before it is captured by the rigid
-- HumanoidRootPart mount.
local BASKET_FORWARD_PITCH_DEGREES = 0
-- Lower the complete basket assembly so the palms support the lower corners
-- instead of hovering below the imported visual.
local BASKET_VERTICAL_ADJUSTMENT = -0.18
local BASKET_OFFSET = CFrame.new(
	0.0020941495895385742,
	0.6161737442016602 + BASKET_VERTICAL_ADJUSTMENT,
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
local BASKET_TARGET_NAME = "BasketTarget"
local BASKET_ORIENTATION_TARGET_NAME = "BasketOrientationTarget"
local BASKET_ATTACHMENT_NAME = "BasketAttachment"
local MOUNT_READY_ATTRIBUTE = "BasketMountReady"
local FALL_BASKET_RELEASE_REMOTE_NAME = "FallBasketReleasePreview"
local FALL_BASKET_RELEASE_REQUEST_NAME = "FallBasketReleaseRequest"
local FALL_BASKET_RELEASED_ATTRIBUTE = "FallBasketReleased"
local FALL_CHARACTER_COLLISION_IGNORE_DURATION = 0.25
-- The hands are already travelling with the collapsing body at release. Add a
-- separate horizontal throw component so the basket visibly continues in the
-- selected fall direction instead of merely inheriting motion and dropping down.
local FALL_BASKET_MIN_HORIZONTAL_SPEED = 10.0
local FALL_BASKET_MAX_HORIZONTAL_SPEED = 16.0
local FALL_BASKET_SIDE_SPEED = 12.0
local FALL_BASKET_FORWARD_INHERITANCE = 0.30
local FALL_BASKET_MIN_UPWARD_SPEED = 4.0
local FALL_BASKET_MAX_UPWARD_SPEED = 6.5
local FALL_BASKET_RELEASE_SPIN = Vector3.new(1.5, -4.5, 2.2)
local BASKET_OWNER_ATTRIBUTE = "OwnerUserId"
local BASKET_PICKUP_STAGE_ATTRIBUTE = "BasketPickupStage"
local BASKET_CARRY_MOUNT_ATTRIBUTE = "BasketCarryMountLocalCFrame"
local BASKET_CARRY_POSITION_TARGET_ATTRIBUTE = "BasketCarryPositionTargetLocalCFrame"
local BASKET_CARRY_ORIENTATION_TARGET_ATTRIBUTE = "BasketCarryOrientationTargetLocalCFrame"
local BASKET_TEMPORARY_GRIP_NAME = "BasketPickupHandGrip"
local LIVE_EGG_ATTRIBUTE = "IsBasketEgg"
local IN_BASKET_ATTRIBUTE = "InBasket"
local HAS_LEFT_BASKET_ATTRIBUTE = "HasLeftBasket"
local PICKUP_SECURED_EGG_ATTRIBUTE = "BasketPickupSecured"
local PICKUP_EGG_LOCAL_PIVOT_ATTRIBUTE = "BasketPickupLocalPivot"
local PICKUP_EGG_ORIGINAL_ANCHORED_ATTRIBUTE = "BasketPickupOriginalAnchored"
local PICKUP_EGG_ORIGINAL_MASSLESS_ATTRIBUTE = "BasketPickupOriginalMassless"
local PICKUP_EGG_ORIGINAL_CAN_COLLIDE_ATTRIBUTE = "BasketPickupOriginalCanCollide"
local PICKUP_EGG_ORIGINAL_CAN_TOUCH_ATTRIBUTE = "BasketPickupOriginalCanTouch"
local EGG_COLLISION_SHELL_NAME = "EggCollisionShell"
local EGG_BASKET_COLLISION_GROUP = "EggBasket"
local BASKET_PICKUP_MAX_DISTANCE = 3.25
local BASKET_EMERGENCY_FORWARD_DISTANCE = 2.0
-- Visual-only woven prototype dimensions. Bottom remains the physical mount
-- reference, so changing the appearance never changes the authored hand pose.
local LOWER_OUTER_WIDTH = 2.05
local LOWER_OUTER_DEPTH = 1.55
local UPPER_OUTER_WIDTH = 2.55
local UPPER_OUTER_DEPTH = 2.20
local VISUAL_WALL_HEIGHT = 0.90
local BOTTOM_THICKNESS = 0.20
local PANEL_THICKNESS = 0.10
local PANEL_OVERLAP = 0.03
local WEAVE_DETAIL_HEIGHT = 0.07
local WEAVE_DETAIL_THICKNESS = 0.035
local RIM_HEIGHT = 0.18
local RIM_THICKNESS = 0.12
local SUPPORT_THICKNESS = 0.11
-- The gameplay collision shell, hand contacts, and egg layout were authored
-- for this size. Imported meshes are uniformly fitted to these outer bounds.
local IMPORTED_VISUAL_TARGET_SIZE = Vector3.new(
	UPPER_OUTER_WIDTH,
	VISUAL_WALL_HEIGHT,
	UPPER_OUTER_DEPTH
)
local IMPORTED_WICKER_FALLBACK_COLOR = Color3.fromRGB(190, 123, 58)

local BOTTOM_COLOR = Color3.fromRGB(151, 94, 42)
local PANEL_LOWER_COLOR = Color3.fromRGB(171, 111, 51)
local PANEL_MIDDLE_COLOR = Color3.fromRGB(165, 103, 45)
local PANEL_UPPER_COLOR = Color3.fromRGB(158, 96, 41)
local WEAVE_DETAIL_COLOR = Color3.fromRGB(112, 64, 27)
local SUPPORT_COLOR = Color3.fromRGB(126, 73, 31)
local RIM_COLOR = Color3.fromRGB(202, 142, 72)
local PANEL_MATERIAL = Enum.Material.Fabric
local STRUCTURE_MATERIAL = Enum.Material.WoodPlanks

-- A physical follower is required because animated hand motion is relative to
-- HumanoidRootPart. Jump velocity is seeded once by VariableJumpController so
-- these constraints never need to catch up from zero during takeoff.
local POSITION_RESPONSIVENESS = 120
local POSITION_MAX_VELOCITY = 70
local HORIZONTAL_MAX_FORCE_PER_MASS = 2400
local VERTICAL_MAX_FORCE_PER_MASS = 1600
local ORIENTATION_RESPONSIVENESS = 100
local ORIENTATION_MAX_TORQUE_PER_MASS = 1400
-- Keep loose eggs out of the basket while the mount changes from its bootstrap
-- weld to the hand-following constraints. This changes only initialization
-- timing; it does not alter gravity, constraint forces, or egg physics.
local INITIAL_MOUNT_SETTLE_TIME = 0.6


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

local function configureBottomAnchor(part: Part)
	part.Transparency = 1
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function configureVisibleBasketPart(part: Part, color: Color3)
	part.Color = color
	part.Material = if part.Name:find("Panel") or part.Name:find("WeaveStrip")
		then PANEL_MATERIAL
		else STRUCTURE_MATERIAL
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
end

local function removeOldBasketTarget(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Attachment") and (
			descendant.Name == BASKET_TARGET_NAME
			or descendant.Name == BASKET_ORIENTATION_TARGET_NAME
		) then
			descendant:Destroy()
		end
	end
end

local function weldParts(part0: BasePart, part1: BasePart, name: string): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Name = name
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
	return weld
end

local function countNamedDescendants(root: Instance, name: string): number
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant.Name == name then
			count += 1
		end
	end
	return count
end

local function destroyNamedDescendants(root: Instance, names: { [string]: boolean })
	for _, descendant in root:GetDescendants() do
		if names[descendant.Name] then
			descendant:Destroy()
		end
	end
end

local function sanitizeCarriedBasketPhysics(basket: Model)
	for _, descendant in basket:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		elseif descendant:IsA("AngularVelocity")
			or descendant:IsA("BodyGyro")
			or descendant:IsA("VectorForce")
			or descendant:IsA("Torque")
		then
			descendant:Destroy()
		end
	end
end

local function getBasketPhysicalMass(basket: Model): number
	local totalMass = 0
	for _, descendant in basket:GetDescendants() do
		if descendant:IsA("BasePart") then
			totalMass += descendant:GetMass()
		end
	end
	return math.max(totalMass, 0.1)
end

local function createVisualPart(
	name: string,
	size: Vector3,
	localCFrame: CFrame,
	color: Color3,
	parent: Instance,
	bottom: BasePart
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	configureVisibleBasketPart(part, color)
	part.CFrame = bottom.CFrame * localCFrame
	part.Parent = parent
	weldParts(bottom, part, "BottomWeld")
	return part
end

local function isImportedVisualRoot(instance: Instance): boolean
	if instance:IsA("BasePart") then
		return true
	end
	if not instance:IsA("Model") then
		return false
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			return true
		end
	end
	return false
end

local function getWorkspaceImportedDisplaySources(): { Instance }
	local sources: { Instance } = {}
	for _, descendant in Workspace:GetDescendants() do
		if table.find(IMPORTED_VISUAL_SOURCE_NAMES, descendant.Name)
			and isImportedVisualRoot(descendant)
		then
			table.insert(sources, descendant)
		end
	end
	return sources
end

local function removeWorkspaceImportedDisplaySources()
	for _, source in getWorkspaceImportedDisplaySources() do
		if source.Parent then
			source:Destroy()
		end
	end
end

local function findImportedVisualTemplate(): Instance?
	local cached = ServerStorage:FindFirstChild(IMPORTED_VISUAL_TEMPLATE_NAME)
	if cached and isImportedVisualRoot(cached) then
		removeWorkspaceImportedDisplaySources()
		return cached
	end

	for _, sourceName in IMPORTED_VISUAL_SOURCE_NAMES do
		local storedSource = ServerStorage:FindFirstChild(sourceName, true)
		if storedSource and isImportedVisualRoot(storedSource) then
			removeWorkspaceImportedDisplaySources()
			return storedSource
		end
	end

	local workspaceSources = getWorkspaceImportedDisplaySources()
	local source = workspaceSources[1]
	if source then
		-- Preserve one clean template outside Workspace before removing every
		-- oversized FBX import/display copy from the spawn area.
		local template = source:Clone()
		template.Name = IMPORTED_VISUAL_TEMPLATE_NAME
		template.Parent = ServerStorage
		for _, displaySource in workspaceSources do
			if displaySource.Parent then
				displaySource:Destroy()
			end
		end
		return template
	end

	return nil
end

local function importedVisualBounds(visualRoot: Instance): (CFrame, Vector3)
	if visualRoot:IsA("Model") then
		return visualRoot:GetBoundingBox()
	end
	local part = visualRoot :: BasePart
	return part.CFrame, part.Size
end

local function scaleImportedVisualToGameplaySize(visualRoot: Instance): number
	local _, currentSize = importedVisualBounds(visualRoot)
	local scaleFactor = math.min(
		IMPORTED_VISUAL_TARGET_SIZE.X / math.max(currentSize.X, 0.001),
		IMPORTED_VISUAL_TARGET_SIZE.Y / math.max(currentSize.Y, 0.001),
		IMPORTED_VISUAL_TARGET_SIZE.Z / math.max(currentSize.Z, 0.001)
	)

	if visualRoot:IsA("Model") then
		visualRoot:ScaleTo(visualRoot:GetScale() * scaleFactor)
	else
		local part = visualRoot :: BasePart
		part.Size *= scaleFactor
	end
	return scaleFactor
end

local function configureImportedVisualPart(part: BasePart, bottom: BasePart)
	local hasImageTexture = part:IsA("MeshPart") and part.TextureID ~= ""
	local hasSurfaceAppearance = false
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceAppearance") then
			hasSurfaceAppearance = true
			-- FBX import can preserve Blender's dark material tint on top of the
			-- already-colored albedo. White removes that double-darkening while
			-- preserving the woven Base Color texture and UV layout.
			child.Color = Color3.new(1, 1, 1)
		end
	end
	if hasImageTexture or hasSurfaceAppearance then
		part.Color = Color3.new(1, 1, 1)
	else
		part.Color = IMPORTED_WICKER_FALLBACK_COLOR
	end
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
	weldParts(bottom, part, "BottomWeld")
end

local function createImportedVisualBasket(basket: Model, bottom: BasePart): boolean
	local template = findImportedVisualTemplate()
	if not template then
		return false
	end

	local visualRoot = template:Clone()
	visualRoot.Name = "VisualBasket"
	visualRoot.Parent = basket
	local scaleFactor = scaleImportedVisualToGameplaySize(visualRoot)
	local boundsCFrame, boundsSize = importedVisualBounds(visualRoot)
	local targetBoundsCFrame = bottom.CFrame
		* CFrame.new(0, bottom.Size.Y * 0.5 + boundsSize.Y * 0.5, 0)

	if visualRoot:IsA("Model") then
		local pivotToBounds = visualRoot:GetPivot():ToObjectSpace(boundsCFrame)
		visualRoot:PivotTo(targetBoundsCFrame * pivotToBounds:Inverse())
	else
		local part = visualRoot :: BasePart
		part.CFrame = targetBoundsCFrame
	end

	local visualPartCount = 0
	if visualRoot:IsA("BasePart") then
		configureImportedVisualPart(visualRoot, bottom)
		visualPartCount += 1
	end
	for _, descendant in visualRoot:GetDescendants() do
		if descendant:IsA("BasePart") then
			configureImportedVisualPart(descendant, bottom)
			visualPartCount += 1
		end
	end

	if visualPartCount == 0 then
		visualRoot:Destroy()
		return false
	end

	basket:SetAttribute("BasketVisualSource", "ImportedTexturedBasket")
	basket:SetAttribute("BasketVisualScaleFactor", scaleFactor)
	basket:SetAttribute("BasketVisualWidth", boundsSize.X)
	basket:SetAttribute("BasketVisualHeight", boundsSize.Y)
	basket:SetAttribute("BasketVisualDepth", boundsSize.Z)
	return true
end

local function createFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function supportLocalCFrame(lowerPoint: Vector3, upperPoint: Vector3): CFrame
	local direction = upperPoint - lowerPoint
	local yAxis = direction.Unit
	local xAxis = Vector3.xAxis
	local zAxis = xAxis:Cross(yAxis).Unit
	xAxis = yAxis:Cross(zAxis).Unit
	return CFrame.fromMatrix((lowerPoint + upperPoint) * 0.5, xAxis, yAxis, zAxis)
end

local function widthAt(alpha: number): number
	return LOWER_OUTER_WIDTH + (UPPER_OUTER_WIDTH - LOWER_OUTER_WIDTH) * alpha
end

local function depthAt(alpha: number): number
	return LOWER_OUTER_DEPTH + (UPPER_OUTER_DEPTH - LOWER_OUTER_DEPTH) * alpha
end

local function frontBackPanelCFrame(
	zSign: number,
	startAlpha: number,
	endAlpha: number,
	floorTop: number
): (CFrame, number)
	local lowerPoint = Vector3.new(
		0,
		floorTop + VISUAL_WALL_HEIGHT * startAlpha,
		zSign * (depthAt(startAlpha) * 0.5 - PANEL_THICKNESS * 0.5)
	)
	local upperPoint = Vector3.new(
		0,
		floorTop + VISUAL_WALL_HEIGHT * endAlpha,
		zSign * (depthAt(endAlpha) * 0.5 - PANEL_THICKNESS * 0.5)
	)
	local yAxis = (upperPoint - lowerPoint).Unit
	local xAxis = Vector3.xAxis
	local zAxis = xAxis:Cross(yAxis).Unit
	return CFrame.fromMatrix((lowerPoint + upperPoint) * 0.5, xAxis, yAxis, zAxis),
		(upperPoint - lowerPoint).Magnitude
end

local function leftRightPanelCFrame(
	xSign: number,
	startAlpha: number,
	endAlpha: number,
	floorTop: number
): (CFrame, number)
	local lowerPoint = Vector3.new(
		xSign * (widthAt(startAlpha) * 0.5 - PANEL_THICKNESS * 0.5),
		floorTop + VISUAL_WALL_HEIGHT * startAlpha,
		0
	)
	local upperPoint = Vector3.new(
		xSign * (widthAt(endAlpha) * 0.5 - PANEL_THICKNESS * 0.5),
		floorTop + VISUAL_WALL_HEIGHT * endAlpha,
		0
	)
	local yAxis = (upperPoint - lowerPoint).Unit
	local zAxis = Vector3.zAxis
	local xAxis = yAxis:Cross(zAxis).Unit
	return CFrame.fromMatrix((lowerPoint + upperPoint) * 0.5, xAxis, yAxis, zAxis),
		(upperPoint - lowerPoint).Magnitude
end

local function frontBackDetailCFrame(zSign: number, alpha: number, floorTop: number): CFrame
	local lowerPoint = Vector3.new(
		0,
		floorTop,
		zSign * (LOWER_OUTER_DEPTH * 0.5 + WEAVE_DETAIL_THICKNESS * 0.5)
	)
	local upperPoint = Vector3.new(
		0,
		floorTop + VISUAL_WALL_HEIGHT,
		zSign * (UPPER_OUTER_DEPTH * 0.5 + WEAVE_DETAIL_THICKNESS * 0.5)
	)
	local yAxis = (upperPoint - lowerPoint).Unit
	local xAxis = Vector3.xAxis
	local zAxis = xAxis:Cross(yAxis).Unit
	local position = lowerPoint:Lerp(upperPoint, alpha)
	return CFrame.fromMatrix(position, xAxis, yAxis, zAxis)
end

local function leftRightDetailCFrame(xSign: number, alpha: number, floorTop: number): CFrame
	local lowerPoint = Vector3.new(
		xSign * (LOWER_OUTER_WIDTH * 0.5 + WEAVE_DETAIL_THICKNESS * 0.5),
		floorTop,
		0
	)
	local upperPoint = Vector3.new(
		xSign * (UPPER_OUTER_WIDTH * 0.5 + WEAVE_DETAIL_THICKNESS * 0.5),
		floorTop + VISUAL_WALL_HEIGHT,
		0
	)
	local yAxis = (upperPoint - lowerPoint).Unit
	local zAxis = Vector3.zAxis
	local xAxis = yAxis:Cross(zAxis).Unit
	local position = lowerPoint:Lerp(upperPoint, alpha)
	return CFrame.fromMatrix(position, xAxis, yAxis, zAxis)
end

local function createWovenVisualBasket(basket: Model, bottom: BasePart)
	local visualBasket = Instance.new("Model")
	visualBasket.Name = "VisualBasket"
	visualBasket.Parent = basket
	local floorTop = BOTTOM_THICKNESS * 0.5

	createVisualPart(
		"BottomPanel",
		Vector3.new(LOWER_OUTER_WIDTH, BOTTOM_THICKNESS, LOWER_OUTER_DEPTH),
		CFrame.identity,
		BOTTOM_COLOR,
		visualBasket,
		bottom
	)

	-- Three overlapping solid courses per face keep the wall visually closed while
	-- approximating a trapezoid with ordinary Roblox Parts.
	local frontPanel = Instance.new("Model")
	frontPanel.Name = "FrontPanel"
	frontPanel.Parent = visualBasket
	local backPanel = Instance.new("Model")
	backPanel.Name = "BackPanel"
	backPanel.Parent = visualBasket
	local leftPanel = Instance.new("Model")
	leftPanel.Name = "LeftPanel"
	leftPanel.Parent = visualBasket
	local rightPanel = Instance.new("Model")
	rightPanel.Name = "RightPanel"
	rightPanel.Parent = visualBasket

	local panelSegments = {
		{
			0,
			1 / 3 + PANEL_OVERLAP * 0.5 / VISUAL_WALL_HEIGHT,
			"LowerPanel",
			PANEL_LOWER_COLOR,
		},
		{
			1 / 3 - PANEL_OVERLAP * 0.5 / VISUAL_WALL_HEIGHT,
			2 / 3 + PANEL_OVERLAP * 0.5 / VISUAL_WALL_HEIGHT,
			"MiddlePanel",
			PANEL_MIDDLE_COLOR,
		},
		{
			2 / 3 - PANEL_OVERLAP * 0.5 / VISUAL_WALL_HEIGHT,
			1,
			"UpperPanel",
			PANEL_UPPER_COLOR,
		},
	}
	for _, segment in panelSegments do
		local startAlpha = segment[1] :: number
		local endAlpha = segment[2] :: number
		local partName = segment[3] :: string
		local color = segment[4] :: Color3
		local midpointAlpha = (startAlpha + endAlpha) * 0.5
		local frontCFrame, frontLength = frontBackPanelCFrame(-1, startAlpha, endAlpha, floorTop)
		local backCFrame, backLength = frontBackPanelCFrame(1, startAlpha, endAlpha, floorTop)
		local leftCFrame, leftLength = leftRightPanelCFrame(-1, startAlpha, endAlpha, floorTop)
		local rightCFrame, rightLength = leftRightPanelCFrame(1, startAlpha, endAlpha, floorTop)

		createVisualPart(
			partName,
			Vector3.new(widthAt(midpointAlpha), frontLength, PANEL_THICKNESS),
			frontCFrame,
			color,
			frontPanel,
			bottom
		)
		createVisualPart(
			partName,
			Vector3.new(widthAt(midpointAlpha), backLength, PANEL_THICKNESS),
			backCFrame,
			color,
			backPanel,
			bottom
		)
		createVisualPart(
			partName,
			Vector3.new(PANEL_THICKNESS, leftLength, depthAt(midpointAlpha)),
			leftCFrame,
			color,
			leftPanel,
			bottom
		)
		createVisualPart(
			partName,
			Vector3.new(PANEL_THICKNESS, rightLength, depthAt(midpointAlpha)),
			rightCFrame,
			color,
			rightPanel,
			bottom
		)
	end

	local frontDetails = createFolder("FrontWeaveDetails", visualBasket)
	local backDetails = createFolder("BackWeaveDetails", visualBasket)
	local leftDetails = createFolder("LeftWeaveDetails", visualBasket)
	local rightDetails = createFolder("RightWeaveDetails", visualBasket)
	for detailIndex, alpha in { 0.31, 0.69 } do
		local detailName = "WeaveStrip" .. tostring(detailIndex)
		createVisualPart(
			detailName,
			Vector3.new(widthAt(alpha) - 0.06, WEAVE_DETAIL_HEIGHT, WEAVE_DETAIL_THICKNESS),
			frontBackDetailCFrame(-1, alpha, floorTop),
			WEAVE_DETAIL_COLOR,
			frontDetails,
			bottom
		)
		createVisualPart(
			detailName,
			Vector3.new(widthAt(alpha) - 0.06, WEAVE_DETAIL_HEIGHT, WEAVE_DETAIL_THICKNESS),
			frontBackDetailCFrame(1, alpha, floorTop),
			WEAVE_DETAIL_COLOR,
			backDetails,
			bottom
		)
		createVisualPart(
			detailName,
			Vector3.new(WEAVE_DETAIL_THICKNESS, WEAVE_DETAIL_HEIGHT, depthAt(alpha) - 0.06),
			leftRightDetailCFrame(-1, alpha, floorTop),
			WEAVE_DETAIL_COLOR,
			leftDetails,
			bottom
		)
		createVisualPart(
			detailName,
			Vector3.new(WEAVE_DETAIL_THICKNESS, WEAVE_DETAIL_HEIGHT, depthAt(alpha) - 0.06),
			leftRightDetailCFrame(1, alpha, floorTop),
			WEAVE_DETAIL_COLOR,
			rightDetails,
			bottom
		)
	end

	local supports = createFolder("CornerSupports", visualBasket)
	local cornerSigns = {
		{ -1, -1, "FrontLeftSupport" },
		{ 1, -1, "FrontRightSupport" },
		{ -1, 1, "BackLeftSupport" },
		{ 1, 1, "BackRightSupport" },
	}
	for _, corner in cornerSigns do
		local xSign = corner[1] :: number
		local zSign = corner[2] :: number
		local lowerPoint = Vector3.new(
			xSign * (LOWER_OUTER_WIDTH * 0.5 - SUPPORT_THICKNESS * 0.5),
			floorTop,
			zSign * (LOWER_OUTER_DEPTH * 0.5 - SUPPORT_THICKNESS * 0.5)
		)
		local upperPoint = Vector3.new(
			xSign * (UPPER_OUTER_WIDTH * 0.5 - SUPPORT_THICKNESS * 0.5),
			floorTop + VISUAL_WALL_HEIGHT,
			zSign * (UPPER_OUTER_DEPTH * 0.5 - SUPPORT_THICKNESS * 0.5)
		)
		createVisualPart(
			corner[3] :: string,
			Vector3.new(SUPPORT_THICKNESS, (upperPoint - lowerPoint).Magnitude, SUPPORT_THICKNESS),
			supportLocalCFrame(lowerPoint, upperPoint),
			SUPPORT_COLOR,
			supports,
			bottom
		)
	end

	local topRim = createFolder("TopRim", visualBasket)
	local rimY = floorTop + VISUAL_WALL_HEIGHT
	createVisualPart(
		"FrontRim",
		Vector3.new(UPPER_OUTER_WIDTH, RIM_HEIGHT, RIM_THICKNESS),
		CFrame.new(0, rimY, -(UPPER_OUTER_DEPTH * 0.5 - RIM_THICKNESS * 0.5)),
		RIM_COLOR,
		topRim,
		bottom
	)
	createVisualPart(
		"BackRim",
		Vector3.new(UPPER_OUTER_WIDTH, RIM_HEIGHT, RIM_THICKNESS),
		CFrame.new(0, rimY, UPPER_OUTER_DEPTH * 0.5 - RIM_THICKNESS * 0.5),
		RIM_COLOR,
		topRim,
		bottom
	)
	createVisualPart(
		"LeftRim",
		Vector3.new(RIM_THICKNESS, RIM_HEIGHT, UPPER_OUTER_DEPTH),
		CFrame.new(-(UPPER_OUTER_WIDTH * 0.5 - RIM_THICKNESS * 0.5), rimY, 0),
		RIM_COLOR,
		topRim,
		bottom
	)
	createVisualPart(
		"RightRim",
		Vector3.new(RIM_THICKNESS, RIM_HEIGHT, UPPER_OUTER_DEPTH),
		CFrame.new(UPPER_OUTER_WIDTH * 0.5 - RIM_THICKNESS * 0.5, rimY, 0),
		RIM_COLOR,
		topRim,
		bottom
	)
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
	basket: Model,
	fadeTime: number?
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

	local resolvedFadeTime = fadeTime or 0
	track:Play(resolvedFadeTime, 1, 1)
	track:AdjustWeight(1, resolvedFadeTime)
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

local function getIntendedMountLocalCFrames(
	character: Model,
	root: BasePart,
	head: BasePart
): (CFrame, CFrame)
	local existingBasket = character:FindFirstChild(BASKET_NAME)
	if existingBasket and existingBasket:IsA("Model") then
		local bottom = existingBasket:FindFirstChild("Bottom")
		if bottom and bottom:IsA("BasePart") then
			local basketAttachment = bottom:FindFirstChild(BASKET_ATTACHMENT_NAME)
			local basketTarget: Attachment? = nil
			for _, descendant in character:GetDescendants() do
				if descendant.Name == BASKET_TARGET_NAME and descendant:IsA("Attachment") then
					basketTarget = descendant
					break
				end
			end

			if basketAttachment and basketAttachment:IsA("Attachment") and basketTarget then
				return root.CFrame:ToObjectSpace(basketTarget.WorldCFrame), basketAttachment.CFrame
			end
		end
	end

	-- This is the same local target used by the original root-attached
	-- BasketTarget. BasketAttachment was identity in that system.
	local targetLocalCFrame = root.CFrame:ToObjectSpace(head.CFrame * BASKET_OFFSET)
	return targetLocalCFrame, CFrame.identity
end

local function attachBasket(character: Model)
	local head = character:WaitForChild("Head", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local rightHand = character:WaitForChild("RightHand", 10)
	if not head or not head:IsA("BasePart") then
		warn("BasketAttachmentService: character Head was not available")
		return
	end
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn("BasketAttachmentService: character Humanoid was not available")
		return
	end
	if not root or not root:IsA("BasePart") then
		warn("BasketAttachmentService: HumanoidRootPart was not available")
		return
	end
	if not rightHand or not rightHand:IsA("BasePart") then
		warn("BasketAttachmentService: RightHand was not available")
		return
	end

	local basketTargetLocalCFrame, basketAttachmentLocalCFrame =
		getIntendedMountLocalCFrames(character, root, head)
	local desiredBottomCFrame = root.CFrame
		* basketTargetLocalCFrame
		* basketAttachmentLocalCFrame:Inverse()
	clearOldBasket(character)
	removeOldBasketTarget(character)

	local basket = Instance.new("Model")
	basket.Name = BASKET_NAME
	basket:SetAttribute(MOUNT_READY_ATTRIBUTE, false)
	local basketOwner = Players:GetPlayerFromCharacter(character)
	if basketOwner then
		basket:SetAttribute(BASKET_OWNER_ATTRIBUTE, basketOwner.UserId)
	end
	basket:SetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE, "Carried")
	-- Save the exact authored carry transform once. Recovery restores this
	-- value verbatim instead of estimating a new head-relative placement from
	-- the moving BasketPickup pose.
	basket:SetAttribute(
		BASKET_CARRY_MOUNT_ATTRIBUTE,
		root.CFrame:ToObjectSpace(desiredBottomCFrame)
	)

	-- Bottom is an invisible mount reference. Its world CFrame, the model pivot,
	-- and all follower constraints remain identical to the working basket.
	local bottom = Instance.new("Part")
	bottom.Name = "Bottom"
	bottom.Size = Vector3.new(LOWER_OUTER_WIDTH, BOTTOM_THICKNESS, LOWER_OUTER_DEPTH)
	configureBottomAnchor(bottom)
	bottom.CFrame = desiredBottomCFrame
	bottom.Parent = basket

	basket.PrimaryPart = bottom
	bottom.Massless = false
	bottom.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.32, 0, 100, 20)
	if not createImportedVisualBasket(basket, bottom) then
		warn(
			"BasketAttachmentService: imported textured basket was not found; using procedural fallback"
		)
		createWovenVisualBasket(basket, bottom)
		basket:SetAttribute("BasketVisualSource", "ProceduralFallback")
	end
	createHandTarget(bottom, "LeftHandContact", CFrame.new(-0.98, -0.10, 0))
	createHandTarget(bottom, "RightHandContact", CFrame.new(0.98, -0.10, 0))

	basket.Parent = character
	local currentPivot = basket:GetPivot()
	local bottomToPivot = bottom.CFrame:ToObjectSpace(currentPivot)
	local desiredPivot = desiredBottomCFrame * bottomToPivot
	basket:PivotTo(desiredPivot)

	-- Keep the intended authored placement stable until BasketHold has applied.
	local bootstrapWeld = weldParts(root, bottom, "BasketBootstrapWeld")

	-- Always clear controls left by an earlier version/hot reload. During this
	-- test createArmIK is unreachable, so the avatar keeps its default arms.
	removeArmIKControls(humanoid)

	if ARM_IK_ENABLED and humanoid.RigType == Enum.HumanoidRigType.R15 then
		addR15HoldingPose(character, humanoid, bottom)
	elseif ARM_IK_ENABLED then
		warn("BasketAttachmentService: the temporary holding pose currently requires an R15 avatar")
	end

	playBasketHoldAnimation(character, humanoid, basket)

	task.spawn(function()
		for _ = 1, 6 do
			RunService.Heartbeat:Wait()
		end
		if not basket.Parent or not bottom.Parent or not rightHand.Parent then
			return
		end

		local target = Instance.new("Attachment")
		target.Name = BASKET_TARGET_NAME
		target.CFrame = rightHand.CFrame:ToObjectSpace(bottom.CFrame)
		target.Parent = rightHand
		basket:SetAttribute(BASKET_CARRY_POSITION_TARGET_ATTRIBUTE, target.CFrame)

		-- Position still follows the animated hand on every axis. Orientation uses
		-- the root-relative neutral hold rotation so run/landing body lean cannot
		-- pitch the basket floor forward and eject the eggs.
		local orientationTarget = Instance.new("Attachment")
		orientationTarget.Name = BASKET_ORIENTATION_TARGET_NAME
		orientationTarget.CFrame = root.CFrame:ToObjectSpace(bottom.CFrame)
		orientationTarget.Parent = root
		basket:SetAttribute(BASKET_CARRY_ORIENTATION_TARGET_ATTRIBUTE, orientationTarget.CFrame)

		local basketAttachment = Instance.new("Attachment")
		basketAttachment.Name = BASKET_ATTACHMENT_NAME
		basketAttachment.CFrame = CFrame.identity
		basketAttachment.Parent = bottom

		if bootstrapWeld.Parent then
			bootstrapWeld:Destroy()
		end

		local basketMass = bottom.AssemblyMass
		local maxAxesForce = Vector3.new(
			basketMass * HORIZONTAL_MAX_FORCE_PER_MASS,
			basketMass * VERTICAL_MAX_FORCE_PER_MASS,
			basketMass * HORIZONTAL_MAX_FORCE_PER_MASS
		)

		local alignPosition = Instance.new("AlignPosition")
		alignPosition.Name = "BasketAlignPosition"
		alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
		alignPosition.Attachment0 = basketAttachment
		alignPosition.Attachment1 = target
		alignPosition.RigidityEnabled = false
		alignPosition.ReactionForceEnabled = false
		alignPosition.ApplyAtCenterOfMass = true
		alignPosition.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		alignPosition.ForceRelativeTo = Enum.ActuatorRelativeTo.World
		alignPosition.MaxAxesForce = maxAxesForce
		alignPosition.MaxVelocity = POSITION_MAX_VELOCITY
		alignPosition.Responsiveness = POSITION_RESPONSIVENESS
		alignPosition.Parent = bottom

		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "BasketAlignOrientation"
		alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		alignOrientation.Attachment0 = basketAttachment
		alignOrientation.Attachment1 = orientationTarget
		alignOrientation.RigidityEnabled = false
		alignOrientation.ReactionTorqueEnabled = false
		alignOrientation.MaxTorque = basketMass * ORIENTATION_MAX_TORQUE_PER_MASS
		alignOrientation.Responsiveness = ORIENTATION_RESPONSIVENESS
		alignOrientation.Parent = bottom

		local basketOwner = Players:GetPlayerFromCharacter(character)
		if basketOwner then
			local canSetOwnership = bottom:CanSetNetworkOwnership()
			if canSetOwnership then
				pcall(function()
					bottom:SetNetworkOwner(basketOwner)
				end)
			end
		end

		-- AlignPosition and AlignOrientation need a short window to take over
		-- from BasketBootstrapWeld. Publishing readiness immediately allowed
		-- loose eggs to spawn during that one-time correction and get launched.
		task.wait(INITIAL_MOUNT_SETTLE_TIME)
		if not basket.Parent
			or not bottom.Parent
			or not target.Parent
			or not orientationTarget.Parent
		then
			return
		end

		basket:SetAttribute(MOUNT_READY_ATTRIBUTE, true)
		print(
			"[BasketPhysics] HandFollowerReady",
			"positionDriver=RightHand",
			"levelOrientationDriver=HumanoidRootPart",
			"separateAssembly=true",
			"jumpVelocitySeeded=true"
		)

		local function cleanUpTarget()
			if target.Parent then
				target:Destroy()
			end
			if orientationTarget.Parent then
				orientationTarget:Destroy()
			end
		end
		basket.Destroying:Once(cleanUpTarget)
		character.Destroying:Once(cleanUpTarget)
	end)
end

-- Eggs are independent Workspace assemblies. Preserve only the eggs which the
-- authoritative break service still considers inside after the dropped basket
-- has settled. Keep those survivors anchored and follow the moving basket by
-- CFrame during pickup. A physical weld here would merge every surviving egg
-- into the hand/character assembly and can feed a large impulse back into the
-- player when the temporary pickup grip is released. Eggs which already spilled
-- retain HasLeftBasket=true and are never captured here.
local releaseSecuredPickupEggs: (Player, BasePart?, string) -> number = function()
	return 0
end

local function secureSurvivingEggsForPickup(
	player: Player,
	basket: Model,
	bottom: BasePart
): number
	local securedCount = 0
	for _, candidate in Workspace:GetChildren() do
		if candidate:IsA("Model")
			and candidate:GetAttribute(LIVE_EGG_ATTRIBUTE) == true
			and candidate:GetAttribute(BASKET_OWNER_ATTRIBUTE) == player.UserId
			and candidate:GetAttribute(IN_BASKET_ATTRIBUTE) == true
			and candidate:GetAttribute(HAS_LEFT_BASKET_ATTRIBUTE) ~= true
		then
			local collider = candidate:FindFirstChild("Collider")
			if collider and collider:IsA("BasePart") then
				candidate:SetAttribute(
					PICKUP_EGG_LOCAL_PIVOT_ATTRIBUTE,
					bottom.CFrame:ToObjectSpace(candidate:GetPivot())
				)
				candidate:SetAttribute(
					PICKUP_EGG_ORIGINAL_ANCHORED_ATTRIBUTE,
					collider.Anchored
				)
				candidate:SetAttribute(
					PICKUP_EGG_ORIGINAL_MASSLESS_ATTRIBUTE,
					collider.Massless
				)
				candidate:SetAttribute(
					PICKUP_EGG_ORIGINAL_CAN_COLLIDE_ATTRIBUTE,
					collider.CanCollide
				)
				candidate:SetAttribute(
					PICKUP_EGG_ORIGINAL_CAN_TOUCH_ATTRIBUTE,
					collider.CanTouch
				)
				collider.Anchored = true
				collider.Massless = true
				collider.CanCollide = false
				collider.CanTouch = false
				candidate:SetAttribute(PICKUP_SECURED_EGG_ATTRIBUTE, true)
				securedCount += 1
			end
		end
	end
	if securedCount > 0 then
		print(string.format(
			"[BasketRecovery] secured surviving eggs count=%d basket=%s",
			securedCount,
			basket.Name
		))
		basket.Destroying:Once(function()
			releaseSecuredPickupEggs(player, bottom, "basketDestroy")
		end)
		task.spawn(function()
			while basket.Parent and bottom.Parent do
				RunService.Heartbeat:Wait()
				if not basket.Parent or not bottom.Parent then
					break
				end

				local followedCount = 0
				for _, candidate in Workspace:GetChildren() do
					if candidate:IsA("Model")
						and candidate:GetAttribute(LIVE_EGG_ATTRIBUTE) == true
						and candidate:GetAttribute(BASKET_OWNER_ATTRIBUTE) == player.UserId
						and candidate:GetAttribute(PICKUP_SECURED_EGG_ATTRIBUTE) == true
					then
						local localPivot = candidate:GetAttribute(
							PICKUP_EGG_LOCAL_PIVOT_ATTRIBUTE
						)
						if typeof(localPivot) == "CFrame" then
							candidate:PivotTo(bottom.CFrame * localPivot)
							followedCount += 1
						end
					end
				end
				if followedCount == 0 then
					break
				end
			end
		end)
	end
	return securedCount
end

releaseSecuredPickupEggs = function(
	player: Player,
	bottom: BasePart?,
	reason: string
): number
	local releasedCount = 0
	for _, candidate in Workspace:GetChildren() do
		if candidate:IsA("Model")
			and candidate:GetAttribute(LIVE_EGG_ATTRIBUTE) == true
			and candidate:GetAttribute(BASKET_OWNER_ATTRIBUTE) == player.UserId
			and candidate:GetAttribute(PICKUP_SECURED_EGG_ATTRIBUTE) == true
		then
			local collider = candidate:FindFirstChild("Collider")
			if collider and collider:IsA("BasePart") then
				local localPivot = candidate:GetAttribute(PICKUP_EGG_LOCAL_PIVOT_ATTRIBUTE)
				if bottom and bottom.Parent and typeof(localPivot) == "CFrame" then
					candidate:PivotTo(bottom.CFrame * localPivot)
				end
				local originalAnchored = candidate:GetAttribute(
					PICKUP_EGG_ORIGINAL_ANCHORED_ATTRIBUTE
				)
				local originalMassless = candidate:GetAttribute(
					PICKUP_EGG_ORIGINAL_MASSLESS_ATTRIBUTE
				)
				local originalCanCollide = candidate:GetAttribute(
					PICKUP_EGG_ORIGINAL_CAN_COLLIDE_ATTRIBUTE
				)
				local originalCanTouch = candidate:GetAttribute(
					PICKUP_EGG_ORIGINAL_CAN_TOUCH_ATTRIBUTE
				)
				collider.Massless = if typeof(originalMassless) == "boolean"
					then originalMassless
					else false
				collider.CanCollide = if typeof(originalCanCollide) == "boolean"
					then originalCanCollide
					else true
				collider.CanTouch = if typeof(originalCanTouch) == "boolean"
					then originalCanTouch
					else true
				collider.Anchored = if typeof(originalAnchored) == "boolean"
					then originalAnchored
					else false
				-- Never inherit the temporary overhead mount's instantaneous velocity.
				-- It can be very large while constraints settle and was the source of
				-- the post-pickup character/basket launch. The eggs resume as their own
				-- assemblies and settle normally inside the restored collision shell.
				if not collider.Anchored then
					collider.AssemblyLinearVelocity = Vector3.zero
					collider.AssemblyAngularVelocity = Vector3.zero
				end
			end
			candidate:SetAttribute(PICKUP_SECURED_EGG_ATTRIBUTE, nil)
			candidate:SetAttribute(PICKUP_EGG_LOCAL_PIVOT_ATTRIBUTE, nil)
			candidate:SetAttribute(PICKUP_EGG_ORIGINAL_ANCHORED_ATTRIBUTE, nil)
			candidate:SetAttribute(PICKUP_EGG_ORIGINAL_MASSLESS_ATTRIBUTE, nil)
			candidate:SetAttribute(PICKUP_EGG_ORIGINAL_CAN_COLLIDE_ATTRIBUTE, nil)
			candidate:SetAttribute(PICKUP_EGG_ORIGINAL_CAN_TOUCH_ATTRIBUTE, nil)
			releasedCount += 1
		end
	end
	if releasedCount > 0 then
		print(string.format(
			"[BasketRecovery] released surviving eggs count=%d reason=%s",
			releasedCount,
			reason
		))
	end
	return releasedCount
end

local function restoreRecoveredBasketEggCollision(basket: Model): boolean
	local shell = basket:FindFirstChild(EGG_COLLISION_SHELL_NAME)
	if not shell or not shell:IsA("Model") then
		warn("[BasketRecovery] recovered basket is missing EggCollisionShell")
		return false
	end
	local restoredParts = 0
	for _, descendant in shell:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = true
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			-- Reparenting the model as "BasketPickup" temporarily puts it under
			-- the character before it is renamed to "Basket". The character's
			-- DescendantAdded collision-group hook therefore classifies these shell
			-- parts as Characters. If that classification survives completion, the
			-- rigid follower continuously drives the shell into the avatar and the
			-- resulting collision launches the player while holding the basket away
			-- from the hands. Restore the shell's authored non-character group.
			descendant.CollisionGroup = EGG_BASKET_COLLISION_GROUP
			restoredParts += 1
		end
	end
	if restoredParts == 0 then
		warn("[BasketRecovery] EggCollisionShell had no physical parts")
		return false
	end
	return true
end

-- Reuses the normal carried-basket follower for the *same* Model that was
-- released during FallBackLeft. Unlike attachBasket, this never constructs or
-- clones a basket. The one allowed correction happens only after the pickup
-- animation has already lifted the basket into the overhead region.
local function mountRecoveredBasketOverhead(character: Model, basket: Model): boolean
	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	local rightHand = character:FindFirstChild("RightHand")
	local bottom = basket:FindFirstChild("Bottom")
	if not player
		or not humanoid
		or not head
		or not head:IsA("BasePart")
		or not root
		or not root:IsA("BasePart")
		or not rightHand
		or not rightHand:IsA("BasePart")
		or not bottom
		or not bottom:IsA("BasePart")
	then
		return false
	end
	if basket:GetAttribute(BASKET_OWNER_ATTRIBUTE) ~= player.UserId then
		return false
	end

	destroyNamedDescendants(basket, {
		[BASKET_TEMPORARY_GRIP_NAME] = true,
		["BasketTemporaryGrip"] = true,
		["BasketPickupHelper"] = true,
		["BasketRecoveryOrientation"] = true,
		["BasketAlignPosition"] = true,
		["BasketAlignOrientation"] = true,
		["BasketBootstrapWeld"] = true,
		[BASKET_ATTACHMENT_NAME] = true,
	})
	removeOldBasketTarget(character)

	-- Restore the exact normal carry mount captured before the fall. Never
	-- derive this from the animated Head/hand pose: doing so captured the
	-- BasketPickup bend and left the recovered basket vertical behind the head.
	local savedCarryMount = basket:GetAttribute(BASKET_CARRY_MOUNT_ATTRIBUTE)
	local desiredBottomCFrame = if typeof(savedCarryMount) == "CFrame"
		then root.CFrame * savedCarryMount
		else CFrame.new(head.Position)
			* root.CFrame.Rotation
			* CFrame.new(BASKET_OFFSET.Position)
			* BASKET_OFFSET.Rotation
	local bottomToPivot = bottom.CFrame:ToObjectSpace(basket:GetPivot())
	local basketPhysicalMass = getBasketPhysicalMass(basket)
	basket.Name = BASKET_NAME
	basket.Parent = character
	basket:PivotTo(desiredBottomCFrame * bottomToPivot)
	basket:SetAttribute(MOUNT_READY_ATTRIBUTE, false)
	basket:SetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE, "Overhead")
	sanitizeCarriedBasketPhysics(basket)
	removeArmIKControls(humanoid)

	-- Establish the one normal follower synchronously. The earlier asynchronous
	-- bootstrap weld could overlap PickupComplete and leave two attachment modes
	-- alive while animation ownership was changing.
	local target = Instance.new("Attachment")
	target.Name = BASKET_TARGET_NAME
	-- Once pickup has reached Overhead, restore the pre-fall root-local mount
	-- directly. A target parented to the pickup hand followed the hand downward
	-- during the Pickup -> BasketHold blend and covered the avatar's face.
	target.CFrame = if typeof(savedCarryMount) == "CFrame"
		then savedCarryMount
		else root.CFrame:ToObjectSpace(bottom.CFrame)
	target.Parent = root

	local orientationTarget = Instance.new("Attachment")
	orientationTarget.Name = BASKET_ORIENTATION_TARGET_NAME
	local savedOrientationTarget = basket:GetAttribute(BASKET_CARRY_ORIENTATION_TARGET_ATTRIBUTE)
	orientationTarget.CFrame = if typeof(savedOrientationTarget) == "CFrame"
		then savedOrientationTarget
		else root.CFrame:ToObjectSpace(bottom.CFrame)
	orientationTarget.Parent = root

	local basketAttachment = Instance.new("Attachment")
	basketAttachment.Name = BASKET_ATTACHMENT_NAME
	basketAttachment.CFrame = CFrame.identity
	basketAttachment.Parent = bottom

	-- Capture the physical part-mass sum before making the whole carried model
	-- Massless so the follower limits remain calibrated to the real basket.
	local basketMass = basketPhysicalMass
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "BasketAlignPosition"
	alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
	alignPosition.Attachment0 = basketAttachment
	alignPosition.Attachment1 = target
	alignPosition.RigidityEnabled = true
	alignPosition.ReactionForceEnabled = false
	alignPosition.ApplyAtCenterOfMass = false
	alignPosition.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	alignPosition.ForceRelativeTo = Enum.ActuatorRelativeTo.World
	alignPosition.MaxAxesForce = Vector3.new(
		basketMass * HORIZONTAL_MAX_FORCE_PER_MASS,
		basketMass * VERTICAL_MAX_FORCE_PER_MASS,
		basketMass * HORIZONTAL_MAX_FORCE_PER_MASS
	)
	alignPosition.MaxVelocity = POSITION_MAX_VELOCITY
	alignPosition.Responsiveness = POSITION_RESPONSIVENESS
	alignPosition.Parent = bottom

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "BasketAlignOrientation"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	alignOrientation.Attachment0 = basketAttachment
	alignOrientation.Attachment1 = orientationTarget
	alignOrientation.RigidityEnabled = true
	alignOrientation.ReactionTorqueEnabled = false
	alignOrientation.MaxTorque = basketMass * ORIENTATION_MAX_TORQUE_PER_MASS
	alignOrientation.Responsiveness = ORIENTATION_RESPONSIVENESS
	alignOrientation.Parent = bottom

	local temporaryGripCount = countNamedDescendants(character, BASKET_TEMPORARY_GRIP_NAME)
	local overheadAttachmentCount = countNamedDescendants(character, BASKET_ATTACHMENT_NAME)
	if temporaryGripCount ~= 0 or overheadAttachmentCount ~= 1 then
		warn(string.format(
			"[BasketRecovery] invalid overhead transfer tempGrips=%d overheadAttachments=%d",
			temporaryGripCount,
			overheadAttachmentCount
		))
		return false
	end

	local canSetOwnership = bottom:CanSetNetworkOwnership()
	if canSetOwnership then
		pcall(function()
			bottom:SetNetworkOwner(player)
		end)
	end
	basket:SetAttribute(MOUNT_READY_ATTRIBUTE, true)

	local function cleanUpTarget()
		if target.Parent then
			target:Destroy()
		end
		if orientationTarget.Parent then
			orientationTarget:Destroy()
		end
	end
	basket.Destroying:Once(cleanUpTarget)
	character.Destroying:Once(cleanUpTarget)
	return true
end

local function temporarilyIgnoreFallingCharacterCollision(
	basketBottom: BasePart,
	character: Model
)
	local oldConstraints = basketBottom:FindFirstChild("FallCharacterNoCollision")
	if oldConstraints then
		oldConstraints:Destroy()
	end

	local constraints = Instance.new("Folder")
	constraints.Name = "FallCharacterNoCollision"
	constraints.Parent = basketBottom

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			local noCollision = Instance.new("NoCollisionConstraint")
			noCollision.Name = "BasketCharacterSeparation"
			noCollision.Part0 = basketBottom
			noCollision.Part1 = descendant
			noCollision.Parent = constraints
		end
	end

	-- The released basket passes cleanly away from the collapsing avatar.
	-- Removing these constraints restores the exact pre-existing
	-- basket/character collision behavior after the separation window.
	task.delay(FALL_CHARACTER_COLLISION_IGNORE_DURATION, function()
		if constraints.Parent then
			constraints:Destroy()
		end
	end)
end

local function releaseBasketForFall(player: Player, requestedSide: any): Model?
	local fallSide = if requestedSide == "Right"
		then "Right"
		elseif requestedSide == "Back"
		then "Back"
		else "Left"
	local character = player.Character
	if not character then
		return nil
	end
	if character:GetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE) == true then
		local existingDroppedBasket = Workspace:FindFirstChild(string.format(
			"DroppedBasket_%d",
			player.UserId
		))
		return if existingDroppedBasket and existingDroppedBasket:IsA("Model")
			then existingDroppedBasket
			else nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local basket = character:FindFirstChild(BASKET_NAME)
	if not humanoid
		or not basket
		or not basket:IsA("Model")
	then
		return nil
	end
	local bottom = basket:FindFirstChild("Bottom")
	if not bottom or not bottom:IsA("BasePart") then
		return nil
	end

	-- Capture the assembly motion before removing its followers, then retain a
	-- bounded portion of forward momentum plus the authored lateral release.
	-- This keeps the physical throw readable without inheriting unlimited sprint
	-- or vertical velocity.
	local preservedLinearVelocity = bottom.AssemblyLinearVelocity
	local preservedAngularVelocity = bottom.AssemblyAngularVelocity
	local preservedHorizontal = Vector3.new(
		preservedLinearVelocity.X,
		0,
		preservedLinearVelocity.Z
	)
	local releasedHorizontal = preservedHorizontal * FALL_BASKET_FORWARD_INHERITANCE
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		if typeof(basket:GetAttribute(BASKET_CARRY_MOUNT_ATTRIBUTE)) ~= "CFrame" then
			basket:SetAttribute(
				BASKET_CARRY_MOUNT_ATTRIBUTE,
				root.CFrame:ToObjectSpace(bottom.CFrame)
			)
		end
		local carryPositionTarget = character:FindFirstChild(BASKET_TARGET_NAME, true)
		if carryPositionTarget and carryPositionTarget:IsA("Attachment") then
			basket:SetAttribute(
				BASKET_CARRY_POSITION_TARGET_ATTRIBUTE,
				carryPositionTarget.CFrame
			)
		end
		local carryOrientationTarget = root:FindFirstChild(BASKET_ORIENTATION_TARGET_NAME)
		if carryOrientationTarget and carryOrientationTarget:IsA("Attachment") then
			basket:SetAttribute(
				BASKET_CARRY_ORIENTATION_TARGET_ATTRIBUTE,
				carryOrientationTarget.CFrame
			)
		end
		local right = root.CFrame.RightVector
		local flatSide = Vector3.new(right.X, 0, right.Z)
		if fallSide ~= "Back" and flatSide.Magnitude > 0.001 then
			local sideDirection = flatSide.Unit
			if fallSide == "Left" then
				sideDirection = -sideDirection
			end
			releasedHorizontal += sideDirection * FALL_BASKET_SIDE_SPEED
		end
	end
	if releasedHorizontal.Magnitude < 0.001 then
		if fallSide == "Back" and root and root:IsA("BasePart") then
			local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			releasedHorizontal = if forward.Magnitude > 0.001
				then forward.Unit * FALL_BASKET_MIN_HORIZONTAL_SPEED
				else Vector3.zAxis * FALL_BASKET_MIN_HORIZONTAL_SPEED
		else
			local fallbackSign = if fallSide == "Right" then 1 else -1
			releasedHorizontal = Vector3.new(fallbackSign, 0, 0)
				* FALL_BASKET_MIN_HORIZONTAL_SPEED
		end
	else
		releasedHorizontal = releasedHorizontal.Unit * math.clamp(
			releasedHorizontal.Magnitude,
			FALL_BASKET_MIN_HORIZONTAL_SPEED,
			FALL_BASKET_MAX_HORIZONTAL_SPEED
		)
	end
	local releasedLinearVelocity = releasedHorizontal + Vector3.yAxis * math.clamp(
		preservedLinearVelocity.Y,
		FALL_BASKET_MIN_UPWARD_SPEED,
		FALL_BASKET_MAX_UPWARD_SPEED
	)

	character:SetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE, true)
	basket:SetAttribute(MOUNT_READY_ATTRIBUTE, false)
	basket:SetAttribute(BASKET_OWNER_ATTRIBUTE, player.UserId)
	basket:SetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE, "Dropped")
	stopBasketHoldAnimation(character)
	removeArmIKControls(humanoid)

	for _, constraintName in {
		"BasketAlignPosition",
		"BasketAlignOrientation",
		"BasketBootstrapWeld",
	} do
		local constraint = bottom:FindFirstChild(constraintName)
		if constraint then
			constraint:Destroy()
		end
	end
	removeOldBasketTarget(character)

	basket.Name = string.format("DroppedBasket_%d", player.UserId)
	basket.Parent = Workspace
	bottom.Massless = false
	bottom.CanCollide = true
	bottom.CanTouch = true
	bottom.CanQuery = true
	temporarilyIgnoreFallingCharacterCollision(bottom, character)
	bottom.AssemblyLinearVelocity = releasedLinearVelocity
	local releaseSpin = FALL_BASKET_RELEASE_SPIN
	if fallSide == "Right" then
		-- Angular velocity is an axial vector: a left/right spatial mirror keeps
		-- the lateral component and reverses the other two components.
		releaseSpin = Vector3.new(releaseSpin.X, -releaseSpin.Y, -releaseSpin.Z)
	end
	bottom.AssemblyAngularVelocity = preservedAngularVelocity + releaseSpin

	local canSetOwnership = bottom:CanSetNetworkOwnership()
	if canSetOwnership then
		pcall(function()
			bottom:SetNetworkOwner(player)
		end)
	end
	character.Destroying:Once(function()
		if basket.Parent then
			basket:Destroy()
		end
	end)
	return basket
end

local function getOwnedRecoveryBasket(player: Player, candidate: any): Model?
	if typeof(candidate) ~= "Instance" or not candidate:IsA("Model") then
		return nil
	end
	if candidate:GetAttribute(BASKET_OWNER_ATTRIBUTE) ~= player.UserId then
		return nil
	end
	local character = player.Character
	if not character or character:GetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE) ~= true then
		return nil
	end
	local expectedName = string.format("DroppedBasket_%d", player.UserId)
	local isDropped = candidate.Parent == Workspace and candidate.Name == expectedName
	local isInPickup = candidate.Parent == character
		and (candidate.Name == "BasketPickup" or candidate.Name == BASKET_NAME)
	return if isDropped or isInPickup then candidate else nil
end

local function getCurrentRecoveryBasket(player: Player): Model?
	local character = player.Character
	if character then
		for _, name in { "BasketPickup", BASKET_NAME } do
			local candidate = character:FindFirstChild(name)
			if candidate and candidate:IsA("Model")
				and candidate:GetAttribute(BASKET_OWNER_ATTRIBUTE) == player.UserId
				and character:GetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE) == true
			then
				return candidate
			end
		end
	end
	local candidate = Workspace:FindFirstChild(string.format(
		"DroppedBasket_%d",
		player.UserId
	))
	return getOwnedRecoveryBasket(player, candidate)
end

local function attachDroppedBasketToPickupGrip(player: Player, candidate: any): boolean
	local character = player.Character
	local basket = getOwnedRecoveryBasket(player, candidate)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rightHand = character and character:FindFirstChild("RightHand")
	local bottom = basket and basket:FindFirstChild("Bottom")
	if not character
		or not basket
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
		or not rightHand
		or not rightHand:IsA("BasePart")
		or not bottom
		or not bottom:IsA("BasePart")
		or basket:GetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE) ~= "Dropped"
	then
		return false
	end
	local pickupOffset = bottom.Position - root.Position
	local horizontalPickupDistance = Vector3.new(pickupOffset.X, 0, pickupOffset.Z).Magnitude
	if horizontalPickupDistance > BASKET_PICKUP_MAX_DISTANCE then
		return false
	end

	secureSurvivingEggsForPickup(player, basket, bottom)
	sanitizeCarriedBasketPhysics(basket)
	local separationConstraints = bottom:FindFirstChild("FallCharacterNoCollision")
	if separationConstraints then
		separationConstraints:Destroy()
	end

	-- Reparenting preserves every part's world transform. WeldConstraint then
	-- captures the current hand-to-basket local offset, so GrabBasket has no
	-- visible teleport and the animated right hand carries the same assembly.
	basket.Name = "BasketPickup"
	basket.Parent = character
	destroyNamedDescendants(basket, {
		[BASKET_TEMPORARY_GRIP_NAME] = true,
		["BasketTemporaryGrip"] = true,
		["BasketPickupHelper"] = true,
	})
	local grip = Instance.new("WeldConstraint")
	grip.Name = BASKET_TEMPORARY_GRIP_NAME
	grip.Part0 = rightHand
	grip.Part1 = bottom
	grip.Parent = bottom
	basket:SetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE, "Hand")
	local gripCount = countNamedDescendants(basket, BASKET_TEMPORARY_GRIP_NAME)
	if gripCount ~= 1 then
		warn(string.format("[BasketRecovery] expected one temporary grip, found %d", gripCount))
		releaseSecuredPickupEggs(player, bottom, "gripFailure")
		return false
	end
	return true
end

local function transferPickedBasketOverhead(player: Player, candidate: any): boolean
	local character = player.Character
	local basket = getOwnedRecoveryBasket(player, candidate)
	if not character
		or not basket
		or basket:GetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE) ~= "Hand"
	then
		return false
	end
	return mountRecoveredBasketOverhead(character, basket)
end

local function completeBasketPickup(player: Player, candidate: any): boolean
	local character = player.Character
	local basket = getOwnedRecoveryBasket(player, candidate)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rightHand = character and character:FindFirstChild("RightHand")
	local positionTarget = character and character:FindFirstChild(BASKET_TARGET_NAME, true)
	if not character
		or not basket
		or not humanoid
		or humanoid.Health <= 0
		or not rightHand
		or not rightHand:IsA("BasePart")
		or not positionTarget
		or not positionTarget:IsA("Attachment")
		or basket.Parent ~= character
		or basket.Name ~= BASKET_NAME
		or basket:GetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE) ~= "Overhead"
	then
		return false
	end

	sanitizeCarriedBasketPhysics(basket)
	playBasketHoldAnimation(character, humanoid, basket, 0.08)

	-- Overhead pickup temporarily positions the basket from HumanoidRootPart so
	-- the fading pickup pose cannot drag it across the avatar's face. At this
	-- point the pickup track has ended and BasketHold owns the arms, so restore
	-- the exact original RightHand-local target captured before the fall. Keep
	-- BasketOrientationTarget on HumanoidRootPart: position follows the animated
	-- hand again while the basket remains level like the original carry system.
	local savedHandTarget = basket:GetAttribute(BASKET_CARRY_POSITION_TARGET_ATTRIBUTE)
	local bottom = basket:FindFirstChild("Bottom")
	positionTarget.CFrame = if typeof(savedHandTarget) == "CFrame"
		then savedHandTarget
		elseif bottom and bottom:IsA("BasePart")
		then rightHand.CFrame:ToObjectSpace(bottom.CFrame)
		else CFrame.identity
	positionTarget.Parent = rightHand

	-- The overhead phase deliberately follows a root-local target. Reparenting
	-- that target to the animated hand changes its world position immediately,
	-- but the physical basket can otherwise spend several frames chasing it.
	-- Place the recovered basket at the two active targets once, then let the
	-- existing AlignPosition/AlignOrientation follower resume normal hand-driven
	-- motion. This is a position correction only; no velocity is added.
	local orientationTarget = character:FindFirstChild(BASKET_ORIENTATION_TARGET_NAME, true)
	if bottom and bottom:IsA("BasePart") then
		local desiredRotation = if orientationTarget
			and orientationTarget:IsA("Attachment")
			then orientationTarget.WorldCFrame.Rotation
			else bottom.CFrame.Rotation
		local desiredBottom = CFrame.new(positionTarget.WorldPosition) * desiredRotation
		local bottomToPivot = bottom.CFrame:ToObjectSpace(basket:GetPivot())
		basket:PivotTo(desiredBottom * bottomToPivot)
		bottom.AssemblyLinearVelocity = Vector3.zero
		bottom.AssemblyAngularVelocity = Vector3.zero
	end

	basket:SetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE, "Carried")
	character:SetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE, false)
	restoreRecoveredBasketEggCollision(basket)
	releaseSecuredPickupEggs(
		player,
		if bottom and bottom:IsA("BasePart") then bottom else nil,
		"pickupComplete"
	)
	return true
end

local function getBasketRecoveryDebugSnapshot(player: Player): { [string]: any }
	local character = player.Character
	local basket = character and character:FindFirstChild(BASKET_NAME)
	local basketAngularSpeed = 0
	local carriedPhysicsInvalid = false
	local mountPositionError = -1
	local mountAngleError = -1
	if basket and basket:IsA("Model") then
		local eggCollisionShell = basket:FindFirstChild(EGG_COLLISION_SHELL_NAME)
		for _, descendant in basket:GetDescendants() do
			if descendant:IsA("BasePart") then
				basketAngularSpeed = math.max(
					basketAngularSpeed,
					descendant.AssemblyAngularVelocity.Magnitude
				)
				local isExpectedEggCollider = eggCollisionShell ~= nil
					and descendant:IsDescendantOf(eggCollisionShell)
				if (descendant.CanCollide and not isExpectedEggCollider)
					or not descendant.Massless
				then
					carriedPhysicsInvalid = true
				end
			end
		end
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local positionTarget = character and character:FindFirstChild(BASKET_TARGET_NAME, true)
		local bottom = basket:FindFirstChild("Bottom")
		local savedOrientationTarget = basket:GetAttribute(BASKET_CARRY_ORIENTATION_TARGET_ATTRIBUTE)
		if root and root:IsA("BasePart")
			and positionTarget and positionTarget:IsA("Attachment")
			and bottom and bottom:IsA("BasePart")
		then
			mountPositionError = (bottom.Position - positionTarget.WorldPosition).Magnitude
			local expectedOrientation = if typeof(savedOrientationTarget) == "CFrame"
				then root.CFrame * savedOrientationTarget
				else root.CFrame
			local _, angle = (expectedOrientation.Rotation:ToObjectSpace(bottom.CFrame.Rotation)):ToAxisAngle()
			mountAngleError = math.deg(math.abs(angle))
		end
	end
	local holdState = character and activeBasketHolds[character] or nil
	return {
		tempGrips = if character then countNamedDescendants(character, BASKET_TEMPORARY_GRIP_NAME) else 0,
		overheadAttachments = if character then countNamedDescendants(character, BASKET_ATTACHMENT_NAME) else 0,
		alignPositions = if character then countNamedDescendants(character, "BasketAlignPosition") else 0,
		alignOrientations = if character then countNamedDescendants(character, "BasketAlignOrientation") else 0,
		basketAngularSpeed = basketAngularSpeed,
		carriedPhysicsInvalid = carriedPhysicsInvalid,
		mountPositionError = mountPositionError,
		mountAngleError = mountAngleError,
		holdPlaying = holdState ~= nil and holdState.track.IsPlaying,
	}
end

local function emergencyRepositionRecoveryBasket(
	player: Player,
	candidate: any,
	reason: string
): Model?
	local character = player.Character
	local basket = getOwnedRecoveryBasket(player, candidate)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bottom = basket and basket:FindFirstChild("Bottom")
	if not character
		or not basket
		or basket.Parent ~= Workspace
		or basket:GetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE) ~= "Dropped"
		or not root
		or not root:IsA("BasePart")
		or not bottom
		or not bottom:IsA("BasePart")
	then
		return nil
	end

	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatLook.Magnitude < 0.001 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end
	local desiredHorizontal = root.Position + flatLook * BASKET_EMERGENCY_FORWARD_DISTANCE
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, basket }
	raycastParams.IgnoreWater = false
	raycastParams.RespectCanCollide = true
	local result = Workspace:Raycast(
		desiredHorizontal + Vector3.new(0, 8, 0),
		Vector3.new(0, -24, 0),
		raycastParams
	)
	if not result or not result.Instance.CanCollide then
		return nil
	end

	local bottomToPivot = bottom.CFrame:ToObjectSpace(basket:GetPivot())
	local desiredBottom = CFrame.new(
		result.Position + Vector3.new(0, bottom.Size.Y * 0.5 + 0.08, 0)
	)
	basket:PivotTo(desiredBottom * bottomToPivot)
	bottom.AssemblyLinearVelocity = Vector3.new(0, -1, 0)
	bottom.AssemblyAngularVelocity = Vector3.zero
	warn(string.format("[BasketRecovery] emergency reposition reason=%s", reason))
	return basket
end

local function restoreBasketAfterFallTest(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or not character.Parent then
		return false
	end

	local droppedBasket = Workspace:FindFirstChild(string.format(
		"DroppedBasket_%d",
		player.UserId
	))
	if droppedBasket then
		local droppedBottom = droppedBasket:FindFirstChild("Bottom")
		releaseSecuredPickupEggs(
			player,
			if droppedBottom and droppedBottom:IsA("BasePart") then droppedBottom else nil,
			"restoreDropped"
		)
		droppedBasket:Destroy()
	end
	local pickupBasket = character:FindFirstChild("BasketPickup")
	if pickupBasket then
		local pickupBottom = pickupBasket:FindFirstChild("Bottom")
		releaseSecuredPickupEggs(
			player,
			if pickupBottom and pickupBottom:IsA("BasePart") then pickupBottom else nil,
			"restorePickup"
		)
		pickupBasket:Destroy()
	end
	local recoveredBasket = character:FindFirstChild(BASKET_NAME)
	if recoveredBasket
		and recoveredBasket:IsA("Model")
		and recoveredBasket:GetAttribute(BASKET_PICKUP_STAGE_ATTRIBUTE) ~= "Carried"
	then
		local recoveredBottom = recoveredBasket:FindFirstChild("Bottom")
		releaseSecuredPickupEggs(
			player,
			if recoveredBottom and recoveredBottom:IsA("BasePart") then recoveredBottom else nil,
			"restoreOverhead"
		)
		recoveredBasket:Destroy()
	end
	character:SetAttribute(FALL_BASKET_RELEASED_ATTRIBUTE, false)
	task.spawn(function()
		if player.Character == character and character.Parent and humanoid.Health > 0 then
			attachBasket(character)
		end
	end)
	return true
end

local fallBasketReleaseRemote: RemoteEvent? = nil
if RunService:IsStudio() then
	local existingRemote = ReplicatedStorage:FindFirstChild(FALL_BASKET_RELEASE_REMOTE_NAME)
	if existingRemote and existingRemote:IsA("RemoteEvent") then
		fallBasketReleaseRemote = existingRemote
	else
		if existingRemote then
			existingRemote:Destroy()
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = FALL_BASKET_RELEASE_REMOTE_NAME
		remote.Parent = ReplicatedStorage
		fallBasketReleaseRemote = remote
	end
	(fallBasketReleaseRemote :: RemoteEvent).OnServerEvent:Connect(function(player)
		releaseBasketForFall(player, "Left")
	end)
end

-- Reversible request shared by the directional and straight-back fall integrations.
-- "Release" preserves current motion plus the bounded lateral separation
-- component; "Restore" is cleanup for a disabled/destroyed client test while
-- the same living character remains.
local existingFallRequest = ReplicatedStorage:FindFirstChild(FALL_BASKET_RELEASE_REQUEST_NAME)
local fallBasketReleaseRequest: RemoteFunction
if existingFallRequest and existingFallRequest:IsA("RemoteFunction") then
	fallBasketReleaseRequest = existingFallRequest
else
	if existingFallRequest then
		existingFallRequest:Destroy()
	end
	fallBasketReleaseRequest = Instance.new("RemoteFunction")
	fallBasketReleaseRequest.Name = FALL_BASKET_RELEASE_REQUEST_NAME
	fallBasketReleaseRequest.Parent = ReplicatedStorage
end
fallBasketReleaseRequest.OnServerInvoke = function(
	player: Player,
	action: string,
	candidate: any,
	reason: any
): any
	if action == "Release" then
		return releaseBasketForFall(player, candidate)
	elseif action == "Restore" then
		return restoreBasketAfterFallTest(player)
	elseif action == "GetDropped" then
		return getCurrentRecoveryBasket(player)
	elseif action == "Grab" then
		return attachDroppedBasketToPickupGrip(player, candidate)
	elseif action == "Overhead" then
		return transferPickedBasketOverhead(player, candidate)
	elseif action == "Complete" then
		return completeBasketPickup(player, candidate)
	elseif action == "DebugSnapshot" then
		return getBasketRecoveryDebugSnapshot(player)
	elseif action == "EmergencyReposition" then
		return emergencyRepositionRecoveryBasket(
			player,
			candidate,
			if typeof(reason) == "string" then reason else "unknown"
		)
	end
	return false
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(attachBasket)

	if player.Character then
		task.spawn(attachBasket, player.Character)
	end
end

-- Consume the FBX import as a template before any character can spawn on it.
-- Only the carried runtime clone is allowed to remain in Workspace.
local startupTemplate = findImportedVisualTemplate()
if not startupTemplate then
	warn("BasketAttachmentService: no imported basket template was found at startup")
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
