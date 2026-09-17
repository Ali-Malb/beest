local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage =  game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ResetEvent = ReplicatedStorage:WaitForChild("ResetToSpawnEvent")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local WS = 10
local RS = 32

humanoid.WalkSpeed = WS

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		humanoid.WalkSpeed = RS
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		humanoid.WalkSpeed = WS
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.R then
		ResetEvent:FireServer()
	end
end)

local function onTouched(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 32
		humanoid.JumpPower = 5000
	end
	local sprintScript = character:FindFirstChild("LocalScrip")
end