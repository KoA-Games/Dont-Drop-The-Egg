--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local MIN_EGG_COUNT = 1
local MAX_EGG_COUNT = 30
local DEFAULT_EGG_COUNT = 5
local SELECTED_EGG_COUNT_ATTRIBUTE = "SelectedEggCount"
local REMAINING_EGG_COUNT_ATTRIBUTE = "RemainingEggCount"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotes or not remotes:IsA("Folder") then
	warn("[EggCountTestUI] ReplicatedStorage.Remotes was not available")
	return
end
local remoteInstance = remotes:WaitForChild("SetEggCount", 10)
if not remoteInstance or not remoteInstance:IsA("RemoteEvent") then
	warn("[EggCountTestUI] Remotes.SetEggCount was not available")
	return
end
local setEggCountRemote = remoteInstance

local oldGui = playerGui:FindFirstChild("EggCountTestUI")
if oldGui then
	oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EggCountTestUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 100

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 18, 0.5, 0)
panel.Size = UDim2.fromOffset(250, 170)
panel.BackgroundColor3 = Color3.fromRGB(30, 34, 43)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(104, 117, 145)
stroke.Transparency = 0.35
stroke.Thickness = 1
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.new(1, -24, 0, 26)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "STUDIO EGG COUNT TEST"
title.TextColor3 = Color3.fromRGB(236, 239, 247)
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local currentLabel = Instance.new("TextLabel")
currentLabel.Name = "CurrentCount"
currentLabel.Position = UDim2.fromOffset(12, 38)
currentLabel.Size = UDim2.new(1, -24, 0, 24)
currentLabel.BackgroundTransparency = 1
currentLabel.Font = Enum.Font.Gotham
currentLabel.TextColor3 = Color3.fromRGB(179, 189, 211)
currentLabel.TextSize = 14
currentLabel.TextXAlignment = Enum.TextXAlignment.Left
currentLabel.Parent = panel

local pendingLabel = Instance.new("TextLabel")
pendingLabel.Name = "PendingCount"
pendingLabel.Position = UDim2.fromOffset(77, 67)
pendingLabel.Size = UDim2.fromOffset(96, 42)
pendingLabel.BackgroundColor3 = Color3.fromRGB(48, 54, 68)
pendingLabel.BorderSizePixel = 0
pendingLabel.Font = Enum.Font.GothamBold
pendingLabel.TextColor3 = Color3.fromRGB(255, 238, 190)
pendingLabel.TextSize = 24
pendingLabel.Parent = panel

local pendingCorner = Instance.new("UICorner")
pendingCorner.CornerRadius = UDim.new(0, 8)
pendingCorner.Parent = pendingLabel

local function createButton(name: string, text: string, position: UDim2, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(68, 78, 99)
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(245, 247, 252)
	button.TextSize = 20
	button.Parent = panel

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button
	return button
end

local minusButton = createButton(
	"Minus",
	"−",
	UDim2.fromOffset(12, 67),
	UDim2.fromOffset(55, 42)
)
local plusButton = createButton(
	"Plus",
	"+",
	UDim2.fromOffset(183, 67),
	UDim2.fromOffset(55, 42)
)
local applyButton = createButton(
	"Apply",
	"APPLY",
	UDim2.fromOffset(12, 119),
	UDim2.new(1, -24, 0, 39)
)
applyButton.BackgroundColor3 = Color3.fromRGB(197, 133, 52)
applyButton.TextSize = 16

local selectedAttribute = player:GetAttribute(SELECTED_EGG_COUNT_ATTRIBUTE)
local currentCount = if typeof(selectedAttribute) == "number"
	then math.clamp(math.floor(selectedAttribute), MIN_EGG_COUNT, MAX_EGG_COUNT)
	else DEFAULT_EGG_COUNT
local remainingAttribute = player:GetAttribute(REMAINING_EGG_COUNT_ATTRIBUTE)
local remainingCount = if typeof(remainingAttribute) == "number"
	then math.max(0, math.floor(remainingAttribute))
	else 0
local pendingCount = currentCount

local function render()
	currentLabel.Text = "Loaded: " .. tostring(currentCount)
		.. "    Remaining: " .. tostring(remainingCount)
	pendingLabel.Text = tostring(pendingCount)
end

minusButton.Activated:Connect(function()
	pendingCount = math.clamp(pendingCount - 1, MIN_EGG_COUNT, MAX_EGG_COUNT)
	render()
end)

plusButton.Activated:Connect(function()
	pendingCount = math.clamp(pendingCount + 1, MIN_EGG_COUNT, MAX_EGG_COUNT)
	render()
end)

applyButton.Activated:Connect(function()
	setEggCountRemote:FireServer(pendingCount)
end)

player:GetAttributeChangedSignal(SELECTED_EGG_COUNT_ATTRIBUTE):Connect(function()
	local value = player:GetAttribute(SELECTED_EGG_COUNT_ATTRIBUTE)
	if typeof(value) == "number" then
		currentCount = math.clamp(math.floor(value), MIN_EGG_COUNT, MAX_EGG_COUNT)
		pendingCount = currentCount
		render()
	end
end)

player:GetAttributeChangedSignal(REMAINING_EGG_COUNT_ATTRIBUTE):Connect(function()
	local value = player:GetAttribute(REMAINING_EGG_COUNT_ATTRIBUTE)
	if typeof(value) == "number" then
		remainingCount = math.max(0, math.floor(value))
		render()
	end
end)

render()
screenGui.Parent = playerGui
