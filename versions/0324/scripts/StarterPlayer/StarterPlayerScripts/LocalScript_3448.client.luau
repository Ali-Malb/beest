local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("PickUpBacon")

-- Create notification GUI
local gui = Instance.new("ScreenGui")
gui.Name = "BaconNotification"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local notification = Instance.new("TextLabel")
notification.Name = "Notification"
notification.Parent = gui

notification.AnchorPoint = Vector2.new(0.5, 0)
notification.Position = UDim2.new(0.5, 0, -0.12, 0)
notification.Size = UDim2.new(0, 400, 0, 65)

notification.BackgroundTransparency = 1
notification.Text = "🥓 BACON COLLECTED!"
notification.TextScaled = true
notification.Font = Enum.Font.FredokaOne

notification.TextColor3 = Color3.fromRGB(255, 255, 255)
notification.TextStrokeColor3 = Color3.fromRGB(70, 35, 15)
notification.TextStrokeTransparency = 0

notification.Visible = false
notification.ZIndex = 100

local showing = false

remote.OnClientEvent:Connect(function()

	-- Restart notification if collected again
	if showing then
		return
	end

	showing = true
	notification.Visible = true

	-- Start above screen
	notification.Position =
		UDim2.new(0.5, 0, -0.12, 0)

	notification.TextTransparency = 0
	notification.TextStrokeTransparency = 0

	-- Slide down
	local slideIn = TweenService:Create(
		notification,
		TweenInfo.new(
			0.35,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		),
		{
			Position = UDim2.new(0.5, 0, 0.06, 0)
		}
	)

	slideIn:Play()
	slideIn.Completed:Wait()

	-- Stay visible
	task.wait(1)

	-- Slide/fade out
	local slideOut = TweenService:Create(
		notification,
		TweenInfo.new(
			0.3,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{
			Position = UDim2.new(0.5, 0, -0.12, 0),
			TextTransparency = 1,
			TextStrokeTransparency = 1
		}
	)

	slideOut:Play()
	slideOut.Completed:Wait()

	notification.Visible = false
	showing = false

end)