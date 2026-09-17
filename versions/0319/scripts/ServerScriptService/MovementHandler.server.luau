local ReplicatedStorage = game:GetService("ReplicatedStorage")
local R_ID = "rbxassetid://656118852"
local W_ID = "rbxassetid://782842708"
local J_ID = "rbxassetid://891627522"
local F_ID = "rbxassetid://507767714" -- 🛠️ Replaced broken Fall ID

local ResetEvent = ReplicatedStorage:FindFirstChild("ResetToSpawnEvent") or Instance.new("RemoteEvent")
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
		local jumpfolder = animateScript:WaitForChild("jump")
		local fallfolder = animateScript:WaitForChild("fall")

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

		for _, child in ipairs(jumpfolder:GetChildren()) do 
			if child:IsA("Animation") then
				child.AnimationId = J_ID
			end
		end

		for _, child in ipairs(fallfolder:GetChildren()) do 
			if child:IsA("Animation") then
				child.AnimationId = F_ID
			end
		end

		local animator = humanoid:WaitForChild("Animator", 5)
		if animator then 
			task.wait(0.1)
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do 
				track:Stop()
				track:Destroy() -- 🛠️ Flushes track instances to prevent hitting the 64-track limit
			end
		end
		humanoid.WalkSpeed = 10
	end)
end)

ResetEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChild("Humanoid")

	if rootPart and humanoid and humanoid.Health > 0 then
		local targetSpawn = playerLastSpawn[player.UserId] or workspace:FindFirstChildOfClass("SpawnLocation")

		if targetSpawn then
			rootPart.CFrame = targetSpawn.CFrame + Vector3.new(0, 5, 0)
		end
	end
end)

for _, obj in ipairs(workspace:GetDescendants()) do 
	if obj.Name == "ResetPart" then
		if obj:IsA("BasePart") then
			obj.Touched:Connect(function(hit)
				local player = game.Players:GetPlayerFromCharacter(hit.Parent)
				if player then
					local char = player.Character
					local rootPart = char and char:FindFirstChild("HumanoidRootPart")
					local humanoid = char and char:FindFirstChild("Humanoid")

					if rootPart and humanoid and humanoid.Health > 0 then 
						local targetSpawn = playerLastSpawn[player.UserId] or workspace:FindFirstChildOfClass("SpawnLocation")
						if targetSpawn then
							rootPart.CFrame = targetSpawn.CFrame + Vector3.new(0, 5, 0)
						end
					end
				end
			end)
		elseif obj:IsA("Model") then
			for _, part in ipairs(obj:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Touched:Connect(function(hit)
						local player = game.Players:GetPlayerFromCharacter(hit.Parent)
						if player then
							local char = player.Character
							local rootPart = char and char:FindFirstChild("HumanoidRootPart")
							local humanoid = char and char:FindFirstChild("Humanoid")

							if rootPart and humanoid and humanoid.Health > 0 then 
								local targetSpawn = playerLastSpawn[player.UserId] or workspace:FindFirstChildOfClass("SpawnLocation")
								if targetSpawn then
									rootPart.CFrame = targetSpawn.CFrame + Vector3.new(0, 5, 0)
								end
							end
						end
					end)
				end
			end
		end
	end
end