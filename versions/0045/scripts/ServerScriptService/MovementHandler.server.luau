local RUN_ID = "rbxassetid://656118852"
local WALK_ID = "rbxassetid://132749301821841"
game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local animateScript = script:WaitForChild("Animate")
		
		local walkfolder = animateScript:WaitForChild("walk")
		local walkAnim  =  walkfolder:WaitForChild("WalkAnim") 
	end)
end)