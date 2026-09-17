local Players = game:GetService("Players")

local finishPart = workspace:WaitForChild("FinishPart")

local startTimes = {}
local finished = {}

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")

		startTimes[player] = nil
		finished[player] = false

		humanoid.Running:Connect(function(speed)
			if speed > 0 and not startTimes[player] and not finished[player] then
				startTimes[player] = os.clock()
			end
		end)
	end)
end)

finishPart.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)

	if player and startTimes[player] and not finished[player] then
		finished[player] = true

		local finalTime = os.clock() - startTimes[player]

		print(player.Name .. " finished in " .. string.format("%.3f", finalTime) .. " seconds")

		player:SetAttribute("FinalTime", finalTime)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	startTimes[player] = nil
	finished[player] = nil
end)