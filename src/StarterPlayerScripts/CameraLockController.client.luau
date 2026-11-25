--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ACTION_NAME = "DDEToggleCameraLock"
local ENFORCE_BINDING = "DDECameraLockEnforce"
local SUPPRESSION_ATTRIBUTE = "CameraLockSuppressed"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local userWantsCameraLock = true
local menuSuppressed = GuiService.MenuIsOpen
local textInputSuppressed = UserInputService:GetFocusedTextBox() ~= nil
local externalSuppressed = player:GetAttribute(SUPPRESSION_ATTRIBUTE) == true
local currentlyLocked = false
local toggleKeyDown = false
local hintShown = false
local alive = true
local connections: { RBXScriptConnection } = {}

local existingGui = playerGui:FindFirstChild("CameraLockGui")
if existingGui then
	existingGui:Destroy()
end

local cameraLockGui = Instance.new("ScreenGui")
cameraLockGui.Name = "CameraLockGui"
cameraLockGui.ResetOnSpawn = false
cameraLockGui.IgnoreGuiInset = true
cameraLockGui.DisplayOrder = 80
cameraLockGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
cameraLockGui.Parent = playerGui

local reticle = Instance.new("Frame")
reticle.Name = "Reticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
reticle.Size = UDim2.fromOffset(16, 16)
reticle.BackgroundTransparency = 1
reticle.BorderSizePixel = 0
reticle.Active = false
reticle.Visible = false
reticle.ZIndex = 2
reticle.Parent = cameraLockGui

local function createReticlePiece(
	name: string,
	size: UDim2,
	position: UDim2
)
	local piece = Instance.new("Frame")
	piece.Name = name
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.Position = position
	piece.Size = size
	piece.BackgroundColor3 = Color3.fromRGB(247, 249, 255)
	piece.BackgroundTransparency = 0.14
	piece.BorderSizePixel = 0
	piece.Active = false
	piece.ZIndex = 2
	piece.Parent = reticle

	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(12, 16, 24)
	outline.Thickness = 1
	outline.Transparency = 0.38
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = piece
end

createReticlePiece("CenterDot", UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5))
createReticlePiece("Left", UDim2.fromOffset(4, 2), UDim2.new(0.5, -5, 0.5, 0))
createReticlePiece("Right", UDim2.fromOffset(4, 2), UDim2.new(0.5, 5, 0.5, 0))
createReticlePiece("Top", UDim2.fromOffset(2, 4), UDim2.new(0.5, 0, 0.5, -5))
createReticlePiece("Bottom", UDim2.fromOffset(2, 4), UDim2.new(0.5, 0, 0.5, 5))

local hint = Instance.new("TextLabel")
hint.Name = "FreeCursorHint"
hint.AnchorPoint = Vector2.new(1, 1)
hint.Position = UDim2.fromScale(0.965, 0.93)
hint.Size = UDim2.fromOffset(166, 28)
hint.BackgroundColor3 = Color3.fromRGB(10, 14, 22)
hint.BackgroundTransparency = 0.28
hint.BorderSizePixel = 0
hint.Font = Enum.Font.GothamMedium
hint.Text = "C   FREE CURSOR"
hint.TextColor3 = Color3.fromRGB(239, 243, 252)
hint.TextSize = 14
hint.TextTransparency = 1
hint.Active = false
hint.Visible = false
hint.ZIndex = 3
hint.Parent = cameraLockGui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 6)
hintCorner.Parent = hint

local function keyboardAndMouseIsPreferred(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
end

local function showHintOnce()
	if hintShown or not keyboardAndMouseIsPreferred() or not alive then
		return
	end
	hintShown = true
	hint.Visible = true
	hint.TextTransparency = 0.08
	task.delay(2.7, function()
		if not alive or not hint.Parent then
			return
		end
		local tween = TweenService:Create(
			hint,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}
		)
		tween:Play()
		tween.Completed:Once(function()
			if hint.Parent then
				hint.Visible = false
			end
		end)
	end)
end

local function reconcileCameraLock(reason: string)
	if not alive then
		return
	end
	menuSuppressed = menuSuppressed or GuiService.MenuIsOpen
	textInputSuppressed = UserInputService:GetFocusedTextBox() ~= nil
	externalSuppressed = player:GetAttribute(SUPPRESSION_ATTRIBUTE) == true

	local shouldLock = keyboardAndMouseIsPreferred()
		and userWantsCameraLock
		and not menuSuppressed
		and not textInputSuppressed
		and not externalSuppressed
	if not keyboardAndMouseIsPreferred() then
		hint.Visible = false
	end

	if shouldLock then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		reticle.Visible = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		reticle.Visible = false
	end

	if currentlyLocked ~= shouldLock then
		currentlyLocked = shouldLock
		print(string.format(
			"[CameraLock] %s reason=%s",
			if shouldLock then "enabled" else "disabled",
			reason
		))
	end
	if shouldLock then
		showHintOnce()
	end
end

local function toggleCameraLock(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel
	then
		toggleKeyDown = false
		return if keyboardAndMouseIsPreferred()
			then Enum.ContextActionResult.Sink
			else Enum.ContextActionResult.Pass
	end
	if inputState ~= Enum.UserInputState.Begin
		or toggleKeyDown
		or not keyboardAndMouseIsPreferred()
		or GuiService.MenuIsOpen
		or UserInputService:GetFocusedTextBox() ~= nil
	then
		return Enum.ContextActionResult.Pass
	end

	toggleKeyDown = true
	userWantsCameraLock = not userWantsCameraLock
	reconcileCameraLock("C")
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(
	ACTION_NAME,
	toggleCameraLock,
	false,
	Enum.KeyCode.C
)

RunService:BindToRenderStep(
	ENFORCE_BINDING,
	Enum.RenderPriority.Camera.Value + 5,
	function()
		if not currentlyLocked
			or not keyboardAndMouseIsPreferred()
			or GuiService.MenuIsOpen
			or UserInputService:GetFocusedTextBox() ~= nil
			or player:GetAttribute(SUPPRESSION_ATTRIBUTE) == true
		then
			return
		end
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	end
)

table.insert(connections, GuiService.MenuOpened:Connect(function()
	menuSuppressed = true
	reconcileCameraLock("menu")
end))

table.insert(connections, GuiService.MenuClosed:Connect(function()
	menuSuppressed = false
	task.defer(function()
		if not alive then
			return
		end
		RunService.RenderStepped:Wait()
		if not alive then
			return
		end
		menuSuppressed = GuiService.MenuIsOpen
		reconcileCameraLock("menu-closed")
	end)
end))

table.insert(connections, UserInputService.TextBoxFocused:Connect(function()
	textInputSuppressed = true
	reconcileCameraLock("textbox")
end))

table.insert(connections, UserInputService.TextBoxFocusReleased:Connect(function()
	task.defer(function()
		if not alive then
			return
		end
		textInputSuppressed = UserInputService:GetFocusedTextBox() ~= nil
		reconcileCameraLock("textbox")
	end)
end))

table.insert(connections, UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
	print(string.format(
		"[CameraLock] preferredInput=%s",
		UserInputService.PreferredInput.Name
	))
	reconcileCameraLock("input-changed")
end))

table.insert(connections, player:GetAttributeChangedSignal(SUPPRESSION_ATTRIBUTE):Connect(function()
	externalSuppressed = player:GetAttribute(SUPPRESSION_ATTRIBUTE) == true
	reconcileCameraLock("external")
end))

table.insert(connections, player.CharacterAdded:Connect(function(character: Model)
	task.defer(function()
		character:WaitForChild("Humanoid", 5)
		if alive and character == player.Character then
			RunService.RenderStepped:Wait()
			reconcileCameraLock("spawn")
		end
	end)
end))

table.insert(connections, script.Destroying:Connect(function()
	if not alive then
		return
	end
	alive = false
	ContextActionService:UnbindAction(ACTION_NAME)
	RunService:UnbindFromRenderStep(ENFORCE_BINDING)
	for _, connection in connections do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	if cameraLockGui.Parent then
		cameraLockGui:Destroy()
	end
end))

print(string.format(
	"[CameraLock] preferredInput=%s",
	UserInputService.PreferredInput.Name
))
reconcileCameraLock("spawn")
