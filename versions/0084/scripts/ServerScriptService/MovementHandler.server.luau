local ReplicatedStorage = game:GetService("ReplicatedStorage")
local R_ID = "rbxassetid://656118852"
local W_ID = "rbxassetid://782842708"

local ResetEvent = ReplicatedStorage:WaitForChild("ResetEvent") or Instance.new("RemoteEvent")
ResetEvent.Name = "ResetToSpawnEvent"
ResetEvent.Parent = ReplicatedStorage

local playerLastSpawn = {}

for _, desc in ipairs(workspace:GetDescendants()) do
	if desc:IsA("SpawnLocation") then
		desc.Touched:Connect(function(hit)
			local player = game.Players:GetPlayerFromCharacter(hit.Parent)
			if player then
				playerLastSpawn[player.UserId] = desc
			end
		end)
	end
end

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local animateScript = character:WaitForChild("Animate")
		local humanoid = character:WaitForChild("Humanoid")
		
		local walkfolder = animateScript:WaitForChild("walk")
		local runfolder = animateScript:WaitForChild("run")
		
		for _, child in ipairs(walkfolder:GetChildren()) do 
			if child:IsA("Animation") then
				child.AnimationId = W_ID
			end
		end
		
		for _, child in ipairs(runfolder:GetChildren()) do 
			if child:IsA("Animation") then
				child.AnimationId = R_ID
			end
		end
	
	local animator  = humanoid:WaitForChild("Animator", 5)
	if animator then task.wait(.1)
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do 
			track:Stop()
		end
	end
		humanoid.WalkSpeed = 10
	end)
end)

ResetEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	local  rootPart = char and char:FindFirstChild("HumanoidRootPart")
	local humaniod  = char and char:FindFirstChild("Humanoid")
	
	if rootPart and humaniod.Health > 0 then
		local targetSpawn = playerLastSpawn[player.UserId] or workspace:FindFirstChildOfClass("SpawnLocation")
		
		if targetSpawn then
			rootPart.CFrame = targetSpawn.CFrame + Vector3.new(0, 5, 0)
		end
	end
end)