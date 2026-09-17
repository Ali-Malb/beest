local RUN_ANIM_ID = "rbxassetid://656118852"

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local animation = Instance.new("Animation")
		animation.AnimationId = RUN_ANIM_ID
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Movement
		track:Play()