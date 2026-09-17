local player = game.Players.LocalPlayer
local RunService = game:GetService("RunService")

local gui = script.Parent

-- TIMER LABEL
local label = Instance.new("TextLabel")
label.Name = "SpeedrunTimer"
label.Parent = gui

-- TOP RIGHT
label.AnchorPoint = Vector2.new(1, 0)
label.Position = UDim2.new(0.97, 0, 0.035, 0)
label.Size = UDim2.new(0, 300, 0, 55)

-- NO BACKGROUND
label.BackgroundTransparency = 1
label.BorderSizePixel = 0

-- TEXT
label.Text = "🕐 00:00.000"
label.TextScaled = true
label.Font = Enum.Font.FredokaOne

-- OUTLINE
label.TextStrokeTransparency = 0.75
label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

-- Make sure it stays above everything
label.ZIndex = 100

local startTime = nil
local finished = false
local showingNewBest = false

local function formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	local milliseconds = math.floor((seconds % 1) * 1000)

	return string.format("🕐 %02d:%02d.%03d", minutes, secs, milliseconds)
end

-- High contrast based on what's behind the timer
local function updateContrast()
	if showingNewBest then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local viewport = camera.ViewportSize

	-- Sample near the timer
	local x = viewport.X * 0.88
	local y = viewport.Y * 0.065

	local ray = camera:ViewportPointToRay(x, y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		player.Character
	}

	local result = workspace:Raycast(
		ray.Origin,
		ray.Direction * 1000,
		params
	)

	if result then
		local color = result.Instance.Color

		local brightness =
			0.299 * color.R +
			0.587 * color.G +
			0.114 * color.B

		if brightness > 0.55 then
			label.TextColor3 = Color3.fromRGB(20, 20, 20)
			label.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		else
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		end
	else
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	end
end

local function updateTimer()
	if startTime and not finished and not showingNewBest then
		local elapsed = os.clock() - startTime
		label.Text = formatTime(elapsed)
	end
end

-- NEW BEST ANIMATION
local function showNewBest(finalTime)
	showingNewBest = true
	finished = true

	local timeText = formatTime(finalTime)

	for i = 1, 8 do
		if i % 2 == 1 then
			label.Text = "🏆 NEW TIME SET!!"
			label.TextColor3 = Color3.fromRGB(255, 215, 0)
			label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		else
			label.Text = timeText
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		end

		task.wait(0.22)
	end

	-- IMPORTANT:
	-- Leave the final time visible after the animation
	label.Text = timeText
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

	showingNewBest = false
end

-- FINISH
player:GetAttributeChangedSignal("FinalTime"):Connect(function()

	local finalTime = player:GetAttribute("FinalTime")
	local newBest = player:GetAttribute("NewBest")

	if finalTime then

		if newBest then
			task.spawn(function()
				showNewBest(finalTime)
			end)
		else
			finished = true
			label.Text = formatTime(finalTime)
		end

	end
end)

-- CHARACTER SETUP
local function setupCharacter(character)

	local humanoid = character:WaitForChild("Humanoid")

	startTime = nil
	finished = false
	showingNewBest = false

	label.Text = "🕐 00:00.000"

	humanoid.Running:Connect(function(speed)

		if speed > 0 and not startTime and not finished then
			startTime = os.clock()
		end

	end)
end

if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

-- UPDATE
RunService.RenderStepped:Connect(function()
	updateTimer()
	updateContrast()
end)