local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local player = Players.LocalPlayer
local hrt = character:WaitForChild("HumanoidRootPart")
local LOOP_EXIT_GRACE_FRAMES = 6

local GRAVITY_STRENGTH = 196.2 
local RAYCAST_LENGTH = 6
local LOOP_OFFSET = 3
local MIN_LOOP_SPEED = 24
local NORMAL_SMOOTHING =0.25
local ORIENTATION_RESPONSIVENESS = 25
local INPUT_ACCEL =60

local MAX_LOOP_SPEED = 90
local VELOCITY_SERVO_FORCE = 25000
local OFFSET_CORRECTION_GAIN = 8
local FORWARD_SMOOTHING = 0.15
local MAX_OFFSET_CORRECTION = 20

--//
local loopModel =Workspace:FindFirstChild("LoopModel") or Workspace:WaitForChild("LoopModel", 10)

local raycastParams = nil
if loopModel then
	raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = {loopModel}
	raycastParams.IgnoreWater = true
end

local isLoopActive = false
local missedFrames = 0
local currentNormal = Vector3.new(0, 1, 0)
local currentForward = hrt.CFrame.LookVector

local loopAttachment
local gravityForce
local alignOrientation
local velocityServo

local function createForces()
	loopAttachment = Instance.new("Attachment")
	loopAttachment.Name = "LoopControllerAttachment"
	loopAttachment.Parent = hrt

	gravityForce = Instance.new("VectorForce")
	gravityForce.Name = "LoopGravityForce"
	gravityForce.Attachment0 = loopAttachment
	gravityForce.Force = Vector3.new(0, 0, 0)
	gravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
	gravityForce.ApplyAtCenterOfMass = true
	gravityForce.Parent = hrt

	alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "LoopAlignOrientation"
	alignOrientation.Attachment0 = loopAttachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.RigidityEnabled = false
	alignOrientation.Responsiveness = ORIENTATION_RESPONSIVENESS
	alignOrientation.MaxTorque = math.huge
	alignOrientation.MaxAngularVelocity = math.huge
	alignOrientation.CFrame = hrt.CFrame
	alignOrientation.Parent = hrt
	alignOrientation.Enabled = false

	velocityServo = Instance.new("LinearVelocity")
	velocityServo.Name = "LoopVelocityServo"
	velocityServo.Attachment0 = loopAttachment
	velocityServo.RelativeTo = Enum.ActuatorRelativeTo.World
	velocityServo.MaxForce = VELOCITY_SERVO_FORCE
	velocityServo.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocityServo.VectorVelocity = Vector3.new(0, 0, 0)
	velocityServo.Enabled = false
	velocityServo.Parent = hrt
end

local function raycastLoop()
	if not loopModel or not raycastParams then 
		return nil, nil 
	end
	local origin = hrt.Position
	local direction = -currentNormal * RAYCAST_LENGTH

	local sampleOrigins = {
		origin,
		origin + currentForward * 1.5,
		origin - currentForward * 1.5,
	}
	local normalSum = Vector3.new(0, 0, 0)
	local distanceSum = 0
	local hitCount = 0 
	for _, sampleOrigin in ipairs(sampleOrigins) do
		local result = Workspace:Raycast(sampleOrigin, direction, raycastParams)
		if result then
			hitCount += 1
			normalSum += result.Normal
			distanceSum += result.Distance
		end
	end
	if hitCount == 0 then
		return nil, nil
	end
	local avgNormal = normalSum / hitCount
	return avgNormal.Unit, distanceSum / hitCount
end

local function updateGravity(normal)	
	local mass = hrt.AssemblyMass
	local counterGravity = Vector3.new(0, Workspace.Gravity, 0) * mass
	local fakeGravity = -normal * GRAVITY_STRENGTH * mass
	gravityForce.Force = counterGravity + fakeGravity
end

local function updateOrientation(normal)
	local velocity = hrt.AssemblyLinearVelocity
	local tangentVelocity = velocity - normal * velocity:Dot(normal)

	local forward
	if tangentVelocity.Magnitude > 1.5 then
		forward = tangentVelocity.Unit
	else
		local projected = currentForward - normal *currentForward:Dot(normal)
		if projected.Magnitude > 0.001 then
			forward = projected.Unit
		else
			forward = hrt.CFrame.LookVector
		end
	end
	currentForward = forward
	alignOrientation.CFrame = CFrame.lookAt(hrt.Position, hrt.Position + forward, normal)
end

local function updateMovement(normal, hitDistance, dt)
	local velocity = hrt.AssemblyLinearVelocity
	local tangentSpeed = (velocity - normal * velocity:Dot(normal)):Dot(currentForward)
	local throttle = humanoid.MoveDirection:Dot(currentForward)
	local targetSpeed = tangentSpeed + throttle * INPUT_ACCEL * dt
	targetSpeed = math.clamp(targetSpeed, MIN_LOOP_SPEED, MAX_LOOP_SPEED)

	local offsetError = LOOP_OFFSET - hitDistance
	local normalCorrection = math.clamp(offsetError * OFFSET_CORRECTION_GAIN, -MAX_OFFSET_CORRECTION, MAX_OFFSET_CORRECTION)
	velocityServo.VectorVelocity = (currentForward * targetSpeed) + (normal * normalCorrection)
end

local function enableLoop()
	isLoopActive = true
	missedFrames = 0
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	gravityForce.Enabled = true
	velocityServo.Enabled = true
	alignOrientation.Enabled = true
end

local function disableLoop()
	isLoopActive = false
	missedFrames = 0
	humanoid.AutoRotate = true
	gravityForce.Enabled = false
	velocityServo.Enabled = false
	humanoid.PlatformStand = false
	alignOrientation.Enabled = false
	currentNormal = Vector3.new(0, 1, 0)
end

local hearbeatConnection
hearbeatConnection = RunService.Heartbeat:Connect(function(dt)
	if not humanoid or humanoid.Health <= 0 or not hrt or not hrt.Parent then
		return
	end
	if not loopModel then 
		return
	end
	local hitNormal, hitDistance = raycastLoop()
	if hitNormal then
		missedFrames = 0
		if not isLoopActive then
			enableLoop()
		end
		currentNormal = currentNormal:Lerp(hitNormal, NORMAL_SMOOTHING)
		if currentNormal.Magnitude > 0.001 then
			currentNormal = currentNormal.Unit
		end
		updateGravity(currentNormal)
		updateOrientation(currentNormal)
		updateMovement(currentNormal, hitDistance, dt)
	elseif isLoopActive then
		missedFrames += 1
		if missedFrames >= LOOP_EXIT_GRACE_FRAMES then
			disableLoop()
		else 
			updateGravity(currentNormal)
			updateOrientation(currentNormal)
			updateMovement(currentNormal, LOOP_OFFSET, dt)
		end
	end

end)

humanoid.Died:Connect(function()
	if hearbeatConnection then
		hearbeatConnection:Disconnect()
	end
end)

createForces()