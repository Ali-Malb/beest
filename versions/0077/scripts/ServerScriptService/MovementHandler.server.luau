local ReplicatedStorage = game:GetService("ReplicatedStorage")
local R_ID = "rbxassetid://656118852"
local W_ID = "rbxassetid://782842708"

local resetEvent = ResetEvent = ReplicatedStorage:WaitForChild("ResetEvent") or Instance.new("RemoteEvent")
ResetEvent.Name = "ResetToSpawnEvent"
resetEvent.Parent = ReplicatedStorage

local playerLastSpawn = {}

