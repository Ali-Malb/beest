local RUN_ID = "rbxassetid://656118852"    -- 🥷 Official Ninja Run
local WALK_ID = "rbxassetid://782842708"   -- 🤖 Raw Toy Run Data ID

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local animateScript = char:WaitForChild("Animate")
		local humanoid = char:WaitForChild("Humanoid")

		local walkfolder = animateScript:WaitForChild("walk")
		local runfolder = animateScript:WaitForChild("run")

		-- 📁 Overwrite EVERY child asset inside the folder (covers Animation1, Animation2, etc.)
		for _, child in ipairs(walkfolder:GetChildren()) do
			if child:IsA("Animation") then child.AnimationId = WALK_ID end
		end

		for _, child in ipairs(runfolder:GetChildren()) do
			if child:IsA("Animation") then child.AnimationId = RUN_ID end
		end

		-- ⚡ THE CACHE FLUSH: Force-stop all current playing animation tracks
		-- This deletes the default tracks from memory and forces the engine to look at your new IDs!
		local animator = humanoid:WaitForChild("Animator", 5)
		if animator then
			task.wait(0.1) -- Give the properties a millisecond to register the ID change
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end

		-- Set baseline walk speed to trigger your new Toy layout
		humanoid.WalkSpeed = 10
	end)
end)