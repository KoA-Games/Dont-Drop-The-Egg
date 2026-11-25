--!strict

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local TEMPLATE_PART_NAME = "EggRaceTracksuitSurfaceTemplate"
local SURFACE_TEMPLATE_NAME = "EggRaceTracksuitSurface"
local TARGET_WRAP_LAYER_NAME = "Jacket_Suit_001"
-- Matching classic underlayer fills the layered coat's real open-front gap.
-- The 3D coat still supplies the sleeves, shoulders, lapels, and fabric volume.
local CLOSED_FRONT_UNDERLAYER = "rbxassetid://83563308924435"
local TRACKSUIT_PANTS = "rbxassetid://131773059048067"

print("[LayeredTracksuit] service started")

local templatePart = ServerStorage:WaitForChild(TEMPLATE_PART_NAME, 10)
if not templatePart then
	error("[LayeredTracksuit] Rojo template is missing; reconnect Rojo in edit mode")
end

local surfaceTemplateInstance = templatePart:WaitForChild(SURFACE_TEMPLATE_NAME, 10)
if not surfaceTemplateInstance or not surfaceTemplateInstance:IsA("SurfaceAppearance") then
	error("[LayeredTracksuit] SurfaceAppearance template is missing or invalid")
end
local SURFACE_TEMPLATE = surfaceTemplateInstance

local function isTargetCoat(accessory: Accessory): boolean
	return accessory.AccessoryType == Enum.AccessoryType.Jacket
		and accessory:FindFirstChild(TARGET_WRAP_LAYER_NAME, true) ~= nil
end

local function applyClosedFrontUnderlayer(character: Model)
	local shirt = character:FindFirstChildOfClass("Shirt")
	if not shirt then
		shirt = Instance.new("Shirt")
		shirt.Name = "EggRaceTracksuitUnderlayer"
		shirt.Parent = character
	end
	shirt.ShirtTemplate = CLOSED_FRONT_UNDERLAYER
end

local function applyTracksuitPants(character: Model)
	local pants = character:FindFirstChildOfClass("Pants")
	if not pants then
		pants = Instance.new("Pants")
		pants.Name = "EggRaceTracksuitPants"
		pants.Parent = character
	end
	pants.PantsTemplate = TRACKSUIT_PANTS
end

local function applyTracksuitColorMap(character: Model): boolean
	local changed = false
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and isTargetCoat(child) then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("MeshPart") then
				local existingSurface = handle:FindFirstChildOfClass("SurfaceAppearance")
				if existingSurface and existingSurface.Name ~= SURFACE_TEMPLATE_NAME then
					existingSurface:Destroy()
				end

				if not handle:FindFirstChild(SURFACE_TEMPLATE_NAME) then
					local replacement = SURFACE_TEMPLATE:Clone()
					replacement.Parent = handle
				end
				changed = true
			end
		end
	end
	if changed then
		applyClosedFrontUnderlayer(character)
		applyTracksuitPants(character)
		character:SetAttribute("EggRaceLayeredTracksuitApplied", true)
		print("[LayeredTracksuit] applied to " .. character.Name)
	end
	return changed
end

local function watchCharacter(character: Model)
	-- Avatar assets can arrive over several frames. Apply once immediately and
	-- also catch the coat's SurfaceAppearance if it is inserted afterwards.
	applyTracksuitColorMap(character)

	local childAddedConnection: RBXScriptConnection? = nil
	childAddedConnection = character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Accessory") and isTargetCoat(child) then
			applyTracksuitColorMap(character)
			if childAddedConnection then
				childAddedConnection:Disconnect()
				childAddedConnection = nil
			end
		end
	end)

	character.Destroying:Once(function()
		if childAddedConnection then
			childAddedConnection:Disconnect()
			childAddedConnection = nil
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterAppearanceLoaded:Connect(function(character: Model)
		if player.Character == character then
			applyTracksuitColorMap(character)
		end
	end)

	if player.Character then
		watchCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
