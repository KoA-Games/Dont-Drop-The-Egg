--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchProtocol = require(
	ReplicatedStorage:WaitForChild("EggRaceMatchmaking"):WaitForChild("MatchProtocol")
)

local function validPayload()
	return {
		schemaVersion = 2,
		matchId = "match-12345678",
		mode = "Online",
		expectedUserIds = { 101, 202 },
		expectedHumanCount = 2,
		maxRacers = 8,
		sourcePlaceId = 1,
		sourceJobId = "job-a",
		createdAt = 1000,
		fillWithBots = false,
	}
end

assert(MatchProtocol.parseTeleportPayload(validPayload(), 2, 8) ~= nil)

local duplicateUsers = validPayload()
duplicateUsers.expectedUserIds = { 101, 101 }
assert(MatchProtocol.parseTeleportPayload(duplicateUsers, 2, 8) == nil)

local mismatchedCount = validPayload()
mismatchedCount.expectedHumanCount = 3
assert(MatchProtocol.parseTeleportPayload(mismatchedCount, 2, 8) == nil)

local wrongSchema = validPayload()
wrongSchema.schemaVersion = 1
assert(MatchProtocol.parseTeleportPayload(wrongSchema, 2, 8) == nil)

local invalidMode = validPayload()
invalidMode.mode = "Ranked"
assert(MatchProtocol.parseTeleportPayload(invalidMode, 2, 8) == nil)

print("MatchProtocol specification passed")
