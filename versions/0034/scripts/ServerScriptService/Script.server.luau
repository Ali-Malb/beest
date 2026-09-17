local RUN_ANIM_ID = "rbxassetid://100537298625296"
local WALK_ANIM_ID = "rbxassetid://132749301821841"

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local animateScript = character:WaitForChild("Animate")
		
		local runFolder = animateScript:WaitForChild("run")
		local runAnim = runFolder:WaitForChild("Animation")
		runAnim.AnimationId = RUN_ANIM_ID
		local walkFolder = animateScript:WaitForChild("walk")
		local walkAnim = walkFolder:WaitForChild("Animation")
		walkAnim.AnimationId = WALK_ANIM_ID
	end)
end)