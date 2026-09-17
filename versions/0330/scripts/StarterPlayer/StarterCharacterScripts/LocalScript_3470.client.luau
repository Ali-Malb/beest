--[[
    PHYSICAL LOOP-THE-LOOP SYSTEM
    Roblox LocalScript

    EXPECTED SETUP:
        Workspace
          └─ RLoop
               ├─ 1
               ├─ 2
               ├─ ...
               └─ 30

    Each numbered object may be a BasePart or a Model containing BaseParts.

    Put this LocalScript in:
        StarterPlayer > StarterPlayerScripts

    IMPORTANT:
    - The physical loop geometry is used by raycasts for the final character position.
    - No camera properties are changed outside the loop.
    - There is NO 30 -> 1 wrap.
    - Section 1 is the terminal section.
    - The character is always placed from the INNER FACE of the physical track.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------

local LOOP_FOLDER_NAME = "RLoop"

local FIRST_SECTION = 30
local LAST_SECTION = 1

local TRACK_OFFSET = 2
local LOOP_SPEED = 45

-- Camera
local CAMERA_RETURN_SECTIONS = 5
local CAMERA_BLEND_POWER = 2.0

local cameraControlling = false
local originalCameraType
local originalCameraSubject
local originalCameraCFrame
local originalCameraFocus
local loopCameraCFrame

-- Raycasting
local RAY_START_DISTANCE = 20
local RAY_LENGTH = 45

-- Debug
local DEBUG_ENABLED = true
local DEBUG_PRINT_INTERVAL = 0.15
local DEBUG_MARKERS = false

-- Animation
local LOOP_ANIMATION_FADE = 0.12
local LOOP_ANIMATION_SPEED_MIN = 0.85
local LOOP_ANIMATION_SPEED_MAX = 2.75

----------------------------------------------------------------
-- REFERENCES
----------------------------------------------------------------

local loopFolder =
	workspace:WaitForChild(LOOP_FOLDER_NAME)

local character
local humanoid
local root

local sections = {}
local sectionCenters = {}

local running = false
local loopActive = false

local currentSection = FIRST_SECTION
local sectionProgress = 0
local pathDistance = 0

local NORMAL_WALK_SPEED = 50

local oldWalkSpeed = NORMAL_WALK_SPEED
local oldAutoRotate = true
local oldCanCollide = {}

local loopAnimationTrack = nil
local loopAnimationObject = nil

----------------------------------------------------------------
-- DEBUG STATE
----------------------------------------------------------------

local debugFolder

local debugState = {
	status = "IDLE",
	section = 0,
	progress = 0,

	hitName = "NONE",
	hitSection = 0,
	expectedSection = 0,

	rayHit = false,

	surfaceDistance = 0,
	targetDistance = TRACK_OFFSET,
	bodySupportDistance = 0,

	rayOrigin = Vector3.zero,
	rayEnd = Vector3.zero,

	targetPosition = Vector3.zero,

	tangent = Vector3.zero,
	inward = Vector3.zero,

	error = "",
}

local function dprint(...)
	if DEBUG_ENABLED then
		print("[LOOP DEBUG]", ...)
	end
end

local function drawDebug()
	-- Intentionally disabled.
end

local function clearDebug()
	if debugFolder then
		debugFolder:Destroy()
		debugFolder = nil
	end
end

local lastDebugPrint = 0

local function debugFrame(now)
	if not DEBUG_ENABLED then
		return
	end

	if now - lastDebugPrint < DEBUG_PRINT_INTERVAL then
		return
	end

	lastDebugPrint = now

	print(
		"[LOOP DEBUG]",
		"status=", debugState.status,
		"section=", debugState.section,
		"progress=", string.format("%.3f", debugState.progress),
		"hit=", debugState.hitName,
		"hitSection=", debugState.hitSection,
		"surface=", string.format("%.3f", debugState.surfaceDistance),
		"error=", debugState.error
	)
end

----------------------------------------------------------------
-- FIND BASEPARTS
----------------------------------------------------------------

local function getPartsFromSection(object)

	local result = {}

	if object:IsA("BasePart") then

		table.insert(result, object)

	else

		for _, descendant in ipairs(object:GetDescendants()) do

			if descendant:IsA("BasePart") then
				table.insert(result, descendant)
			end

		end

	end

	return result
end

----------------------------------------------------------------
-- SECTION CENTER
----------------------------------------------------------------

local function getSectionCenter(object)

	if object:IsA("BasePart") then
		return object.Position
	end

	local parts =
		getPartsFromSection(object)

	if #parts == 0 then
		return nil
	end

	local sum = Vector3.zero

	for _, p in ipairs(parts) do
		sum += p.Position
	end

	return sum / #parts
end

----------------------------------------------------------------
-- LOAD SECTIONS
----------------------------------------------------------------

local function loadSections()

	table.clear(sections)
	table.clear(sectionCenters)

	for i = LAST_SECTION, FIRST_SECTION do

		local object =
			loopFolder:FindFirstChild(tostring(i))

		if not object then
			error(
				"LOOP ERROR: Missing Workspace.RLoop."
					.. i
			)
		end

		local parts =
			getPartsFromSection(object)

		if #parts == 0 then
			error(
				"LOOP ERROR: Section "
					.. i
					.. " contains no BaseParts"
			)
		end

		local center =
			getSectionCenter(object)

		if not center then
			error(
				"LOOP ERROR: Could not calculate center of section "
					.. i
			)
		end

		sections[i] = {
			object = object,
			parts = parts,
			center = center,
		}

		sectionCenters[i] = center

		dprint(
			"Loaded section",
			i,
			object:GetFullName()
		)
	end

	print("==========================================")
	print("PHYSICAL LOOP SYSTEM READY")
	print(
		"Sections:",
		FIRST_SECTION,
		"->",
		LAST_SECTION
	)
	print("Track offset:", TRACK_OFFSET)
	print("Loop speed:", LOOP_SPEED)
	print("WASD speed:", NORMAL_WALK_SPEED)
	print("Ray start:", RAY_START_DISTANCE)
	print("Ray length:", RAY_LENGTH)
	print("Debug:", DEBUG_ENABLED)
	print(
		"Camera/loop inactive until sections 30, 29, or 28 are touched"
	)
	print("==========================================")
end

----------------------------------------------------------------
-- PATH GEOMETRY
----------------------------------------------------------------

local function getPathPoint(
	sectionNumber,
	progress
)

	progress =
		math.clamp(progress, 0, 1)

	local a =
		sectionCenters[sectionNumber]

	local b

	if sectionNumber > LAST_SECTION then

		b =
			sectionCenters[
		sectionNumber - 1
		]

	else

		local previous =
			sectionCenters[
		LAST_SECTION + 1
		]

		local final =
			sectionCenters[
		LAST_SECTION
		]

		b =
			final +
			(final - previous)

	end

	return a:Lerp(b, progress)
end

----------------------------------------------------------------
-- TANGENT
----------------------------------------------------------------

local function getTangent(sectionNumber)

	local previous
	local nextPoint

	if sectionNumber > LAST_SECTION then

		previous =
			sectionCenters[sectionNumber]

		nextPoint =
			sectionCenters[
		sectionNumber - 1
		]

	else

		previous =
			sectionCenters[
		LAST_SECTION + 1
		]

		nextPoint =
			sectionCenters[
		LAST_SECTION
		]
			+
			(
				sectionCenters[
				LAST_SECTION
				]
				-
				sectionCenters[
				LAST_SECTION + 1
				]
			)

	end

	local tangent =
		nextPoint - previous

	if tangent.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return tangent.Unit
end

----------------------------------------------------------------
-- LOOP CENTRE
----------------------------------------------------------------

local function getLoopCentre()

	local centre = Vector3.zero
	local count = 0

	for i = LAST_SECTION, FIRST_SECTION do

		if sectionCenters[i] then

			centre += sectionCenters[i]
			count += 1

		end

	end

	if count == 0 then
		return nil
	end

	return centre / count
end

----------------------------------------------------------------
-- INWARD DIRECTION
----------------------------------------------------------------

local function getInwardDirection(
	pathPoint,
	tangent
)

	local centre =
		getLoopCentre()

	if not centre then
		return Vector3.yAxis
	end

	local radial =
		centre - pathPoint

	-- Remove the component along the track.
	radial -=
		tangent *
		radial:Dot(tangent)

	if radial.Magnitude < 0.001 then

		radial =
			Vector3.yAxis -
			tangent *
			Vector3.yAxis:Dot(tangent)

		if radial.Magnitude < 0.001 then

			radial =
				Vector3.xAxis -
				tangent *
				Vector3.xAxis:Dot(tangent)

		end

	end

	return radial.Unit
end

----------------------------------------------------------------
-- RAYCAST PARAMETERS
----------------------------------------------------------------

local rayParams =
	RaycastParams.new()

rayParams.FilterType =
	Enum.RaycastFilterType.Include

rayParams.IgnoreWater = true

----------------------------------------------------------------
-- UPDATE RAYCAST FILTER
----------------------------------------------------------------

local function updateRaycastFilter()

	local include = {}

	for i = LAST_SECTION, FIRST_SECTION do

		for _, part in ipairs(
			sections[i].parts
			) do

			table.insert(
				include,
				part
			)

		end

	end

	rayParams.FilterDescendantsInstances =
		include
end

----------------------------------------------------------------
-- NORMAL LOOP RAYCAST
----------------------------------------------------------------

local function raycastTrack(
	pathPoint,
	inwardDirection
)

	-- IMPORTANT:
	--
	-- Start INSIDE the loop.
	-- Travel OUTWARD toward the track.
	--
	-- Therefore the ray hits the INNER FACE.
	--
	-- The normal from that inner face points INTO
	-- the loop, which is exactly what we need
	-- for the character's UpVector.

	local rayOrigin =
		pathPoint
		+
		inwardDirection *
		RAY_START_DISTANCE

	local rayDirection =
		-inwardDirection *
		RAY_LENGTH

	local result =
		workspace:Raycast(
			rayOrigin,
			rayDirection,
			rayParams
		)

	return
		result,
		rayOrigin,
		rayOrigin + rayDirection
end

----------------------------------------------------------------
-- IDENTIFY HIT SECTION
----------------------------------------------------------------

local function getSectionNumberFromHit(
	instance
)

	if not instance then
		return 0
	end

	local current = instance

	while current
		and current ~= loopFolder do

		local n =
			tonumber(current.Name)

		if n
			and n >= LAST_SECTION
			and n <= FIRST_SECTION then

			return n
		end

		current =
			current.Parent
	end

	return 0
end

----------------------------------------------------------------
-- PHYSICAL ORIENTATION
----------------------------------------------------------------

local function getPhysicalOrientation(
	hit,
	tangent
)

	local up =
		hit.Normal

	if up.Magnitude < 0.001 then
		return nil
	end

	up = up.Unit

	local forward =
		tangent -
		up *
		tangent:Dot(up)

	if forward.Magnitude < 0.001 then
		return nil
	end

	forward =
		forward.Unit

	local right =
		forward:Cross(up)

	if right.Magnitude < 0.001 then
		return nil
	end

	right =
		right.Unit

	forward =
		up:Cross(right).Unit

	return up, forward
end

----------------------------------------------------------------
-- CHARACTER SUPPORT DISTANCE
----------------------------------------------------------------

local function getCharacterSupportDistance(
	outward
)

	if not character or not root then
		return 0
	end

	local rootCF =
		root.CFrame

	local maxDistance = 0

	for _, part in ipairs(
		character:GetDescendants()
		) do

		if part:IsA("BasePart")
			and part ~= root then

			local relative =
				rootCF:ToObjectSpace(
					part.CFrame
				)

			local half =
				part.Size * 0.5

			local localProjection =
				math.abs(
					relative.RightVector:Dot(outward)
				)
				* half.X
				+
				math.abs(
					relative.UpVector:Dot(outward)
				)
				* half.Y
				+
				math.abs(
					relative.LookVector:Dot(outward)
				)
				* half.Z

			local centerProjection =
				relative.Position:Dot(outward)

			maxDistance =
				math.max(
					maxDistance,
					centerProjection +
					localProjection
				)

		end

	end

	return math.max(
		0,
		maxDistance
	)
end

----------------------------------------------------------------
-- PLACE CHARACTER
----------------------------------------------------------------

local function placeCharacterFromSurface(
	hit,
	tangent
)

	if not hit then
		return false, nil, nil, nil
	end

	local up, forward =
		getPhysicalOrientation(
			hit,
			tangent
		)

	if not up then
		return false, nil, nil, nil
	end

	------------------------------------------------------------
	-- INNER FACE
	------------------------------------------------------------

	-- hit.Normal points INTO the loop.
	--
	-- Therefore:
	--
	-- hit.Position
	--      +
	-- hit.Normal * TRACK_OFFSET
	--
	-- puts the ROOT inside the physical track.

	local targetPosition =
		hit.Position +
		up *
		TRACK_OFFSET

	local targetCFrame =
		CFrame.lookAt(
			targetPosition,
			targetPosition + forward,
			up
		)

	root.CFrame =
		targetCFrame

	return
		true,
		up,
		up,
		targetPosition
end

----------------------------------------------------------------
-- LOOP ANIMATION
----------------------------------------------------------------

local function getAnimationIdFromAnimate()

	local animate =
		character
		and character:FindFirstChild(
			"Animate"
		)

	if not animate then
		return nil
	end

	local runFolder =
		animate:FindFirstChild("run")

	if runFolder then

		local runAnim =
			runFolder:FindFirstChildWhichIsA(
				"Animation"
			)

		if runAnim
			and runAnim.AnimationId ~= "" then

			return runAnim.AnimationId
		end

	end

	local walkFolder =
		animate:FindFirstChild("walk")

	if walkFolder then

		local walkAnim =
			walkFolder:FindFirstChildWhichIsA(
				"Animation"
			)

		if walkAnim
			and walkAnim.AnimationId ~= "" then

			return walkAnim.AnimationId
		end

	end

	return nil
end

----------------------------------------------------------------
-- START LOOP ANIMATION
----------------------------------------------------------------

local function startLoopAnimation()

	if not humanoid then
		return
	end

	local animator =
		humanoid:FindFirstChildOfClass(
			"Animator"
		)

	if not animator then

		animator =
			Instance.new("Animator")

		animator.Parent =
			humanoid

	end

	if loopAnimationTrack then

		loopAnimationTrack:Stop(
			LOOP_ANIMATION_FADE
		)

		loopAnimationTrack:Destroy()

		loopAnimationTrack = nil
	end

	local animationId =
		getAnimationIdFromAnimate()

	if not animationId then

		if humanoid.RigType ==
			Enum.HumanoidRigType.R6 then

			animationId =
				"rbxassetid://180426354"

		else

			animationId =
				"rbxassetid://507767714"

		end

	end

	loopAnimationObject =
		Instance.new("Animation")

	loopAnimationObject.Name =
		"LoopRunAnimation"

	loopAnimationObject.AnimationId =
		animationId

	local ok, track =
		pcall(function()

			return animator:LoadAnimation(
				loopAnimationObject
			)

		end)

	if not ok or not track then

		warn(
			"[LOOP] Could not load loop animation:",
			animationId
		)

		if loopAnimationObject then
			loopAnimationObject:Destroy()
			loopAnimationObject = nil
		end

		return
	end

	loopAnimationTrack =
		track

	loopAnimationTrack.Priority =
		Enum.AnimationPriority.Movement

	loopAnimationTrack.Looped =
		true

	loopAnimationTrack:Play(
		LOOP_ANIMATION_FADE,
		1,
		1
	)

	dprint(
		"Loop animation started:",
		animationId
	)
end

----------------------------------------------------------------
-- UPDATE LOOP ANIMATION
----------------------------------------------------------------

local function updateLoopAnimation()

	if not loopAnimationTrack then
		return
	end

	local speedScale =
		LOOP_SPEED / 16

	speedScale =
		math.clamp(
			speedScale,
			LOOP_ANIMATION_SPEED_MIN,
			LOOP_ANIMATION_SPEED_MAX
		)

	loopAnimationTrack:AdjustSpeed(
		speedScale
	)
end

----------------------------------------------------------------
-- STOP LOOP ANIMATION
----------------------------------------------------------------

local function stopLoopAnimation()

	if loopAnimationTrack then

		loopAnimationTrack:Stop(
			LOOP_ANIMATION_FADE
		)

		loopAnimationTrack:Destroy()

		loopAnimationTrack = nil
	end

	if loopAnimationObject then

		loopAnimationObject:Destroy()

		loopAnimationObject = nil
	end
end

----------------------------------------------------------------
-- DISABLE CHARACTER COLLISIONS
----------------------------------------------------------------

local function disableLoopCollisions()

	table.clear(oldCanCollide)

	if not character then
		return
	end

	for _, descendant in ipairs(
		character:GetDescendants()
		) do

		if descendant:IsA("BasePart") then

			oldCanCollide[descendant] =
				descendant.CanCollide

			descendant.CanCollide =
				false
		end

	end

	dprint(
		"Character collisions disabled while attached to loop"
	)
end

----------------------------------------------------------------
-- RESTORE CHARACTER COLLISIONS
----------------------------------------------------------------

local function restoreLoopCollisions()

	for part, wasCollidable in pairs(
		oldCanCollide
		) do

		if part and part.Parent then

			part.CanCollide =
				wasCollidable

		end

	end

	table.clear(oldCanCollide)

	dprint(
		"Character collisions restored"
	)
end

----------------------------------------------------------------
-- CHARACTER
----------------------------------------------------------------

local function refreshCharacter()

	stopLoopAnimation()
	restoreLoopCollisions()

	character =
		player.Character
		or player.CharacterAdded:Wait()

	humanoid =
		character:WaitForChild(
			"Humanoid"
		)

	root =
		character:WaitForChild(
			"HumanoidRootPart"
		)

	oldWalkSpeed =
		NORMAL_WALK_SPEED

	humanoid.WalkSpeed =
		NORMAL_WALK_SPEED

	oldAutoRotate =
		humanoid.AutoRotate
end

----------------------------------------------------------------
-- CAMERA
----------------------------------------------------------------

local camera

local originalCameraOffset = nil

----------------------------------------------------------------
-- CAPTURE ORIGINAL CAMERA
----------------------------------------------------------------

local function captureOriginalCamera()

	camera =
		workspace.CurrentCamera

	if not camera then
		return
	end

	originalCameraType =
		camera.CameraType

	originalCameraSubject =
		camera.CameraSubject

	originalCameraCFrame =
		camera.CFrame

	originalCameraFocus =
		camera.Focus

	if root then

		originalCameraOffset =
			root.CFrame:PointToObjectSpace(
				camera.CFrame.Position
			)

	end
end

----------------------------------------------------------------
-- CAMERA REFERENCE
----------------------------------------------------------------

local REFERENCE_CAMERA_POSITION =
	Vector3.new(
		-612.618,
		138.553,
		178.464
	)

local REFERENCE_CAMERA_FOCUS =
	Vector3.new(
		-737.797,
		138.553,
		178.464
	)

local REFERENCE_BLOCK1_POSITION =
	Vector3.new(
		-708.998,
		79.579,
		178.373
	)

----------------------------------------------------------------
-- GUIDE FORWARD
----------------------------------------------------------------

local function getGuideForward()

	local a =
		sectionCenters[FIRST_SECTION]

	local b =
		sectionCenters[
	FIRST_SECTION - 1
	]

	if not a or not b then
		return nil
	end

	local direction =
		b - a

	if direction.Magnitude < 0.001 then
		return nil
	end

	return direction.Unit
end

----------------------------------------------------------------
-- SIDE CAMERA
----------------------------------------------------------------

local function getSideCameraCFrame()

	local block1 =
		sections[FIRST_SECTION].object

	if not block1 then
		return nil
	end

	local block1Position

	if block1:IsA("BasePart") then

		block1Position =
			block1.Position

	else

		block1Position =
			sectionCenters[
		FIRST_SECTION
		]

	end

	if not block1Position then
		return nil
	end

	local cameraOffset =
		REFERENCE_CAMERA_POSITION -
		REFERENCE_BLOCK1_POSITION

	local focusOffset =
		REFERENCE_CAMERA_FOCUS -
		REFERENCE_BLOCK1_POSITION

	local cameraPosition =
		block1Position +
		cameraOffset

	local focusPosition =
		block1Position +
		focusOffset

	return CFrame.lookAt(
		cameraPosition,
		focusPosition,
		Vector3.yAxis
	)
end

----------------------------------------------------------------
-- NORMAL CAMERA TARGET
----------------------------------------------------------------

local function getNormalCameraTarget()

	if not root
		or not originalCameraOffset then

		return nil
	end

	local desiredOffset =
		Vector3.new(
			originalCameraOffset.X,

			math.max(
				originalCameraOffset.Y,
				5
			),

			originalCameraOffset.Z
		)

	local position =
		root.CFrame:PointToWorldSpace(
			desiredOffset
		)

	local lookAt =
		root.Position +
		Vector3.new(
			0,
			2.5,
			0
		)

	return CFrame.lookAt(
		position,
		lookAt,
		Vector3.yAxis
	)
end

----------------------------------------------------------------
-- START LOOP CAMERA
----------------------------------------------------------------

local function startLoopCamera()

	captureOriginalCamera()

	camera =
		workspace.CurrentCamera

	if not camera then
		return
	end

	loopCameraCFrame =
		getSideCameraCFrame()

	if not loopCameraCFrame then
		return
	end

	camera.CameraType =
		Enum.CameraType.Scriptable

	camera.CFrame =
		loopCameraCFrame

	camera.Focus =
		CFrame.new(
			loopCameraCFrame.Position
			+
			loopCameraCFrame.LookVector *
			125
		)

	cameraControlling =
		true
end

----------------------------------------------------------------
-- RESTORE PLAYER CAMERA
----------------------------------------------------------------

local function restorePlayerCamera()

	camera =
		workspace.CurrentCamera

	if not camera then

		cameraControlling =
			false

		return
	end

	cameraControlling =
		false

	camera.CameraType =
		originalCameraType
		or
		Enum.CameraType.Custom

	camera.CameraSubject =
		(
			originalCameraSubject
			and originalCameraSubject.Parent
		)
		or
		humanoid

	loopCameraCFrame = nil
	originalCameraOffset = nil
end

----------------------------------------------------------------
-- UPDATE LOOP CAMERA
----------------------------------------------------------------

local function updateLoopCamera()

	if not loopActive
		or not cameraControlling then

		return
	end

	camera =
		workspace.CurrentCamera

	if not camera or not root then
		return
	end

	if not loopCameraCFrame then
		return
	end

	local returnStart =
		math.max(
			LAST_SECTION,
			LAST_SECTION +
			CAMERA_RETURN_SECTIONS
		)

	------------------------------------------------------------
	-- STATIC LOOP CAMERA
	------------------------------------------------------------

	if currentSection > returnStart then

		camera.CFrame =
			loopCameraCFrame

		camera.Focus =
			CFrame.new(
				loopCameraCFrame.Position
				+
				loopCameraCFrame.LookVector *
				125
			)

		return
	end

	------------------------------------------------------------
	-- FINAL FIVE SECTIONS
	------------------------------------------------------------

	local progress =
		(
			(returnStart - currentSection)
			+
			sectionProgress
		)
		/
		CAMERA_RETURN_SECTIONS

	progress =
		math.clamp(
			progress,
			0,
			1
		)

	local smooth =
		progress *
		progress *
		(3 - 2 * progress)

	local alpha =
		math.pow(
			smooth,
			CAMERA_BLEND_POWER
		)

	local normalTarget =
		getNormalCameraTarget()

	if not normalTarget then

		camera.CFrame =
			loopCameraCFrame

		return
	end

	camera.CFrame =
		loopCameraCFrame:Lerp(
			normalTarget,
			alpha
		)

	camera.Focus =
		CFrame.new(
			root.Position +
			Vector3.new(
				0,
				2.5,
				0
			)
		)

	if progress >= 1 then
		restorePlayerCamera()
	end
end

----------------------------------------------------------------
-- START LOOP
----------------------------------------------------------------

local function startLoop(
	startingSection
)

	if running then
		return
	end

	if not root
		or not root.Parent then

		refreshCharacter()
	end

	startingSection =
		tonumber(startingSection)
		or FIRST_SECTION

	startingSection =
		math.clamp(
			startingSection,
			LAST_SECTION,
			FIRST_SECTION
		)

	running = true
	loopActive = true

	currentSection =
		startingSection

	sectionProgress = 0
	pathDistance = 0

	startLoopCamera()

	humanoid.AutoRotate =
		false

	humanoid.WalkSpeed =
		0

	humanoid.PlatformStand =
		false

	disableLoopCollisions()
	startLoopAnimation()

	debugState.status =
		"ENTERING"

	debugState.error =
		""

	print("==========================================")
	print("[LOOP] LOOP STARTED")
	print(
		"[LOOP] Starting section:",
		currentSection
	)
	print(
		"[LOOP] Last section:",
		LAST_SECTION
	)
	print(
		"[LOOP] Track offset:",
		TRACK_OFFSET
	)
	print("==========================================")
end

----------------------------------------------------------------
-- EXIT
----------------------------------------------------------------

local function beginExit(tangent)

	if not running then
		return
	end

	------------------------------------------------------------
	-- IMPORTANT:
	--
	-- At this point Section 1 has already placed the character
	-- against the REAL physical inner surface.
	--
	-- Do NOT move the character again here.
	------------------------------------------------------------

	running = false
	loopActive = false

	------------------------------------------------------------
	-- Stop artificial loop movement
	------------------------------------------------------------

	humanoid.WalkSpeed =
		NORMAL_WALK_SPEED

	humanoid.AutoRotate =
		oldAutoRotate

	humanoid.PlatformStand =
		false

	------------------------------------------------------------
	-- Stop animation
	------------------------------------------------------------

	stopLoopAnimation()

	------------------------------------------------------------
	-- Restore collisions
	------------------------------------------------------------

	restoreLoopCollisions()

	------------------------------------------------------------
	-- IMPORTANT:
	--
	-- Clear any velocity accumulated while attached.
	-- Otherwise Roblox may launch/fall the character from
	-- the final surface when control is released.
	------------------------------------------------------------

	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero

	------------------------------------------------------------
	-- Make sure the humanoid is standing normally.
	------------------------------------------------------------

	humanoid:ChangeState(
		Enum.HumanoidStateType.GettingUp
	)

	------------------------------------------------------------
	-- Release camera AFTER the character has been positioned.
	------------------------------------------------------------

	restorePlayerCamera()

	debugState.status =
		"IDLE"

	debugState.error =
		""

	print("==========================================")
	print("[LOOP] LOOP COMPLETE")
	print(
		"[LOOP] Final section:",
		LAST_SECTION
	)
	print("[LOOP] Final physical position preserved")
	print("[LOOP] Normal movement restored")
	print("[LOOP CAMERA] Roblox camera restored")
	print("==========================================")
end

----------------------------------------------------------------
-- MAIN LOOP UPDATE
----------------------------------------------------------------

local function updateLoop(dt)

	if not loopActive
		or not running then

		return
	end

	updateLoopAnimation()

	if not character
		or not character.Parent
		or not root
		or not root.Parent then

		debugState.error =
			"Character/root disappeared"

		running = false
		loopActive = false

		return
	end

	------------------------------------------------------------
	-- ADVANCE PATH
	------------------------------------------------------------

	local currentCenter =
		sectionCenters[currentSection]

	local nextCenter

	if currentSection > LAST_SECTION then

		nextCenter =
			sectionCenters[
		currentSection - 1
		]

	else

		nextCenter =
			currentCenter
			+
			(
				currentCenter
				-
				sectionCenters[
				currentSection + 1
				]
			)

	end

	local sectionLength =
		(
			nextCenter -
			currentCenter
		).Magnitude

	if sectionLength < 0.01 then

		debugState.error =
			"Section length is nearly zero"

		return
	end

	sectionProgress +=
		(
			LOOP_SPEED * dt
		)
		/
		sectionLength

	------------------------------------------------------------
	-- SECTION TRANSITION
	------------------------------------------------------------

	while sectionProgress >= 1
		and currentSection > LAST_SECTION do

		sectionProgress -= 1

		currentSection -= 1

		print(
			"[LOOP] Entered section",
			currentSection
		)
	end

	------------------------------------------------------------
	-- SECTION 1 TERMINAL
	------------------------------------------------------------

	if currentSection == LAST_SECTION
		and sectionProgress >= 1 then

		local tangent =
			getTangent(
				LAST_SECTION
			)

		local bestHit = nil
		local bestDistance =
			math.huge

		--------------------------------------------------------
		-- IMPORTANT FIX
		--
		-- Start INSIDE the loop and ray OUTWARD.
		--
		-- The OLD code did:
		--
		-- sample - direction * distance
		-- direction * length
		--
		-- which started OUTSIDE and hit the OUTER FACE.
		--
		-- Correct:
		--
		-- sample + direction * distance
		-- -direction * length
		--
		-- This hits the INNER FACE.
		--------------------------------------------------------

		for _, part in ipairs(
			sections[
			LAST_SECTION
			].parts
			) do

			local sample =
				part.Position

			local rayDirection =
				getInwardDirection(
					sample,
					tangent
				)

			local rayOrigin =
				sample
				+
				rayDirection *
				RAY_START_DISTANCE

			local rayVector =
				-rayDirection *
				RAY_LENGTH

			local result =
				workspace:Raycast(
					rayOrigin,
					rayVector,
					rayParams
				)

			if result then

				local distance =
					(
						result.Position -
						root.Position
					).Magnitude

				if distance <
					bestDistance then

					bestDistance =
						distance

					bestHit =
						result
				end

			end

		end

		--------------------------------------------------------
		-- FINAL PHYSICAL PLACEMENT
		--------------------------------------------------------

		if bestHit then

			local placed,
				physicalUp,
				_,
				targetPosition =
				placeCharacterFromSurface(
					bestHit,
					tangent
				)

			if placed then

				debugState.section =
					LAST_SECTION

				debugState.progress =
					1

				debugState.expectedSection =
					LAST_SECTION

				debugState.hitName =
					bestHit.Instance:GetFullName()

				debugState.hitSection =
					getSectionNumberFromHit(
						bestHit.Instance
					)

				debugState.rayHit =
					true

				debugState.inward =
					physicalUp

				debugState.targetPosition =
					targetPosition

				debugState.surfaceDistance =
					(
						root.Position -
						bestHit.Position
					).Magnitude

				debugState.status =
					"FINAL PHYSICAL SURFACE"

				debugState.error =
					""

				drawDebug()
				debugFrame(os.clock())

			else

				debugState.status =
					"FINAL PLACEMENT FAILED"

				debugState.error =
					"Could not construct final orientation"

				drawDebug()
				debugFrame(os.clock())

			end

		else

			debugState.status =
				"FINAL RAYCAST FAILED"

			debugState.error =
				"Section 1 physical geometry could not be raycast"

			dprint(
				"FINAL RAYCAST FAILED"
			)

			drawDebug()
			debugFrame(os.clock())

		end

		--------------------------------------------------------
		-- EXIT
		--------------------------------------------------------

		beginExit(tangent)

		return
	end

	------------------------------------------------------------
	-- NORMAL LOOP RAYCAST
	------------------------------------------------------------

	local pathPoint =
		getPathPoint(
			currentSection,
			sectionProgress
		)

	local tangent =
		getTangent(
			currentSection
		)

	local rayDirection =
		getInwardDirection(
			pathPoint,
			tangent
		)

	local hit,
		rayOrigin,
		rayEnd =
		raycastTrack(
			pathPoint,
			rayDirection
		)

	debugState.section =
		currentSection

	debugState.progress =
		sectionProgress

	debugState.expectedSection =
		currentSection

	debugState.tangent =
		tangent

	debugState.inward =
		rayDirection

	debugState.rayOrigin =
		rayOrigin

	debugState.rayEnd =
		rayEnd

	debugState.error =
		""

	------------------------------------------------------------
	-- PHYSICAL SECTION RECOVERY
	------------------------------------------------------------

	if not hit then

		local bestHit = nil
		local bestDistance =
			math.huge

		for _, part in ipairs(
			sections[
			currentSection
			].parts
			) do

			local sample =
				part.Position

			local recoveryDirection =
				getInwardDirection(
					sample,
					tangent
				)

			----------------------------------------------------
			-- IMPORTANT FIX
			--
			-- Same inside -> outward direction as the main ray.
			----------------------------------------------------

			local recoveryOrigin =
				sample
				+
				recoveryDirection *
				RAY_START_DISTANCE

			local recoveryVector =
				-recoveryDirection *
				RAY_LENGTH

			local candidate =
				workspace:Raycast(
					recoveryOrigin,
					recoveryVector,
					rayParams
				)

			if candidate then

				local distance =
					(
						candidate.Position -
						root.Position
					).Magnitude

				if distance <
					bestDistance then

					bestDistance =
						distance

					bestHit =
						candidate
				end

			end

		end

		if bestHit then

			hit =
				bestHit

			debugState.error =
				"GUIDE RAY MISSED; PHYSICAL SECTION RECOVERY USED"

			dprint(
				"Recovered from physical geometry:",
				currentSection
			)

		else

			debugState.rayHit =
				false

			debugState.hitName =
				"NONE"

			debugState.hitSection =
				0

			debugState.status =
				"RAYCAST FAILED"

			debugState.error =
				"Guide ray AND physical-section recovery ray missed"

			dprint(
				"RAYCAST FAILED",
				"section=",
				currentSection,
				"progress=",
				sectionProgress
			)

			drawDebug()
			debugFrame(os.clock())

			return
		end
	end

	------------------------------------------------------------
	-- HIT INFORMATION
	------------------------------------------------------------

	local hitSection =
		getSectionNumberFromHit(
			hit.Instance
		)

	debugState.rayHit =
		true

	debugState.hitName =
		hit.Instance:GetFullName()

	debugState.hitSection =
		hitSection

	debugState.status =
		"RUNNING"

	------------------------------------------------------------
	-- ADJACENT SECTION WARNING
	------------------------------------------------------------

	if math.abs(
		hitSection -
			currentSection
		) > 1 then

		debugState.error =
			"Ray hit a non-adjacent section: expected "
			..
			currentSection
			..
			", got "
			..
			hitSection

		dprint(
			"WARNING:",
			debugState.error
		)

	end

	------------------------------------------------------------
	-- PHYSICAL SURFACE IS AUTHORITATIVE
	------------------------------------------------------------

	local placed,
		physicalInward,
		up,
		targetPosition =
		placeCharacterFromSurface(
			hit,
			tangent
		)

	if not placed then

		debugState.error =
			"Failed to construct physical surface orientation"

		drawDebug()
		debugFrame(os.clock())

		return
	end

	debugState.inward =
		physicalInward

	debugState.targetPosition =
		targetPosition

	debugState.targetDistance =
		TRACK_OFFSET

	debugState.bodySupportDistance =
		getCharacterSupportDistance(
			-physicalInward
		)

	debugState.surfaceDistance =
		(
			root.Position -
			hit.Position
		).Magnitude

	------------------------------------------------------------
	-- OFFSET CHECK
	------------------------------------------------------------

	local actualError =
		math.abs(
			debugState.surfaceDistance
			-
			TRACK_OFFSET
		)

	if actualError > 0.05 then

		debugState.error =
			string.format(
				"OFFSET ERROR: %.3f studs (target %.3f)",
				debugState.surfaceDistance,
				TRACK_OFFSET
			)
	end

	------------------------------------------------------------
	-- CAMERA
	------------------------------------------------------------

	updateLoopCamera()

	drawDebug()
	debugFrame(os.clock())
end

----------------------------------------------------------------
-- TRIGGER DETECTION
----------------------------------------------------------------

local touchDebounce = false

local function isCharacterPart(part)

	return character
		and part
		and part:IsDescendantOf(
			character
		)
end

----------------------------------------------------------------
-- ENTRY SECTIONS
----------------------------------------------------------------

local ENTRY_SECTIONS = {
	[30] = true,
	[29] = true,
	[28] = true,
}

----------------------------------------------------------------
-- CONNECT ENTRY TRIGGERS
----------------------------------------------------------------

local function connectEntryTriggers()

	for sectionNumber, enabled in pairs(
		ENTRY_SECTIONS
		) do

		if enabled
			and sections[sectionNumber] then

			for _, part in ipairs(
				sections[
				sectionNumber
				].parts
				) do

				part.Touched:Connect(
					function(hit)

						if touchDebounce then
							return
						end

						if not isCharacterPart(
							hit
							) then
							return
						end

						if running then
							return
						end

						touchDebounce =
							true

						startLoop(
							sectionNumber
						)

						task.delay(
							0.5,
							function()

								touchDebounce =
									false

							end
						)

					end
				)

			end

			print(
				"[LOOP] Entry trigger connected: section",
				sectionNumber
			)

		end

	end
end

----------------------------------------------------------------
-- CHARACTER RESPAWN
----------------------------------------------------------------

player.CharacterAdded:Connect(
	function()

		running = false
		loopActive = false

		restorePlayerCamera()

		task.wait()

		refreshCharacter()

	end
)

----------------------------------------------------------------
-- INITIALIZE
----------------------------------------------------------------

loadSections()

updateRaycastFilter()

refreshCharacter()

connectEntryTriggers()

----------------------------------------------------------------
-- HEARTBEAT
----------------------------------------------------------------

RunService.Heartbeat:Connect(
	function(dt)

		updateLoop(dt)

	end
)

print(
	"[LOOP] System initialized successfully."
)