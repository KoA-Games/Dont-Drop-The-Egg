--!strict

-- TEMPORARY STEP 1 PROTOTYPE TEST.
-- Remove or disable this script after the broken-egg visual has been approved.
local TEST_ENABLED = true

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BrokenEggService = require(script.Parent:WaitForChild("BrokenEggService"))

local TEST_FORWARD_DISTANCE = 5
local RAY_START_HEIGHT = 5
local RAY_DISTANCE = 50

if not TEST_ENABLED then
	return
end

local testSpawnClaimed = false

local function spawnPrototypeForPlayer(player: Player)
	if testSpawnClaimed then
		return
	end
	testSpawnClaimed = true

	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		local rootInstance = character:WaitForChild("HumanoidRootPart", 15)
		if not rootInstance or not rootInstance:IsA("BasePart") then
			warn("[BrokenEggPrototypeTest] HumanoidRootPart was not available")
			return
		end

		local targetPosition = rootInstance.Position
			+ rootInstance.CFrame.LookVector * TEST_FORWARD_DISTANCE
		local rayOrigin = targetPosition + Vector3.yAxis * RAY_START_HEIGHT
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { character }
		raycastParams.IgnoreWater = false

		local result = Workspace:Raycast(
			rayOrigin,
			-Vector3.yAxis * RAY_DISTANCE,
			raycastParams
		)
		if not result then
			warn("[BrokenEggPrototypeTest] No ground was found below the test position")
			return
		end

		BrokenEggService.SpawnBrokenEgg(result.Position, result.Normal, player.UserId)
	end)
end

local currentPlayers = Players:GetPlayers()
if #currentPlayers > 0 then
	spawnPrototypeForPlayer(currentPlayers[1])
else
	Players.PlayerAdded:Once(spawnPrototypeForPlayer)
end
