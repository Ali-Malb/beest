local RUN_ANIM_ID = "rbxassetid://100537298625296"
local WALK_ANIM_ID = "rbxassetid://132749301821841"

print("🔍 DIAGNOSTIC: Script has started running successfully!")

game.Players.PlayerAdded:Connect(function(player)
	print("🔍 DIAGNOSTIC: Player joined: " .. player.Name)

	player.CharacterAdded:Connect(function(character)
		print("🔍 DIAGNOSTIC: Character spawned for: " .. player.Name)

		print("⏳ Waiting for Animate script...")
		local animateScript = character:WaitForChild("Animate", 5)
		if not animateScript then
			warn("❌ ERROR: Failed to find 'Animate' script inside the character within 5 seconds!")
			return
		end

		print("⏳ Waiting for run and walk folders...")
		local runFolder = animateScript:WaitForChild("run", 5)
		local walkFolder = animateScript:WaitForChild("walk", 5)

		if not runFolder or not walkFolder then
			warn("❌ ERROR: Could not find 'run' or 'walk' folders inside the Animate script!")
			return
		end

		print("⏳ Waiting for Animation tracks...")
		local runAnim = runFolder:WaitForChild("Animation", 5)
		local walkAnim = walkFolder:WaitForChild("Animation", 5)

		if not runAnim or not walkAnim then
			warn("❌ ERROR: Could not find the internal 'Animation' object. Are you sure the game is set to R6?")
			return
		end

		-- Apply IDs
		runAnim.AnimationId = RUN_ANIM_ID
		walkAnim.AnimationId = WALK_ANIM_ID
		print("✅ SUCCESS: Both Animation IDs have been injected into your character!")

		-- Boost speed automatically for testing
		character:WaitForChild("Humanoid").WalkSpeed = 26
		print("⚡ SPEED: WalkSpeed forced to 26 for testing.")
	end)
end)