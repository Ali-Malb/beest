local RUN_ANIM_ID = "rbxassetid://656118852"

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local animateScript = character:WaitForChild("Animate")
		local runFolder = animateScript:WaitForChild("run")
		local runAnim = runFolder:WaitForChild("RunAnim")
		runAnim.AnimationId = RUN_ANIM_ID
	end)
end)