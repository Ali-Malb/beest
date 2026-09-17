local SPRINT_ANIM_ID = "rbxassetid://100537298625296" -- 🏃‍♂️ Your Sprint ID
local WALK_ANIM_ID   = "rbxassetid://132749301821841" -- 🚶‍♂️ Your Walk ID

print("⚡ SYSTEM: R6 Dynamic Animation Swapper Active!")

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local animateScript = character:WaitForChild("Animate")
		local humanoid = character:WaitForChild("Humanoid")

		local walkFolder = animateScript:WaitForChild("walk")
		local walkAnim = walkFolder:WaitForChild("Animation")

		-- Set testing speed
		humanoid.WalkSpeed = 26

		-- Watch player speed and switch the ID instantly
		humanoid.Running:Connect(function(currentSpeed)
			if currentSpeed > 18 then
				-- If running fast, force the sprint asset into the walk slot
				if walkAnim.AnimationId ~= SPRINT_ANIM_ID then
					walkAnim.AnimationId = SPRINT_ANIM_ID

					-- Force the engine to instantly refresh the track
					for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
						if track.Name == "walk" then track:Stop(0.1) end
					end
				end
			else
				-- If walking slowly, drop back down to the walk asset
				if walkAnim.AnimationId ~= WALK_ANIM_ID then
					walkAnim.AnimationId = WALK_ANIM_ID

					for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
						if track.Name == "walk" then track:Stop(0.1) end
					end
				end
			end
		end)
	end)
end)