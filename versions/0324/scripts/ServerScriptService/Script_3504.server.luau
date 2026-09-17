local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local TargetSpawn = Workspace:WaitForChild("SpawnLocation2")

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
	local humanoidrootpart = character:WaitForChild("HumanoidRootPart")
	humanoidrootpart.CFrame = TargetSpawn.CFrame + Vector3.new(0, 3, 0)
	end)
end)
