local player = game.Players.LocalPlayer
local label = script.Parent

local startTime = nil
local finished = false

local function formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	local milliseconds = math.floor((seconds % 1) * 1000)

	return string.format("%02d:%02d.%03d", minutes, secs, milliseconds)
end

local function updateTimer()
	if startTime and not finished then
		local elapsed = os.clock() - startTime
		label.Text = formatTime(elapsed)
	end
end

-- Timer stops when the server says the player finished
player:GetAttributeChangedSignal("FinalTime"):Connect(function()
	local finalTime = player:GetAttribute("FinalTime")

	if finalTime then
		finished = true
		label.Text = formatTime(finalTime)
	end
end)

-- Start timer when player moves
local function setupCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")

	startTime = nil
	finished = false
	label.Text = "00:00.000"

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

-- Update timer every frame
game:GetService("RunService").RenderStepped:Connect(updateTimer)