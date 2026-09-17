local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local character
local humanoid
local root
local particles

local NORMAL_FOV = 70
local MAX_FOV = 100

local MAX_SPEED = 200

local function setupCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")

	camera.FieldOfView = NORMAL_FOV

	-- Speed particles
	particles = Instance.new("ParticleEmitter")
	particles.Name = "SpeedParticles"
	particles.Parent = root

	particles.Enabled = false
	particles.Rate = 0

	particles.Lifetime = NumberRange.new(0.15, 0.35)
	particles.Speed = NumberRange.new(25, 45)
	particles.SpreadAngle = Vector2.new(180, 180)

	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0)
	})

	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1)
	})

	particles.EmissionDirection = Enum.NormalId.Back
end

if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

RunService.RenderStepped:Connect(function()

	if not humanoid or not root or not particles then
		return
	end

	local speed = root.AssemblyLinearVelocity.Magnitude

	-- 0 → 200 becomes 0 → 1
	local alpha = math.clamp(speed / MAX_SPEED, 0, 1)

	-- =========================
	-- FOV
	-- =========================

	local targetFOV =
		NORMAL_FOV +
		((MAX_FOV - NORMAL_FOV) * alpha)

	camera.FieldOfView =
		camera.FieldOfView +
		(targetFOV - camera.FieldOfView) * 0.1

	-- =========================
	-- SPEED PARTICLES
	-- =========================

	if speed >= 100 then

		particles.Enabled = true

		-- 100 speed = small amount
		-- 200 speed = maximum amount
		particles.Rate = 10 + (alpha * 70)

	else

		particles.Enabled = false
		particles.Rate = 0

	end

end)