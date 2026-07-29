--!strict

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BrokenEggService = {}

local BROKEN_EGG_LIFETIME = 15
local SPREAD_OUT_DURATION = 0.18
local SPREAD_SETTLE_DURATION = 0.08
local YOLK_DELAY = 0.035
local SHELL_SPREAD_DURATION = 0.22
local FADE_DURATION = 0.3
local SURFACE_OFFSET = 0.012

local WHITE_COLOR = Color3.fromRGB(255, 248, 221)
local YOLK_COLOR = Color3.fromRGB(245, 158, 35)
local SHELL_COLOR = Color3.fromRGB(255, 241, 205)

local random = Random.new()

type WhiteDefinition = {
	name: string,
	size: Vector3,
	position: Vector3,
	rotationDegrees: number,
	transparency: number,
}

type ShellDefinition = {
	name: string,
	size: Vector3,
	position: Vector3,
	rotation: Vector3,
}

local WHITE_DEFINITIONS: { WhiteDefinition } = {
	{
		name = "WhiteCenter",
		size = Vector3.new(1.55, 0.040, 1.05),
		position = Vector3.new(0, 0.020, 0),
		rotationDegrees = -7,
		transparency = 0.16,
	},
	{
		name = "WhiteLobe_01",
		size = Vector3.new(1.05, 0.034, 0.75),
		position = Vector3.new(0.63, 0.017, 0.05),
		rotationDegrees = 17,
		transparency = 0.18,
	},
	{
		name = "WhiteLobe_02",
		size = Vector3.new(0.95, 0.030, 0.70),
		position = Vector3.new(-0.60, 0.015, -0.10),
		rotationDegrees = -24,
		transparency = 0.20,
	},
	{
		name = "WhiteLobe_03",
		size = Vector3.new(1.05, 0.032, 0.67),
		position = Vector3.new(0.12, 0.016, 0.51),
		rotationDegrees = 8,
		transparency = 0.19,
	},
	{
		name = "WhiteLobe_04",
		size = Vector3.new(0.90, 0.028, 0.72),
		position = Vector3.new(-0.20, 0.014, -0.50),
		rotationDegrees = 31,
		transparency = 0.21,
	},
}

local SHELL_DEFINITIONS: { ShellDefinition } = {
	{
		name = "Shell_01",
		size = Vector3.new(0.30, 0.08, 0.23),
		position = Vector3.new(0.78, 0.075, 0.26),
		rotation = Vector3.new(-12, 38, 9),
	},
	{
		name = "Shell_02",
		size = Vector3.new(0.22, 0.06, 0.18),
		position = Vector3.new(-0.91, 0.060, 0.14),
		rotation = Vector3.new(8, -54, -6),
	},
	{
		name = "Shell_03",
		size = Vector3.new(0.28, 0.07, 0.17),
		position = Vector3.new(0.31, 0.065, -0.73),
		rotation = Vector3.new(-7, 112, 13),
	},
}

local function getBrokenEggFolder(): Folder
	for _, child in Workspace:GetChildren() do
		if child.Name == "BrokenEggs" and child:IsA("Folder") then
			return child
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "BrokenEggs"
	folder.Parent = Workspace
	return folder
end

local function normalizeSurfaceNormal(surfaceNormal: Vector3?): Vector3
	if surfaceNormal == nil or surfaceNormal.Magnitude < 0.001 then
		return Vector3.yAxis
	end
	return surfaceNormal.Unit
end

local function createSurfaceFrame(impactPosition: Vector3, surfaceNormal: Vector3): CFrame
	local referenceAxis = if math.abs(surfaceNormal:Dot(Vector3.yAxis)) < 0.98
		then Vector3.yAxis
		else Vector3.xAxis
	local rightAxis = referenceAxis:Cross(surfaceNormal).Unit
	local backAxis = rightAxis:Cross(surfaceNormal).Unit
	local surfacePosition = impactPosition + surfaceNormal * SURFACE_OFFSET
	local baseFrame = CFrame.fromMatrix(surfacePosition, rightAxis, surfaceNormal, backAxis)
	return baseFrame * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
end

local function configureVisiblePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function scaledPosition(position: Vector3, scale: number): Vector3
	return Vector3.new(position.X * scale, position.Y * scale, position.Z * scale)
end

local function localRotation(rotationDegrees: Vector3): CFrame
	return CFrame.Angles(
		math.rad(rotationDegrees.X),
		math.rad(rotationDegrees.Y),
		math.rad(rotationDegrees.Z)
	)
end

local function createWhiteParts(
	parent: Model,
	surfaceFrame: CFrame,
	visualScale: number
): { BasePart }
	local parts: { BasePart } = {}
	local expandTweens: { Tween } = {}
	local settleGoals: { [BasePart]: { [string]: any } } = {}

	for _, definition in WHITE_DEFINITIONS do
		local finalSize = definition.size * visualScale
		local finalPosition = scaledPosition(definition.position, visualScale)
		local rotation = CFrame.Angles(0, math.rad(definition.rotationDegrees), 0)
		local finalCFrame = surfaceFrame * CFrame.new(finalPosition) * rotation
		local startSize = finalSize * 0.25
		local startPosition = Vector3.new(
			finalPosition.X * 0.25,
			startSize.Y * 0.5,
			finalPosition.Z * 0.25
		)
		local expandedPosition = Vector3.new(
			finalPosition.X * 1.10,
			finalPosition.Y,
			finalPosition.Z * 1.10
		)

		local part = Instance.new("Part")
		part.Name = definition.name
		part.Shape = Enum.PartType.Ball
		part.Size = startSize
		part.CFrame = surfaceFrame * CFrame.new(startPosition) * rotation
		part.Color = WHITE_COLOR
		part.Transparency = math.min(definition.transparency + 0.16, 0.38)
		configureVisiblePart(part)
		part.Parent = parent

		local expandedSize = Vector3.new(
			finalSize.X * 1.12,
			finalSize.Y,
			finalSize.Z * 1.12
		)
		local expandTween = TweenService:Create(
			part,
			TweenInfo.new(SPREAD_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Size = expandedSize,
				CFrame = surfaceFrame * CFrame.new(expandedPosition) * rotation,
				Transparency = definition.transparency,
			}
		)
		table.insert(parts, part)
		table.insert(expandTweens, expandTween)
		settleGoals[part] = {
			Size = finalSize,
			CFrame = finalCFrame,
		}
	end

	for _, tween in expandTweens do
		tween:Play()
	end

	task.delay(SPREAD_OUT_DURATION, function()
		if not parent.Parent then
			return
		end
		for part, goal in settleGoals do
			if part.Parent then
				TweenService:Create(
					part,
					TweenInfo.new(
						SPREAD_SETTLE_DURATION,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.InOut
					),
					goal
				):Play()
			end
		end
	end)

	return parts
end

local function createYolk(parent: Model, surfaceFrame: CFrame, visualScale: number): BasePart
	local finalSize = Vector3.new(0.59, 0.18, 0.56) * visualScale
	local finalPosition = Vector3.new(0.17, 0.13, -0.08) * visualScale
	local startSize = finalSize * 0.25
	local startPosition = Vector3.new(
		finalPosition.X * 0.35,
		0.04 * visualScale + startSize.Y * 0.5,
		finalPosition.Z * 0.35
	)

	local yolk = Instance.new("Part")
	yolk.Name = "Yolk"
	yolk.Shape = Enum.PartType.Ball
	yolk.Size = startSize
	yolk.CFrame = surfaceFrame * CFrame.new(startPosition)
	yolk.Color = YOLK_COLOR
	yolk.Transparency = 1
	configureVisiblePart(yolk)
	yolk.Parent = parent

	task.delay(YOLK_DELAY, function()
		if not yolk.Parent then
			return
		end
		TweenService:Create(
			yolk,
			TweenInfo.new(0.17, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Size = finalSize,
				CFrame = surfaceFrame * CFrame.new(finalPosition),
				Transparency = 0.02,
			}
		):Play()
	end)

	return yolk
end

local function createShellPieces(
	parent: Model,
	surfaceFrame: CFrame,
	visualScale: number
): { BasePart }
	local pieces: { BasePart } = {}

	for index, definition in SHELL_DEFINITIONS do
		local finalSize = definition.size * visualScale
		local finalPosition = scaledPosition(definition.position, visualScale)
		local finalRotation = localRotation(definition.rotation)
		local startPosition = Vector3.new(
			finalPosition.X * 0.12,
			finalPosition.Y,
			finalPosition.Z * 0.12
		)
		local startRotation = CFrame.Angles(0, math.rad(index * 12), 0)

		local shell = Instance.new("WedgePart")
		shell.Name = definition.name
		shell.Size = finalSize * 0.65
		shell.CFrame = surfaceFrame * CFrame.new(startPosition) * startRotation
		shell.Color = SHELL_COLOR
		shell.Transparency = 0.16
		configureVisiblePart(shell)
		shell.Parent = parent

		TweenService:Create(
			shell,
			TweenInfo.new(SHELL_SPREAD_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Size = finalSize,
				CFrame = surfaceFrame * CFrame.new(finalPosition) * finalRotation,
				Transparency = 0,
			}
		):Play()
		table.insert(pieces, shell)
	end

	return pieces
end

local function createSlipHitbox(
	parent: Model,
	surfaceFrame: CFrame,
	visualScale: number
): BasePart
	local hitbox = Instance.new("Part")
	hitbox.Name = "SlipHitbox"
	hitbox.Size = Vector3.new(1.95, 0.08, 1.42) * visualScale
	hitbox.CFrame = surfaceFrame * CFrame.new(0, hitbox.Size.Y * 0.5, 0)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = true
	hitbox.CanQuery = true
	hitbox.CastShadow = false
	hitbox.Massless = true
	hitbox:SetAttribute("IsEggSlipZone", true)
	hitbox.Parent = parent
	return hitbox
end

local function scheduleCleanup(brokenEgg: Model, visibleParts: { BasePart }, hitbox: BasePart)
	task.delay(BROKEN_EGG_LIFETIME, function()
		if not brokenEgg.Parent then
			return
		end

		if hitbox.Parent then
			hitbox.CanTouch = false
			hitbox.CanQuery = false
		end
		for _, part in visibleParts do
			if part.Parent then
				TweenService:Create(
					part,
					TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Transparency = 1 }
				):Play()
			end
		end

		task.delay(FADE_DURATION, function()
			if brokenEgg.Parent then
				brokenEgg:Destroy()
			end
		end)
	end)
end

function BrokenEggService.SpawnBrokenEgg(
	impactPosition: Vector3,
	surfaceNormal: Vector3?,
	ownerUserId: number?
): Model
	assert(typeof(impactPosition) == "Vector3", "impactPosition must be a Vector3")

	local normal = normalizeSurfaceNormal(surfaceNormal)
	local surfaceFrame = createSurfaceFrame(impactPosition, normal)
	local visualScale = random:NextNumber(0.95, 1.05)
	local safeOwnerUserId = if typeof(ownerUserId) == "number"
		then math.max(0, math.floor(ownerUserId))
		else 0

	local brokenEgg = Instance.new("Model")
	brokenEgg.Name = "BrokenEgg"
	brokenEgg:SetAttribute("IsBrokenEgg", true)
	brokenEgg:SetAttribute("OwnerUserId", safeOwnerUserId)
	brokenEgg:SetAttribute("SpawnTime", Workspace:GetServerTimeNow())

	local eggWhite = Instance.new("Model")
	eggWhite.Name = "EggWhite"
	eggWhite.Parent = brokenEgg

	local shellPieces = Instance.new("Model")
	shellPieces.Name = "ShellPieces"
	shellPieces.Parent = brokenEgg

	local visibleParts = createWhiteParts(eggWhite, surfaceFrame, visualScale)
	local yolk = createYolk(brokenEgg, surfaceFrame, visualScale)
	table.insert(visibleParts, yolk)
	for _, shell in createShellPieces(shellPieces, surfaceFrame, visualScale) do
		table.insert(visibleParts, shell)
	end
	local hitbox = createSlipHitbox(brokenEgg, surfaceFrame, visualScale)

	brokenEgg.Parent = getBrokenEggFolder()
	scheduleCleanup(brokenEgg, visibleParts, hitbox)
	return brokenEgg
end

return BrokenEggService
