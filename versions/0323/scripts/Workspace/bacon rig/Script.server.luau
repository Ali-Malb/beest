local model = script.Parent
local clickDetector = model:FindFirstChild("ClickDetector", true)
local remote = game.ReplicatedStorage:WaitForChild("PickUpBacon")

local baconTemplate = game.ServerStorage:WaitForChild("BaconBack")

clickDetector.MouseClick:Connect(function(player)

	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	humanoid.WalkSpeed += 25
	humanoid.JumpHeight += 25

	if character:FindFirstChild("BaconBack") then return end

	local upperTorso = character:FindFirstChild("UpperTorso")
	if not upperTorso then warn("no uppertorso") return end

	local bacon = baconTemplate:Clone()
	bacon:ScaleTo(.54)
	bacon.Name = "BaconBack"	
	bacon.Parent = character 
	local baconHumanoid = bacon:FindFirstChild("Humanoid")
	if baconHumanoid then 
		baconHumanoid.PlatformStand = true
		baconHumanoid.AutoRotate = false
		baconHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		baconHumanoid.BreakJointsOnDeath = false
	end
	
	
	local baconRoot = bacon:WaitForChild("HumanoidRootPart")

	for _, obj in ipairs(bacon:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = false
			obj.CanTouch= false 
			obj.CanQuery = false
			obj.CanCollide = false
			obj.Massless = true
		end
	end

	bacon:PivotTo(
		upperTorso.CFrame * CFrame.new(0,0.5,1) * CFrame.Angles(0, math.rad(180), 0))


	local weld = Instance.new("WeldConstraint")
	weld.Part0 = upperTorso
	weld.Part1 = baconRoot
	weld.Parent = baconRoot

	print(player.Name .. " clicked")
	remote:FireClient(player, model)
	
	
end)