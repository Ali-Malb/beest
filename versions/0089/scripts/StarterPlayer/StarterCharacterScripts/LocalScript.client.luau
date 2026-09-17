local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage =  game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ResetEvent = ReplicatedStorage:WaitForChild("ResetToSpawnEvent")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local WS = 10
local RS = 27

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