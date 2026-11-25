--!strict

local MatchProtocol = {}

MatchProtocol.Modes = table.freeze({
	Solo = "Solo",
	Online = "Online",
})

export type MatchMode = "Solo" | "Online"

export type TeleportPayload = {
	schemaVersion: number,
	matchId: string,
	mode: MatchMode,
	expectedUserIds: { number },
	expectedHumanCount: number,
	maxRacers: number,
	sourcePlaceId: number,
	sourceJobId: string,
	createdAt: number,
	fillWithBots: boolean,
}

function MatchProtocol.normalizeMode(value: any): MatchMode?
	if value == MatchProtocol.Modes.Solo then
		return "Solo"
	end
	if value == MatchProtocol.Modes.Online then
		return "Online"
	end
	return nil
end

function MatchProtocol.readUserIds(value: any, maximum: number): { number }?
	if typeof(value) ~= "table" then
		return nil
	end

	local result: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, candidate in value do
		if typeof(candidate) ~= "number" or candidate % 1 ~= 0 or candidate <= 0 then
			return nil
		end
		if seen[candidate] then
			return nil
		end
		seen[candidate] = true
		table.insert(result, candidate)
		if #result > maximum then
			return nil
		end
	end

	return result
end

function MatchProtocol.parseTeleportPayload(
	value: any,
	expectedSchemaVersion: number,
	maximumRacers: number
): TeleportPayload?
	if typeof(value) ~= "table" then
		return nil
	end

	local mode = MatchProtocol.normalizeMode(value.mode)
	local userIds = MatchProtocol.readUserIds(value.expectedUserIds, maximumRacers)
	if not mode or not userIds then
		return nil
	end

	if value.schemaVersion ~= expectedSchemaVersion then
		return nil
	end
	if typeof(value.matchId) ~= "string" or #value.matchId < 8 or #value.matchId > 80 then
		return nil
	end
	if typeof(value.expectedHumanCount) ~= "number"
		or value.expectedHumanCount % 1 ~= 0
		or value.expectedHumanCount < 1
		or value.expectedHumanCount > maximumRacers
	then
		return nil
	end
	if value.expectedHumanCount ~= #userIds then
		return nil
	end
	if value.maxRacers ~= maximumRacers then
		return nil
	end
	if typeof(value.sourcePlaceId) ~= "number" or value.sourcePlaceId < 0 then
		return nil
	end
	if typeof(value.sourceJobId) ~= "string" then
		return nil
	end
	if typeof(value.createdAt) ~= "number" then
		return nil
	end
	if typeof(value.fillWithBots) ~= "boolean" then
		return nil
	end

	return {
		schemaVersion = value.schemaVersion,
		matchId = value.matchId,
		mode = mode,
		expectedUserIds = userIds,
		expectedHumanCount = value.expectedHumanCount,
		maxRacers = value.maxRacers,
		sourcePlaceId = value.sourcePlaceId,
		sourceJobId = value.sourceJobId,
		createdAt = value.createdAt,
		fillWithBots = value.fillWithBots,
	}
end

return MatchProtocol
