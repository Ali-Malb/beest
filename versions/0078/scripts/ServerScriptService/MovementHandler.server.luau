local ReplicatedStorage = game:GetService("ReplicatedStorage")
local R_ID = "rbxassetid://656118852"
local W_ID = "rbxassetid://782842708"

local resetEvent = ResetEvent = ReplicatedStorage:WaitForChild("ResetEvent") or Instance.new("RemoteEvent")
ResetEvent.Name = "ResetToSpawnEvent"
resetEvent.Parent = ReplicatedStorage

local playerLastSpawn = {}

for _, desc in ipairs(workspace:GetDescendants()) do
	if desc:IsA("BasePart") then
		desc.Touched:Connect(function(hit)
			local player = game.Players:GetPlayerFromCharacter(hit.Parent)
			if player then
				playerLastSpawn[player.UserId] = desc
			end
		end)
	end
end

game.Players.PlayerAdded:Connect(function(player)