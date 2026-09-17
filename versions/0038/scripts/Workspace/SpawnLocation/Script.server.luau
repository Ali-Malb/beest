local RUN_ANIM_ID = "rbxassetid://100537298625296"
local WALK_ANIM_ID = "rbxassetid://132749301821841"

print("🔍 DIAGNOSTIC: Upgraded Hybrid Script Active!")

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local animateScript = character:WaitForChild("Animate", 5)
		if not animateScript then return end

		local runFolder = animateScript:WaitForChild("run", 5)
		local walkFolder = animateScript:WaitForChild("walk", 5)
		if not runFolder or not walkFolder then return end

		-- 📁 Dynamic Detection: Checks if game is running R6 or R15 structure
		local runAnim = runFolder:FindFirstChild("Animation") or runFolder:FindFirstChild("RunAnim")
		local walkAnim = walkFolder:FindFirstChild("Animation") or walkFolder:FindFirstChild("WalkAnim")

		if runAnim and walkAnim then
			runAnim.AnimationId = RUN_ANIM_ID
			walkAnim.AnimationId = WALK_ANIM_ID
			print("✅ SUCCESS: Animation IDs injected successfully!")
		else
			warn("❌ ERROR: Could not find animation track targets inside folders.")
		end

		-- Force speed boost for testing
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = 26
	end)
end)