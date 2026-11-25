--!strict

-- Safe public example. Replace IDs locally and opt in only after both places
-- have the runtime installed and have passed a Studio dry run.
return table.freeze({
	SchemaVersion = 2,
	Enabled = false,
	LobbyPlaceId = 0,
	RacePlaceId = 0,
	MaxRacers = 8,
	MinimumOnlineRacers = 2,
	TeleportPayloadMaxAgeSeconds = 300,
	AllowStudioDryRun = true,
})
