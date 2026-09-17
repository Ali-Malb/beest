local spawnLocation = script.Parent
local spawnTime = 10 -- Time in seconds before the spawn location resets

spawnLocation.Touched:Connect(function(hit))
local character = hit.Parent
local humanoid = character:FindFirstChild("Humanoid")
local player = game.Players:GetPlayerFromCharacter(character)
if humanoid and player then
	humanoid.walkSpeed = 16
	if not player:get
end