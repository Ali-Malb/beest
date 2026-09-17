local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local Walk = 10
local Run = 30

humanoid.WalkSpeed = Walk

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed 
end)