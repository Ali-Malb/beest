local RUN_ID = "rbxassetid://656118852"
local WALK_ID = "rbxassetid://132749301821841"
game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local animateScript = char:WaitForChild("Animate")
		
		local walkfolder = animateScript:WaitForChild("walk")
		local walkAnim  =  walkfolder:WaitForChild("Animation1, 5") or walkfolder:FindFirstChildWhichIsA("Animation")
		
		local runfolder = animateScript:WaitForChild("run")
		local runAnim  =  runfolder:WaitForChild("RunAnim") or runfolder:WaitForChild("Animation")

		if walkAnim then walkAnim.AnimationId = WALK_ID end
		if runAnim then runAnim.AnimationId = RUN_ID end
		
		local  humanoid = char:WaitForChild("Humanoid")
		humanoid.WalkSpeed = 27
	end)
end)