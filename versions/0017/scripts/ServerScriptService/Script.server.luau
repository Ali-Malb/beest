local RUN_ANIM_ID = "rbxassetid://656118852"

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local animateScript = character:WaitForChild("Humanoid")
		local runFolder = animateScript:WaitForChild("Run")
		local runAnim = Instance.new("Animation")
		runAnim.AnimationId = RUN_ANIM_ID
		runAnim.Name = "RunAnim"
		runAnim.Parent = runFolder
	end)
end)