local spawnLocation = script.Parent
local spawnTime = 10 -- Time in seconds before the spawn location resets

spawnLocation.Touched:Connect(function(hit))
local character = hit.Parent
local humanoid = character:FindFirstChild("Humanoid")
local player = game.Players:GetPlayerFromCharacter(character)
if humanoid and player then
	humanoid.walkSpeed = 16
	if not player:GetAttribute("SpeedConnectionsSet") then
		player:setAttribute("SpeedConnectionsSet", true)
		player.CharacterAdded:Connect(function(newCharacter))
		local newHumanoid = newCharacter:WaitForChild("Humanoid")
		if player.TeamColor == spawnLocation.TeamColor then
			newHumanoid.WalkSpeed = 16
		else
			newHumanoid.WalkSpeed = 10
		end
	end
end