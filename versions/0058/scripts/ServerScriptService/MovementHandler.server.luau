local RUN_ID = "rbxassetid://656118852"
local WALK_ID = "rbxassetid://973766674"

print("🔍 R15 DEBUG: Script has initialized successfully!")

game.Players.PlayerAdded:Connect(function(player)
	print("🔍 R15 DEBUG: Player joined -> " .. player.Name)
	player.CharacterAdded:Connect(function(char)
		print("🔍 R15 DEBUG: Character spawned!")

		local animateScript = char:WaitForChild("Animate", 5)
		if not animateScript then
			warn("❌ R15 DEBUG: Failed to find the 'Animate' script inside your character!")
			return
		end

		local walkfolder = animateScript:WaitForChild("walk", 5)
		local runfolder = animateScript:WaitForChild("run", 5)
		if not walkfolder or not runfolder then
			warn("❌ R15 DEBUG: Missing the walk or run folders inside the Animate script!")
			return
		end

		local walkAnim  =  walkfolder:WaitForChild("Animation1", 5) or walkfolder:FindFirstChildWhichIsA("Animation")
		local runAnim   =  runfolder:WaitForChild("Animation1", 5) or runfolder:FindFirstChildWhichIsA("Animation")

		if walkAnim then 
			walkAnim.AnimationId = WALK_ID 
			print("✅ R15 DEBUG: Successfully injected custom Walk ID!")
		else 
			warn("❌ R15 DEBUG: Could not find the internal Walk Animation object!") 
		end

		if runAnim then 
			runAnim.AnimationId = RUN_ID 
			print("✅ R15 DEBUG: Successfully injected Ninja Run ID!")
		else 
			warn("❌ R15 DEBUG: Could not find the internal Run Animation object!") 
		end

		local humanoid = char:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.WalkSpeed = 7 -- Keeping it at 27 for this test so we can force the Ninja run to trigger!
			print("⚡ R15 DEBUG: WalkSpeed forced to 27!")
		end
	end)
end)