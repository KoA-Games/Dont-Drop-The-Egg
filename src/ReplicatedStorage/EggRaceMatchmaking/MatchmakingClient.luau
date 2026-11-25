--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("EggRaceMatchmaking")
local remotes = root:WaitForChild("Remotes")
local requestMatch = remotes:WaitForChild("RequestMatch") :: RemoteEvent
local cancelMatch = remotes:WaitForChild("CancelMatch") :: RemoteEvent
local setQueueReady = remotes:WaitForChild("SetQueueReady") :: RemoteEvent
local requestQueueStatus = remotes:WaitForChild("RequestQueueStatus") :: RemoteEvent
local matchStatus = remotes:WaitForChild("MatchStatus") :: RemoteEvent

local MatchmakingClient = {}

function MatchmakingClient.requestSolo()
	requestMatch:FireServer("Solo")
end

function MatchmakingClient.requestOnline()
	requestMatch:FireServer("Online")
end

function MatchmakingClient.cancel()
	cancelMatch:FireServer()
end

function MatchmakingClient.setQueueReady(isReady: boolean)
	setQueueReady:FireServer(isReady)
end

function MatchmakingClient.requestQueueStatus()
	requestQueueStatus:FireServer()
end

function MatchmakingClient.statusChanged(): RBXScriptSignal
	return matchStatus.OnClientEvent
end

return table.freeze(MatchmakingClient)
