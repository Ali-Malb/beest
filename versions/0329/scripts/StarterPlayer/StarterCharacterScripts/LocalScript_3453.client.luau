--[[
    PHYSICAL LOOP-THE-LOOP SYSTEM
    Roblox LocalScript

    EXPECTED SETUP:
        Workspace
          └─ Loop
               ├─ 1
               ├─ 2
               ├─ ...
               └─ 30

    Each numbered object may be a BasePart or a Model containing BaseParts.

    Put this LocalScript in StarterPlayer > StarterPlayerScripts.

    IMPORTANT:
    - The physical loop geometry is used by raycasts for the final character position.
    - No camera properties are changed.
    - There is NO 30 -> 1 wrap.
    - Debugging can be enabled/disabled with DEBUG_ENABLED below.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------

local LOOP_FOLDER_NAME = "Loop"

local FIRST_SECTION = 1
local LAST_SECTION = 30

local TRACK_OFFSET = 2                 -- studs from physical track
local LOOP_SPEED = 45                  -- studs/sec along section path

-- Camera handoff:
-- start at the old loop pivot, then smoothly return to the player's
-- original camera over the final 5 loop sections.
local CAMERA_RETURN_SECTIONS = 5
local CAMERA_BLEND_POWER = 2.0
local cameraControlling = false
local originalCameraType
local originalCameraSubject
local originalCameraCFrame
local originalCameraFocus
local loopCameraCFrame

local EXIT_TIME = 3                    -- seconds of forward movement

local RAY_START_DISTANCE = 20
local RAY_LENGTH = 45

local DEBUG_ENABLED = true
local DEBUG_PRINT_INTERVAL = 0.15
local DEBUG_MARKERS = false

-- How much the character is allowed to move through the section
-- interpolation before switching to the next one.
local SECTION_LOOKAHEAD = 0.08

-- Animation / collision handling while attached to the loop.
local LOOP_ANIMATION_FADE = 0.12
local LOOP_ANIMATION_SPEED_MIN = 0.85
local LOOP_ANIMATION_SPEED_MAX = 2.75
local LOOP_BODY_CLEARANCE = 0.08 -- extra anti-clipping safety margin

----------------------------------------------------------------
-- REFERENCES
----------------------------------------------------------------

local loopFolder = workspace:WaitForChild(LOOP_FOLDER_NAME)

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

local exitVelocity = Vector3.zero
local exitStart = 0

local NORMAL_WALK_SPEED = 50
local oldWalkSpeed = NORMAL_WALK_SPEED
local oldAutoRotate = true
local oldCanCollide = {}
local loopAnimationTrack = nil
local loopAnimationObject = nil

----------------------------------------------------------------
-- DEBUG
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
	-- 3D debug markers intentionally disabled.
	-- Console debugging remains available through DEBUG_ENABLED.
end

local function clearDebug()
	if debugFolder then
		debugFolder:Destroy()
		debugFolder = nil
	end
end

----------------------------------------------------------------
-- FIND BASEPARTS INSIDE A SECTION
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

local function getSectionCenter(object)
	if object:IsA("BasePart") then
		return object.Position
	end

	local parts = getPartsFromSection(object)

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

	for i = FIRST_SECTION, LAST_SECTION do
		local object = loopFolder:FindFirstChild(tostring(i))

		if not object then
			error("LOOP ERROR: Missing Workspace.Loop." .. i)
		end

		local parts = getPartsFromSection(object)

		if #parts == 0 then
			error("LOOP ERROR: Section " .. i .. " contains no BaseParts")
		end

		local center = getSectionCenter(object)

		if not center then
			error("LOOP ERROR: Could not calculate center of section " .. i)
		end

		sections[i] = {
			object = object,
			parts = parts,
			center = center,
		}

		sectionCenters[i] = center

		dprint("Loaded section", i, object:GetFullName())
	end

	print("==========================================")
	print("PHYSICAL LOOP SYSTEM READY")
	print("Sections:", FIRST_SECTION, "->", LAST_SECTION)
	print("Track offset:", TRACK_OFFSET)
	print("Loop speed:", LOOP_SPEED)
	print("WASD speed:", NORMAL_WALK_SPEED)
	print("Ray start:", RAY_START_DISTANCE)
	print("Debug:", DEBUG_ENABLED)
	print("Camera/loop inactive until sections 1, 2, or 3 are touched")
	print("Camera: calibrated from reference Camera/Block 1 relationship")
	print("==========================================")
end

----------------------------------------------------------------
-- PATH GEOMETRY
----------------------------------------------------------------

local function getPathPoint(sectionNumber, progress)
	progress = math.clamp(progress, 0, 1)

	local a = sectionCenters[sectionNumber]
	local b

	if sectionNumber < LAST_SECTION then
		b = sectionCenters[sectionNumber + 1]
	else
		-- At section 30, do NOT wrap to section 1.
		-- Extrapolate from the final two section centers only for
		-- calculating the final tangent/exit direction.
		local previous = sectionCenters[LAST_SECTION - 1]
		local final = sectionCenters[LAST_SECTION]
		b = final + (final - previous)
	end

	return a:Lerp(b, progress)
end

local function getTangent(sectionNumber)
	local previous

	if sectionNumber <= FIRST_SECTION then
		previous = sectionCenters[1]
	else
		previous = sectionCenters[sectionNumber - 1]
	end

	local nextPoint

	if sectionNumber >= LAST_SECTION then
		nextPoint = sectionCenters[LAST_SECTION] +
			(sectionCenters[LAST_SECTION] - sectionCenters[LAST_SECTION - 1])
	else
		nextPoint = sectionCenters[sectionNumber + 1]
	end

	local tangent = nextPoint - previous

	if tangent.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return tangent.Unit
end

local function getInwardDirection(pathPoint, tangent)
	-- Find the approximate loop centre from all section centres.
	-- This is ONLY used to choose the ray direction.
	-- The final position comes from the physical raycast.
	local centre = Vector3.zero

	for i = FIRST_SECTION, LAST_SECTION do
		centre += sectionCenters[i]
	end

	centre /= (LAST_SECTION - FIRST_SECTION + 1)

	local radial = centre - pathPoint

	-- Remove the component parallel to the tangent so the radial
	-- direction remains perpendicular to travel.
	radial -= tangent * radial:Dot(tangent)

	if radial.Magnitude < 0.001 then
		-- Fallback: choose a stable perpendicular direction.
		radial = Vector3.yAxis - tangent * Vector3.yAxis:Dot(tangent)

		if radial.Magnitude < 0.001 then
			radial = Vector3.xAxis - tangent * Vector3.xAxis:Dot(tangent)
		end
	end

	return radial.Unit
end

----------------------------------------------------------------
-- RAYCAST
----------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true

local function updateRaycastFilter()
	local include = {}

	for i = FIRST_SECTION, LAST_SECTION do
		for _, part in ipairs(sections[i].parts) do
			table.insert(include, part)
		end
	end

	rayParams.FilterDescendantsInstances = include
end

local function raycastTrack(pathPoint, rayDirectionIn)
	-- Start on the OUTSIDE of the loop and ray inward.
	-- The first physical surface hit is therefore the outside
	-- face of the track. Its normal points OUTWARD, so the
	-- character's true inward direction is -hit.Normal.
	local rayOrigin = pathPoint - rayDirectionIn * RAY_START_DISTANCE
	local rayDirection = rayDirectionIn * RAY_LENGTH

	local result = workspace:Raycast(
		rayOrigin,
		rayDirection,
		rayParams
	)

	return result, rayOrigin, rayOrigin + rayDirection
end

----------------------------------------------------------------
-- IDENTIFY HIT SECTION CORRECTLY
----------------------------------------------------------------

local function getSectionNumberFromHit(instance)
	if not instance then
		return 0
	end

	local current = instance

	while current and current ~= loopFolder do
		local n = tonumber(current.Name)

		if n and n >= FIRST_SECTION and n <= LAST_SECTION then
			return n
		end

		current = current.Parent
	end

	return 0
end

----------------------------------------------------------------
-- CHARACTER
----------------------------------------------------------------

----------------------------------------------------------------
-- DEBUG SNAPSHOT
----------------------------------------------------------------

local lastDebugPrint = 0

local function debugFrame(now)
	if not DEBUG_ENABLED then
		return
	end

	if now - lastDebugPrint < DEBUG_PRINT_INTERVAL then
		return
	end

	lastDebugPrint = now

	print("------------------------------------------")
	print("[LOOP DEBUG] Status:", debugState.status)
	print("[LOOP DEBUG] Section:", debugState.section)
	print("[LOOP DEBUG] Progress:", string.format("%.2f", debugState.progress))
	print("[LOOP DEBUG] Expected hit:", debugState.expectedSection)
	print("[LOOP DEBUG] Actual hit:", debugState.hitSection, debugState.hitName)
	print("[LOOP DEBUG] Ray hit:", debugState.rayHit)
	print("[LOOP DEBUG] Surface -> character:",
		string.format("%.3f", debugState.surfaceDistance))
	print("[LOOP DEBUG] Target distance:", debugState.targetDistance)
	print("[LOOP DEBUG] Body support distance:", debugState.bodySupportDistance)
	print("[LOOP DEBUG] Tangent:", debugState.tangent)
	print("[LOOP DEBUG] Inward / Physical Up:", debugState.inward)
	print("[LOOP DEBUG] Animation:", loopAnimationTrack and loopAnimationTrack.IsPlaying or false)
	print("[LOOP DEBUG] Collision disabled:", next(oldCanCollide) ~= nil)
	print("[LOOP DEBUG] Error:", debugState.error)
end

----------------------------------------------------------------
-- POSITION + ORIENTATION
----------------------------------------------------------------

local function getPhysicalOrientation(hit, tangent)
	-- Hit.Normal points OUT of the physical track.
	-- The character is on the INSIDE, so its UpVector points inward.
	local outward = hit.Normal

	if outward.Magnitude < 0.001 then
		return nil
	end

	outward = outward.Unit

	local up = -outward

	-- The section path gives us the travel direction, but it may
	-- contain a small component through the physical surface.
	-- Project it onto the physical surface so Forward and Up are
	-- guaranteed to be perpendicular.
	local forward = tangent - outward * tangent:Dot(outward)

	if forward.Magnitude < 0.001 then
		return nil
	end

	forward = forward.Unit

	-- Construct a clean orthogonal frame.
	local right = forward:Cross(up)

	if right.Magnitude < 0.001 then
		return nil
	end

	right = right.Unit
	forward = up:Cross(right).Unit

	return up, forward
end

local function getCharacterSupportDistance(outward)
	-- Find how far the character extends from the HumanoidRootPart
	-- toward the physical track. This prevents the body/feet from
	-- entering the track even though the root itself is 2 studs away.
	if not character or not root then
		return 0
	end

	local rootCF = root.CFrame
	local maxDistance = 0

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root then
			local relative = rootCF:ToObjectSpace(part.CFrame)

			local half = part.Size * 0.5
			local localProjection =
				math.abs(relative.RightVector:Dot(outward)) * half.X +
				math.abs(relative.UpVector:Dot(outward)) * half.Y +
				math.abs(relative.LookVector:Dot(outward)) * half.Z

			local centerProjection =
				relative.Position:Dot(outward)

			maxDistance = math.max(
				maxDistance,
				centerProjection + localProjection
			)
		end
	end

	return math.max(0, maxDistance)
end

local function placeCharacterFromSurface(hit, tangent)
	if not hit then
		return false, nil, nil, nil
	end

	local up, forward = getPhysicalOrientation(hit, tangent)

	if not up then
		return false, nil, nil, nil
	end

	-- EXACTLY 2 studs inward from the actual raycast surface.
	-- The requested 2 studs is the minimum ROOT offset.
	-- If the avatar extends farther toward the track than that,
	-- move the root outward enough that the actual body still has
	-- a small clearance from the physical surface.
	local outward = -up
	local bodySupport = getCharacterSupportDistance(outward)

	local requiredRootOffset = math.max(
		TRACK_OFFSET,
		bodySupport + LOOP_BODY_CLEARANCE
	)

	local targetPosition =
		hit.Position +
		up * requiredRootOffset

	local targetCFrame =
		CFrame.lookAt(
			targetPosition,
			targetPosition + forward,
			up
		)

	root.CFrame = targetCFrame

	return true, up, up, targetPosition
end

----------------------------------------------------------------
-- LOOP ANIMATION + COLLISION
----------------------------------------------------------------

local function getAnimationIdFromAnimate()
	-- Prefer the player's existing Run animation so custom avatar
	-- animation packs continue to work.
	local animate = character and character:FindFirstChild("Animate")

	if not animate then
		return nil
	end

	local runFolder = animate:FindFirstChild("run")
	if runFolder then
		local runAnim = runFolder:FindFirstChildWhichIsA("Animation")
		if runAnim and runAnim.AnimationId ~= "" then
			return runAnim.AnimationId
		end
	end

	local walkFolder = animate:FindFirstChild("walk")
	if walkFolder then
		local walkAnim = walkFolder:FindFirstChildWhichIsA("Animation")
		if walkAnim and walkAnim.AnimationId ~= "" then
			return walkAnim.AnimationId
		end
	end

	return nil
end

local function startLoopAnimation()
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	if loopAnimationTrack then
		loopAnimationTrack:Stop(LOOP_ANIMATION_FADE)
		loopAnimationTrack:Destroy()
		loopAnimationTrack = nil
	end

	local animationId = getAnimationIdFromAnimate()

	-- Fallback R15 running animation if the character's Animate
	-- controller does not expose a run/walk animation.
	if not animationId then
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			animationId = "rbxassetid://180426354"
		else
			animationId = "rbxassetid://507767714"
		end
	end

	loopAnimationObject = Instance.new("Animation")
	loopAnimationObject.Name = "LoopRunAnimation"
	loopAnimationObject.AnimationId = animationId

	local ok, track = pcall(function()
		return animator:LoadAnimation(loopAnimationObject)
	end)

	if not ok or not track then
		warn("[LOOP] Could not load loop animation:", animationId)
		if loopAnimationObject then
			loopAnimationObject:Destroy()
			loopAnimationObject = nil
		end
		return
	end

	loopAnimationTrack = track
	loopAnimationTrack.Priority = Enum.AnimationPriority.Movement
	loopAnimationTrack.Looped = true
	loopAnimationTrack:Play(LOOP_ANIMATION_FADE, 1, 1)

	dprint("Loop animation started:", animationId)
end

local function updateLoopAnimation()
	if not loopAnimationTrack then
		return
	end

	local speedScale = LOOP_SPEED / 16
	speedScale = math.clamp(
		speedScale,
		LOOP_ANIMATION_SPEED_MIN,
		LOOP_ANIMATION_SPEED_MAX
	)

	loopAnimationTrack:AdjustSpeed(speedScale)
end

local function stopLoopAnimation()
	if loopAnimationTrack then
		loopAnimationTrack:Stop(LOOP_ANIMATION_FADE)
		loopAnimationTrack:Destroy()
		loopAnimationTrack = nil
	end

	if loopAnimationObject then
		loopAnimationObject:Destroy()
		loopAnimationObject = nil
	end
end

local function disableLoopCollisions()
	table.clear(oldCanCollide)

	if not character then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			oldCanCollide[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end

	dprint("Character collisions disabled while attached to loop")
end

local function restoreLoopCollisions()
	for part, wasCollidable in pairs(oldCanCollide) do
		if part and part.Parent then
			part.CanCollide = wasCollidable
		end
	end

	table.clear(oldCanCollide)

	dprint("Character collisions restored")
end

----------------------------------------------------------------
-- CHARACTER
----------------------------------------------------------------

local function refreshCharacter()
	-- These helpers are defined above this function so respawns can
	-- safely stop the old animation and restore old collision states.
	stopLoopAnimation()
	restoreLoopCollisions()

	character = player.Character or player.CharacterAdded:Wait()

	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")

	oldWalkSpeed = NORMAL_WALK_SPEED
	humanoid.WalkSpeed = NORMAL_WALK_SPEED
	oldAutoRotate = humanoid.AutoRotate
end

----------------------------------------------------------------
-- ENTER LOOP
----------------------------------------------------------------


----------------------------------------------------------------
-- CAMERA CONTROL
----------------------------------------------------------------

-- CAMERA DESIGN
--
-- During the loop:
--   The camera is a SIDE / AERIAL spectator camera.
--   It looks at the centre of the entire physical loop, so the
--   whole loop remains visible instead of following the player's
--   feet.
--
-- During the last 5 sections:
--   The spectator view smoothly moves toward a normal third-person
--   camera position behind/above the player.
--
-- After section 30:
--   Scriptable camera control is released completely and Roblox
--   takes over again, so the camera follows the player normally.

local loopCameraCFrame = nil
local originalCameraOffset = nil

local function captureOriginalCamera()
	camera = workspace.CurrentCamera

	if not camera then
		return
	end

	originalCameraType = camera.CameraType
	originalCameraSubject = camera.CameraSubject
	originalCameraCFrame = camera.CFrame
	originalCameraFocus = camera.Focus

	if root then
		-- Save the player's normal camera relationship.
		originalCameraOffset =
			root.CFrame:PointToObjectSpace(
				camera.CFrame.Position
			)
	end
end

-- Exact camera calibration supplied for the loop.
--
-- Camera CFrame:
--   Position: -612.618, 138.553, 178.464
--   Rotation: 0, 90, 0
--
-- Camera Focus:
--   Position: -737.797, 138.553, 178.464
--
-- Block 1 reference:
--   Position: -708.998, 79.579, 178.373
--   Rotation: 0, 0, 0
--
-- We preserve the exact camera-to-focus relationship and use Block 1
-- as the anchor for adapting it to the actual loop.
local REFERENCE_CAMERA_POSITION =
	Vector3.new(-612.618, 138.553, 178.464)

local REFERENCE_CAMERA_FOCUS =
	Vector3.new(-737.797, 138.553, 178.464)

local REFERENCE_BLOCK1_POSITION =
	Vector3.new(-708.998, 79.579, 178.373)

local REFERENCE_CAMERA_ROTATION =
	CFrame.Angles(0, math.rad(90), 0)

local REFERENCE_FOCUS_OFFSET =
	REFERENCE_CAMERA_FOCUS -
	REFERENCE_BLOCK1_POSITION


local function getLoopCentre()
	local centre = Vector3.zero
	local count = 0

	for i = FIRST_SECTION, LAST_SECTION do
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

local function getGuideForward()
	-- This is the direction the old glowing guide string was going
	-- at the beginning of the loop: section 1 -> section 2.
	local a = sectionCenters[FIRST_SECTION]
	local b = sectionCenters[FIRST_SECTION + 1]

	if not a or not b then
		return nil
	end

	local direction = b - a

	if direction.Magnitude < 0.001 then
		return nil
	end

	return direction.Unit
end

local function getSideCameraCFrame()
	local block1 = sections[FIRST_SECTION].object

	if not block1 then
		return nil
	end

	local block1Position

	if block1:IsA("BasePart") then
		block1Position = block1.Position
	else
		block1Position = sectionCenters[FIRST_SECTION]
	end

	if not block1Position then
		return nil
	end

	------------------------------------------------------------
	-- EXACT CALIBRATION
	------------------------------------------------------------
	--
	-- The supplied setup is:
	--
	-- Block 1:
	--   -708.998, 79.579, 178.373
	--
	-- Camera:
	--   -612.618, 138.553, 178.464
	--
	-- Focus:
	--   -737.797, 138.553, 178.464
	--
	-- We calculate the offsets from Block 1, then apply those
	-- offsets to the actual Block 1 position.
	------------------------------------------------------------

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

	------------------------------------------------------------
	-- Use the supplied camera-to-focus vector for orientation.
	-- This is mathematically equivalent to the requested
	-- 0, 90, 0 orientation for the supplied coordinates.
	------------------------------------------------------------

	return CFrame.lookAt(
		cameraPosition,
		focusPosition,
		Vector3.yAxis
	)
end

local function getNormalCameraTarget()
	if not root or not originalCameraOffset then
		return nil
	end

	-- Keep a conventional third-person position behind and above
	-- the player rather than looking at their feet.
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

local function startLoopCamera()
	captureOriginalCamera()

	camera = workspace.CurrentCamera

	if not camera then
		return
	end

	-- Exact requested camera position:
	-- old glowing-line pivot -> 90° right -> 20 studs ->
	-- 180° turn back toward the loop.
	loopCameraCFrame =
		getSideCameraCFrame()

	if not loopCameraCFrame then
		return
	end

	camera.CameraType =
		Enum.CameraType.Scriptable

	camera.CFrame =
		loopCameraCFrame

	local focusPosition =
		getSideCameraCFrame()

	if focusPosition then
		camera.Focus =
			CFrame.new(
				focusPosition.Position +
				focusPosition.LookVector * 125
			)
	end

	cameraControlling = true
end

local function restorePlayerCamera()
	camera = workspace.CurrentCamera

	if not camera then
		cameraControlling = false
		return
	end

	cameraControlling = false

	-- DO NOT restore a saved/frozen CFrame.
	--
	-- Giving CameraType back to Roblox is what makes the camera
	-- continue following the player after the loop.
	-- Give the camera back to Roblox. Do NOT assign camera.CFrame here;
	-- doing so can leave the camera visually frozen for a frame/state.
	camera.CameraType =
		originalCameraType or
		Enum.CameraType.Custom

	camera.CameraSubject =
		originalCameraSubject or
		humanoid

	loopCameraCFrame = nil
	originalCameraOffset = nil
end

local function updateLoopCamera()
	if not loopActive or not cameraControlling then
		return
	end

	camera = workspace.CurrentCamera

	if not camera or not root then
		return
	end

	if not loopCameraCFrame then
		return
	end

	------------------------------------------------------------
	-- MAIN LOOP: STATIC AERIAL SIDE VIEW
	------------------------------------------------------------

	local returnStart =
		math.max(
			FIRST_SECTION,
			LAST_SECTION -
			CAMERA_RETURN_SECTIONS +
			1
		)

	if currentSection < returnStart then
		-- Fixed spectator position: 20 studs to the right of the
		-- original guide-line direction, facing back at the loop.
		camera.CFrame =
			loopCameraCFrame

		local cameraTarget = getSideCameraCFrame()

		if cameraTarget then
			camera.Focus =
				CFrame.new(
					cameraTarget.Position +
					cameraTarget.LookVector * 125
				)
		end

		return
	end

	------------------------------------------------------------
	-- LAST 5 PIECES: MOVE TOWARD NORMAL PLAYER CAMERA
	------------------------------------------------------------

	local progress =
		(
			(currentSection - returnStart) +
			sectionProgress
		) /
		CAMERA_RETURN_SECTIONS

	progress =
		math.clamp(
			progress,
			0,
			1
		)

	-- Smoothstep.
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

		local cameraTarget = getSideCameraCFrame()

		if cameraTarget then
			camera.Focus =
				CFrame.new(
					cameraTarget.Position +
					cameraTarget.LookVector * 125
				)
		end

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
			Vector3.new(0, 2.5, 0)
		)

	-- At the end, release the camera completely.
	if progress >= 1 then
		restorePlayerCamera()
	end
end

local function startLoop(startingSection)
	if running then
		return
	end

	if not root or not root.Parent then
		refreshCharacter()
	end

	-- Default to section 1, but allow sections 2/3 to start directly.
	startingSection = tonumber(startingSection) or FIRST_SECTION
	startingSection = math.clamp(
		startingSection,
		FIRST_SECTION,
		LAST_SECTION
	)

	running = true
	loopActive = true

	currentSection = startingSection
	sectionProgress = 0

	startLoopCamera()
	pathDistance = 0

	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0

	-- The loop controller owns the character's position. Physical
	-- collision with the track can otherwise push the body through
	-- the surface or fight the CFrame placement.
	disableLoopCollisions()
	startLoopAnimation()

	debugState.status = "ENTERING"
	debugState.error = ""

	print("==========================================")
	print("[LOOP] LOOP STARTED")
	print("[LOOP] Starting section:", currentSection)
	print("[LOOP] Last section:", LAST_SECTION)
	print("[LOOP] Track offset:", TRACK_OFFSET)
	print("==========================================")
end

----------------------------------------------------------------
-- EXIT
----------------------------------------------------------------

local function beginExit(tangent)
	if not running then
		return
	end

	running = false
	loopActive = false

	-- CRITICAL:
	-- Release the Scriptable camera immediately when section 30 is
	-- reached. Do not leave the camera in the loop camera state.
	restorePlayerCamera()

	-- Preserve the final position and orientation, but do NOT
	-- start a running/exit movement phase after the loop.
	local finalCFrame = root.CFrame

	exitVelocity = Vector3.zero
	exitStart = 0

	debugState.status = "EXITING"
	debugState.error = ""

	print("==========================================")
	print("[LOOP] EXITING")
	print("[LOOP] Final section:", LAST_SECTION)
	print("[LOOP] Exit direction:", tangent)
	print("[LOOP] Exit velocity:", exitVelocity)
	print("==========================================")

	-- Keep the exact final position/orientation.
	root.CFrame = finalCFrame
	root.AssemblyLinearVelocity = Vector3.zero

	-- Immediately return control to the normal character controller.
	humanoid.WalkSpeed = NORMAL_WALK_SPEED
	humanoid.AutoRotate = oldAutoRotate
	stopLoopAnimation()
	restoreLoopCollisions()

	debugState.status = "IDLE"
	print("[LOOP] LOOP COMPLETE - character stopped at exit")
	print("[LOOP CAMERA] Released - Roblox camera restored")
end

----------------------------------------------------------------
-- EXIT UPDATE
----------------------------------------------------------------

local function updateExit()
	if not root or not root.Parent then
		return
	end

	local elapsed = os.clock() - exitStart

	if elapsed < EXIT_TIME then
		updateLoopAnimation()

		-- Keep forward momentum.
		-- Gravity is allowed to work normally; we do NOT launch
		-- the player upward.
		root.AssemblyLinearVelocity = Vector3.new(
			exitVelocity.X,
			root.AssemblyLinearVelocity.Y,
			exitVelocity.Z
		)
	else
		humanoid.WalkSpeed = NORMAL_WALK_SPEED
		humanoid.AutoRotate = oldAutoRotate

		stopLoopAnimation()
		restoreLoopCollisions()

		debugState.status = "IDLE"

		print("==========================================")
		print("[LOOP] EXIT COMPLETE")
		print("[LOOP] Normal movement restored")
		print("==========================================")

		exitStart = 0
	end
end

----------------------------------------------------------------
-- MAIN LOOP UPDATE
----------------------------------------------------------------

local function updateLoop(dt)
	if not loopActive or not running then
		return
	end

	updateLoopAnimation()

	if not character or not character.Parent or not root or not root.Parent then
		debugState.error = "Character/root disappeared"
		running = false
		return
	end

	-- Advance through the numbered physical sections.
	local currentCenter = sectionCenters[currentSection]
	local nextCenter

	if currentSection < LAST_SECTION then
		nextCenter = sectionCenters[currentSection + 1]
	else
		nextCenter = currentCenter +
			(currentCenter - sectionCenters[currentSection - 1])
	end

	local sectionLength = (nextCenter - currentCenter).Magnitude

	if sectionLength < 0.01 then
		debugState.error = "Section length is nearly zero"
		return
	end

	sectionProgress += (LOOP_SPEED * dt) / sectionLength

	while sectionProgress >= 1 and currentSection < LAST_SECTION do
		sectionProgress -= 1
		currentSection += 1

		print("[LOOP] Entered section", currentSection)
	end

	-- SECTION 30 IS TERMINAL.
	-- Never extrapolate beyond it and never wrap to section 1.
	if currentSection == LAST_SECTION and sectionProgress >= 1 then

		local tangent =
			getTangent(LAST_SECTION)

		-- Search the ACTUAL physical geometry of section 30.
		local bestHit = nil
		local bestDistance = math.huge

		for _, part in ipairs(
			sections[LAST_SECTION].parts
			) do

			local sample =
				part.Position

			local rayDirection =
				getInwardDirection(
					sample,
					tangent
				)

			local result =
				workspace:Raycast(
					sample -
					rayDirection *
					RAY_START_DISTANCE,

					rayDirection *
					RAY_LENGTH,

					rayParams
				)

			if result then

				local distance =
					(
						result.Position -
						root.Position
					).Magnitude

				if distance < bestDistance then
					bestDistance = distance
					bestHit = result
				end

			end

		end

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

				debugState.progress = 1

				debugState.expectedSection =
					LAST_SECTION

				debugState.hitName =
					bestHit.Instance:GetFullName()

				debugState.hitSection =
					getSectionNumberFromHit(
						bestHit.Instance
					)

				debugState.rayHit = true

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

				debugState.error = ""

				drawDebug()
				debugFrame(os.clock())

			end

		else

			debugState.status =
				"FINAL RAYCAST FAILED"

			debugState.error =
				"Section 30 physical geometry could not be raycast"

			drawDebug()
			debugFrame(os.clock())

		end

		-- Detach naturally and continue forward.
		beginExit(tangent)

		return
	end

	local pathPoint = getPathPoint(currentSection, sectionProgress)

	local tangent = getTangent(currentSection)
	local rayDirection = getInwardDirection(pathPoint, tangent)

	local hit, rayOrigin, rayEnd = raycastTrack(pathPoint, rayDirection)

	debugState.section = currentSection
	debugState.progress = sectionProgress
	debugState.expectedSection = currentSection
	debugState.tangent = tangent
	debugState.inward = rayDirection
	debugState.rayOrigin = rayOrigin
	debugState.rayEnd = rayEnd
	debugState.error = ""

	if not hit then

		-- The guide ray can miss at a seam because the section-center
		-- path is only a guide. Recover from the actual physical pieces.
		local bestHit = nil
		local bestDistance = math.huge

		for _, part in ipairs(
			sections[currentSection].parts
			) do

			local sample =
				part.Position

			local recoveryDirection =
				getInwardDirection(
					sample,
					tangent
				)

			local candidate =
				workspace:Raycast(
					sample -
					recoveryDirection *
					RAY_START_DISTANCE,

					recoveryDirection *
					RAY_LENGTH,

					rayParams
				)

			if candidate then

				local distance =
					(
						candidate.Position -
						root.Position
					).Magnitude

				if distance < bestDistance then
					bestDistance = distance
					bestHit = candidate
				end

			end

		end

		if bestHit then

			hit = bestHit

			debugState.error =
				"GUIDE RAY MISSED; PHYSICAL SECTION RECOVERY USED"

			dprint(
				"Recovered from physical geometry:",
				currentSection
			)

		else

			debugState.rayHit = false
			debugState.hitName = "NONE"
			debugState.hitSection = 0
			debugState.status =
				"RAYCAST FAILED"

			debugState.error =
				"Guide ray AND physical-section recovery ray missed"

			dprint(
				"RAYCAST FAILED",
				"section=", currentSection,
				"progress=", sectionProgress
			)

			drawDebug()
			debugFrame(os.clock())

			return

		end

	end

	local hitSection = getSectionNumberFromHit(hit.Instance)

	debugState.rayHit = true
	debugState.hitName = hit.Instance:GetFullName()
	debugState.hitSection = hitSection
	debugState.status = "RUNNING"

	-- IMPORTANT:
	-- The physical surface is authoritative.
	-- We do not reject a ray hit merely because it crossed into
	-- the next numbered section.
	--
	-- Adjacent section hits are normal because the character is
	-- continuously moving along the seam between physical pieces.
	if math.abs(hitSection - currentSection) > 1 then
		debugState.error =
			"Ray hit a non-adjacent section: expected " ..
			currentSection .. ", got " .. hitSection

		dprint("WARNING:", debugState.error)
	end

	-- The raycast surface normal is now authoritative.
	local placed, physicalInward, up, targetPosition =
		placeCharacterFromSurface(hit, tangent)

	if not placed then
		debugState.error = "Failed to construct physical surface orientation"
		drawDebug()
		debugFrame(os.clock())
		return
	end

	debugState.inward = physicalInward
	debugState.targetPosition = targetPosition
	debugState.targetDistance =
		(root.Position - hit.Position).Magnitude
	debugState.bodySupportDistance =
		getCharacterSupportDistance(-physicalInward)

	-- This is the actual post-placement measurement.
	-- It should be essentially exactly TRACK_OFFSET.
	debugState.surfaceDistance = (root.Position - hit.Position).Magnitude

	local actualError = math.abs(
		debugState.surfaceDistance -
			debugState.targetDistance
	)

	if actualError > 0.05 then
		debugState.error =
			string.format(
				"OFFSET ERROR: %.3f studs (target %.3f)",
				debugState.surfaceDistance,
				TRACK_OFFSET + LOOP_BODY_CLEARANCE
			)
	end

	updateLoopCamera()

	drawDebug()
	debugFrame(os.clock())
end

----------------------------------------------------------------
-- TRIGGER DETECTION
----------------------------------------------------------------

local touchDebounce = false

local function isCharacterPart(part)
	return character and part and part:IsDescendantOf(character)
end

-- Sections that can directly start the loop.
-- Touching any of these will begin the loop from that section.
local ENTRY_SECTIONS = {
	[1] = true,
	[2] = true,
	[3] = true,
}

local function connectEntryTriggers()
	for sectionNumber, enabled in pairs(ENTRY_SECTIONS) do
		if enabled and sections[sectionNumber] then

			for _, part in ipairs(sections[sectionNumber].parts) do
				part.Touched:Connect(function(hit)

					if touchDebounce then
						return
					end

					if not isCharacterPart(hit) then
						return
					end

					touchDebounce = true

					-- Start from the section that was actually touched.
					startLoop(sectionNumber)

					task.delay(0.5, function()
						touchDebounce = false
					end)

				end)
			end

			print(
				"[LOOP] Entry trigger connected: section",
				sectionNumber
			)
		end
	end
end

----------------------------------------------------------------
-- CwwHARACTER RESPAWN
----------------------------------------------------------------

player.CharacterAdded:Connect(function()
	running = false
	loopActive = false
	restorePlayerCamera()
	exitStart = 0
	task.wait()
	refreshCharacter()
end)

----------------------------------------------------------------
-- INITIALIZE
----------------------------------------------------------------

loadSections()
updateRaycastFilter()
refreshCharacter()
connectEntryTriggers()

RunService.Heartbeat:Connect(function(dt)
	if exitStart > 0 then
		updateExit()
		return
	end

	updateLoop(dt)
end)

print("[LOOP] System initialized successfully.")