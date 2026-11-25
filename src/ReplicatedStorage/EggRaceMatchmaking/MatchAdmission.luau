--!strict

local MatchProtocol = require(script.Parent:WaitForChild("MatchProtocol"))

local MatchAdmission = {}

export type Context = {
	expectedSchemaVersion: number,
	maximumRacers: number,
	expectedSourcePlaceId: number,
	maximumPayloadAgeSeconds: number,
	now: number,
}

function MatchAdmission.validate(value: any, context: Context): (MatchProtocol.TeleportPayload?, string?)
	local payload = MatchProtocol.parseTeleportPayload(
		value,
		context.expectedSchemaVersion,
		context.maximumRacers
	)
	if not payload then
		return nil, "MalformedPayload"
	end
	if payload.sourcePlaceId ~= context.expectedSourcePlaceId then
		return nil, "UnexpectedSource"
	end
	local payloadAge = context.now - payload.createdAt
	if payloadAge < -60 or payloadAge > context.maximumPayloadAgeSeconds then
		return nil, "StalePayload"
	end
	return payload, nil
end

return table.freeze(MatchAdmission)
