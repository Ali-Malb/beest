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

--==================================================
-- SETTINGS
--==================================================

local NORMAL_FOV = 70
local MAX_FOV = 100
local MAX_SPEED = 200

local MIN_TRAIL_SPEED = 75
local PARTICLE_START_SPEED = 100

local FALL_HEIGHT_REQUIRED = 100

local LANDING_EFFECT_TIME = 0.75

local CAMERA_SHAKE_MAX = 1.5
local CAMERA_SHAKE_TIME = 0.35

--==================================================
-- FALL VARIABLES
--==================================================

local highestFallY = nil
local falling = false
local landingDebounce = false

--==================================================
-- DEBUG
--==================================================

local function debug(message)

	print(
		"[EFFECTS] "
			.. message
	)

end

debug("SCRIPT STARTED")

--==================================================
-- CAMERA SHAKE
--==================================================

local shakeEndTime = 0
local shakeStrength = 0

local function cameraShake(strength, duration)

	debug(
		"Camera shake triggered | Strength: "
			.. tostring(strength)
			.. " | Duration: "
			.. tostring(duration)
	)

	shakeStrength = math.max(
		shakeStrength,
		strength
	)

	shakeEndTime = math.max(
		shakeEndTime,
		os.clock() + duration
	)

end

--==================================================
-- LANDING CLOUD
--==================================================

local function createLandingEffect(fallDistance)

	if landingDebounce then

		debug("Landing effect blocked by debounce")

		return

	end

	landingDebounce = true

	debug(
		"💥 CREATING LANDING EFFECT | Fall: "
			.. string.format("%.1f", fallDistance)
			.. " studs"
	)

	-- Attachment at feet
	local attachment = Instance.new("Attachment")

	attachment.Name = "LandingEffect"

	attachment.Position =
		Vector3.new(0, -2.5, 0)

	attachment.Parent = root


	--==================================================
	-- CLOUD
	--==================================================

	local cloud = Instance.new("ParticleEmitter")

	cloud.Name = "LandingCloud"

	cloud.Parent = attachment

	cloud.Rate = 0

	cloud.Lifetime =
		NumberRange.new(
			0.45,
			0.75
		)

	cloud.Speed =
		NumberRange.new(
			10,
			25
		)

	cloud.SpreadAngle =
		Vector2.new(
			180,
			180
		)

	cloud.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				1
			),

			NumberSequenceKeypoint.new(
				0.35,
				3
			),

			NumberSequenceKeypoint.new(
				1,
				0
			)
		})

	cloud.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.2
			),

			NumberSequenceKeypoint.new(
				0.7,
				0.6
			),

			NumberSequenceKeypoint.new(
				1,
				1
			)
		})

	cloud:Emit(40)

	-- Remove after requested duration
	Debris:AddItem(
		attachment,
		LANDING_EFFECT_TIME
	)


	--==================================================
	-- CAMERA SHAKE
	--==================================================

	local fallAlpha = math.clamp(
		fallDistance / 500,
		0,
		1
	)

	local shakeAmount =
		0.3
		+ (
			CAMERA_SHAKE_MAX
			* fallAlpha
		)

	cameraShake(
		shakeAmount,
		CAMERA_SHAKE_TIME
	)

	-- Release debounce
	task.delay(
		1,
		function()

			landingDebounce = false

		end
	)

end

--==================================================
-- CHARACTER SETUP
--==================================================

local function setupCharacter(char)

	character = char

	humanoid =
		char:WaitForChild(
			"Humanoid"
		)

	root =
		char:WaitForChild(
			"HumanoidRootPart"
		)

	debug(
		"Character setup complete"
	)

	highestFallY = nil
	falling = false
	landingDebounce = false


	--==================================================
	-- SPEED PARTICLES
	--==================================================

	speedParticles =
		Instance.new(
			"ParticleEmitter"
		)

	speedParticles.Name =
		"SpeedParticles"

	speedParticles.Parent =
		root

	speedParticles.Enabled = false

	speedParticles.Rate = 0

	-- CHANGED TO 1 SECOND
	speedParticles.Lifetime =
		NumberRange.new(
			1,
			1
		)

	speedParticles.Speed =
		NumberRange.new(
			25,
			45
		)

	speedParticles.SpreadAngle =
		Vector2.new(
			180,
			180
		)

	speedParticles.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.12
			),

			NumberSequenceKeypoint.new(
				1,
				0
			)
		})

	speedParticles.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.15
			),

			NumberSequenceKeypoint.new(
				1,
				1
			)
		})

	speedParticles.EmissionDirection =
		Enum.NormalId.Back


	--==================================================
	-- SPEED TRAIL
	--==================================================

	trailAttachment1 =
		Instance.new(
			"Attachment"
		)

	trailAttachment1.Name =
		"SpeedTrailTop"

	trailAttachment1.Position =
		Vector3.new(
			0,
			1.2,
			0
		)

	trailAttachment1.Parent =
		root


	trailAttachment2 =
		Instance.new(
			"Attachment"
		)

	trailAttachment2.Name =
		"SpeedTrailBottom"

	trailAttachment2.Position =
		Vector3.new(
			0,
			-1.2,
			0
		)

	trailAttachment2.Parent =
		root


	trail =
		Instance.new(
			"Trail"
		)

	trail.Name =
		"SpeedTrail"

	trail.Attachment0 =
		trailAttachment1

	trail.Attachment1 =
		trailAttachment2

	trail.Parent =
		root

	trail.Enabled = false

	trail.Lifetime = 0.25

	trail.MinLength = 0.1

	trail.FaceCamera = true

	trail.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.15
			),

			NumberSequenceKeypoint.new(
				1,
				1
			)
		})


	debug(
		"Speed particles + trail created"
	)

end

--==================================================
-- CONTINUOUS FALL DETECTION
--==================================================

RunService.Heartbeat:Connect(function()

	if not humanoid
		or not root then

		return

	end


	local state =
		humanoid:GetState()


	--==================================================
	-- FALLING
	--==================================================

	if state ==
		Enum.HumanoidStateType.Freefall
		or state ==
		Enum.HumanoidStateType.FallingDown then

		if not falling then

			falling = true

			highestFallY =
				root.Position.Y

			debug(
				"⬇️ FALL STARTED | Y="
					.. string.format(
						"%.1f",
						highestFallY
					)
			)

		else

			-- Track highest point
			highestFallY =
				math.max(
					highestFallY,
					root.Position.Y
				)

		end

	end


	--==================================================
	-- LANDED
	--==================================================

	if falling then

		local grounded =
			state ==
			Enum.HumanoidStateType.Landed
			or state ==
			Enum.HumanoidStateType.Running
			or state ==
			Enum.HumanoidStateType.RunningNoPhysics


		if grounded then

			local landingY =
				root.Position.Y

			local fallDistance =
				highestFallY
			- landingY


			debug(
				"⬆️ LANDING DETECTED | Fall distance="
					.. string.format(
						"%.1f",
						fallDistance
					)
					.. " studs"
			)


			if fallDistance
				>= FALL_HEIGHT_REQUIRED then

				debug(
					"🔥 FALL WAS OVER "
						.. FALL_HEIGHT_REQUIRED
						.. " STUDS!"
				)

				createLandingEffect(
					fallDistance
				)

			else

				debug(
					"Fall too small for effect"
				)

			end


			falling = false

			highestFallY = nil

		end

	end

end)

--==================================================
-- SPEED + FOV
--==================================================

RunService.RenderStepped:Connect(function()

	if not humanoid
		or not root then

		return

	end


	--==================================================
	-- CAMERA SHAKE
	--==================================================

	if os.clock()
		< shakeEndTime then

		local x =
			(math.random() - 0.5)
			* shakeStrength

		local y =
			(math.random() - 0.5)
			* shakeStrength

		local z =
			(math.random() - 0.5)
			* shakeStrength


		camera.CFrame =
			camera.CFrame
			* CFrame.new(
				x,
				y,
				z
			)

	else

		shakeStrength = 0

	end


	--==================================================
	-- SPEED
	--==================================================

	local velocity =
		root.AssemblyLinearVelocity


	local horizontalVelocity =
		Vector3.new(
			velocity.X,
			0,
			velocity.Z
		)


	local speed =
		horizontalVelocity.Magnitude


	local alpha =
		math.clamp(
			speed / MAX_SPEED,
			0,
			1
		)


	--==================================================
	-- FOV
	--==================================================

	local targetFOV =
		NORMAL_FOV
		+ (
			(MAX_FOV - NORMAL_FOV)
			* alpha
		)


	camera.FieldOfView =
		camera.FieldOfView
		+ (
			targetFOV
			- camera.FieldOfView
		)
		* 0.1


	--==================================================
	-- SPEED PARTICLES
	--==================================================

	if speed
		>= PARTICLE_START_SPEED then

		speedParticles.Enabled = true

		speedParticles.Rate =
			10
			+ (
				alpha
				* 70
			)

	else

		speedParticles.Enabled = false

		speedParticles.Rate = 0

	end


	--==================================================
	-- TRAIL
	--==================================================

	if speed
		>= MIN_TRAIL_SPEED then

		trail.Enabled = true

		trail.Lifetime =
			0.08
			+ (
				alpha
				* 0.3
			)

	else

		trail.Enabled = false

	end

end)

--==================================================
-- START
--==================================================

if player.Character then

	setupCharacter(
		player.Character
	)

end

player.CharacterAdded:Connect(
	setupCharacter
)

debug(
	"ALL EFFECT SYSTEMS READY"
)