local SPRINT_ANIM_ID = "rbxassetid://100537298625296" -- 🏃‍♂️ Your Sprint ID
local WALK_ANIM_ID   = "rbxassetid://132749301821841" -- 🚶‍♂️ Your Walk ID

print("⚙️ SYSTEM: Movement Handler Initialized Successfully!")

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local animateScript = character:WaitForChild("Animate", 5)
		if not animateScript then return end

		local runFolder = animateScript:WaitForChild("run", 5)
		local walkFolder = animateScript:WaitForChild("walk", 5)
		if not runFolder or not walkFolder then return end

		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = 26 -- Force speed boost for testing

		-- 📁 FIX: Give Roblox up to 1 second to load the internal asset track
		local r6WalkAnim = walkFolder:WaitForChild("Animation", 1)

		if r6WalkAnim then
			print("🤖 RIG DETECTED: Game successfully verified your R6 structure!")

			-- Dynamic R6 Swapper logic
			humanoid.Running:Connect(function(speed)
				if speed > 18 then
					if r6WalkAnim.AnimationId ~= SPRINT_ANIM_ID then
						r6WalkAnim.AnimationId = SPRINT_ANIM_ID
						for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
							if track.Name == "walk" then track:Stop(0.1) end
						end
					end
				else
					if r6WalkAnim.AnimationId ~= WALK_ANIM_ID then
						r6WalkAnim.AnimationId = WALK_ANIM_ID
						for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
							if track.Name == "walk" then track:Stop(0.1) end
						end
					end
				end
			end)
		else
			print("⚠️ FALLBACK: Animation object not found in time. Trying R15 layout...")
			local r15Run = runFolder:FindFirstChild("RunAnim")
			local r15Walk = walkFolder:FindFirstChild("WalkAnim")
			if r15Run and r15Walk then
				r15Run.AnimationId = SPRINT_ANIM_ID
				r15Walk.AnimationId = WALK_ANIM_ID
			end
		end
	end)
end)