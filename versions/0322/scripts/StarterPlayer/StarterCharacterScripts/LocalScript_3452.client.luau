local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local character
local humanoid
local root

local speedParticles
local trail
local trailAttachment1
local trailAttachment2

-- SETTINGS
local NORMAL_FOV = 70
local MAX_FOV = 100
local MAX_SPEED = 200

local MIN_TRAIL_SPEED = 75

local FALL_HEIGHT_REQUIRED = 100
local LANDING_EFFECT_TIME = 0.75

local fallStartY = nil
local wasFalling = false
local landingDebounce = false


--------------------------------------------------
-- CHARACTER SETUP
--------------------------------------------------

local function setupCharacter(char)

	character = char
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")

	camera.FieldOfView = NORMAL_FOV

	fallStartY = nil
	wasFalling = false
	landingDebounce = false


	--------------------------------------------------
	-- SPEED PARTICLES
	--------------------------------------------------

	speedParticles = Instance.new("ParticleEmitter")
	speedParticles.Name = "SpeedParticles"
	speedParticles.Parent = root

	speedParticles.Enabled = false
	speedParticles.Rate = 0

	speedParticles.Lifetime = NumberRange.new(0.15, 0.35)
	speedParticles.Speed = NumberRange.new(25, 45)

	speedParticles.SpreadAngle = Vector2.new(180, 180)

	speedParticles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0)
	})

	speedParticles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1)
	})

	speedParticles.EmissionDirection = Enum.NormalId.Back


	--------------------------------------------------
	-- SPEED TRAIL
	--------------------------------------------------

	trailAttachment1 = Instance.new("Attachment")
	trailAttachment1.Name = "SpeedTrailTop"
	trailAttachment1.Position = Vector3.new(0, 1.2, 0)
	trailAttachment1.Parent = root

	trailAttachment2 = Instance.new("Attachment")
	trailAttachment2.Name = "SpeedTrailBottom"
	trailAttachment2.Position = Vector3.new(0, -1.2, 0)
	trailAttachment2.Parent = root

	trail = Instance.new("Trail")
	trail.Name = "SpeedTrail"

	trail.Attachment0 = trailAttachment1
	trail.Attachment1 = trailAttachment2

	trail.Parent = root

	trail.Enabled = false

	trail.Lifetime = 0.25

	trail.MinLength = 0.1

	trail.FaceCamera = true

	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1)
	})

end


--------------------------------------------------
-- LANDING CLOUD EFFECT
--------------------------------------------------

local function createLandingEffect()

	if landingDebounce then
		return
	end

	landingDebounce = true

	-- Invisible attachment at player's feet
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, -2.5, 0)
	attachment.Parent = root

	-- CLOUD / DUST
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "LandingCloud"
	dust.Parent = attachment

	dust.Enabled = true

	dust.Rate = 0

	dust.Lifetime = NumberRange.new(0.4, 0.75)

	dust.Speed = NumberRange.new(12, 25)

	dust.SpreadAngle = Vector2.new(180, 180)

	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(0.4, 3),
		NumberSequenceKeypoint.new(1, 0)
	})

	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.7, 0.6),
		NumberSequenceKeypoint.new(1, 1)
	})

	-- Emit a burst
	dust:Emit(35)

	-- Remove after 0.75 seconds
	Debris:AddItem(attachment, LANDING_EFFECT_TIME)

	task.delay(0.9, function()
		landingDebounce = false
	end)

end


--------------------------------------------------
-- FALL DETECTION
--------------------------------------------------

humanoid.StateChanged:Connect(function(oldState, newState)

	-- Start tracking fall
	if newState == Enum.HumanoidStateType.Freefall then

		if not wasFalling then
			fallStartY = root.Position.Y
			wasFalling = true
		end

	end


	-- Player lands
	if wasFalling and (
		newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
		) then

		if fallStartY then

			local fallDistance =
				fallStartY - root.Position.Y

			print("[LANDING] Fall distance:", fallDistance)

			if fallDistance >= FALL_HEIGHT_REQUIRED then
				createLandingEffect()
			end

		end

		fallStartY = nil
		wasFalling = false

	end

end)


--------------------------------------------------
-- UPDATE EVERY FRAME
--------------------------------------------------

RunService.RenderStepped:Connect(function()

	if not humanoid or not root then
		return
	end

	local velocity = root.AssemblyLinearVelocity

	local horizontalVelocity = Vector3.new(
		velocity.X,
		0,
		velocity.Z
	)

	local speed = horizontalVelocity.Magnitude

	-- 0 → 200 = 0 → 1
	local alpha = math.clamp(
		speed / MAX_SPEED,
		0,
		1
	)


	--------------------------------------------------
	-- FOV
	--------------------------------------------------

	local targetFOV =
		NORMAL_FOV +
		((MAX_FOV - NORMAL_FOV) * alpha)

	camera.FieldOfView =
		camera.FieldOfView +
		(targetFOV - camera.FieldOfView) * 0.1


	--------------------------------------------------
	-- SPEED PARTICLES
	--------------------------------------------------

	if speed >= 100 then

		speedParticles.Enabled = true

		speedParticles.Rate =
			10 + (alpha * 70)

	else

		speedParticles.Enabled = false
		speedParticles.Rate = 0

	end


	--------------------------------------------------
	-- TRAIL
	--------------------------------------------------

	if speed >= MIN_TRAIL_SPEED then

		trail.Enabled = true

		-- Trail gets longer at higher speed
		trail.Lifetime =
			0.08 + (alpha * 0.3)

	else

		trail.Enabled = false

	end

end)


--------------------------------------------------
-- START CHARACTER
--------------------------------------------------

if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)