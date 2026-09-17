local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local character = script.Parent
local hrp = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local controllerManager = character:findFirstChild("ControllerManager")

local loopModel = Workspace:WaitForChild("LoopModel")

local GRAVITY_STRENGTH = 196.2
local RAY_CAST_LENGTH = 12

local attachment = Instance.new("Attachment", hrp)
local vectorForce = Instance.new("VectorForce")
vectorForce.Attachment0 = attachment
vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
vectorForce.ApplyAtCenterOfMass = true
vectorForce.Parent = hrp

local function getCharacterMass()
	local mass = 0
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and not part.Massless then
			mass += part:GetMass()
		end
	end
	return mass
end

local totalMass = getCharacterMass()

if not controllerManager then
	humanoid.PlatformStand = true
end

RunService.Heartbeat:Connect(function()
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {loopModel}
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	
	local rayDirection = -hrp.CFrame.UpVector * RAY_CAST_LENGTH
	local raycayResult = Workspace:Raycast(hrp.Position, rayDirection, raycastParams)
	local targetUpVector = Vector3.new(0, 1, 0)
	
	if raycayResult then
		targetUpVector = raycayResult.Normal
	end
	
	local gravityDirection = -targetUpVector
	vectorForce.Force = gravityDirection * totalMass * GRAVITY_STRENGTH
	
	if controllerManager then
		controllerManager.UpDirection = targetUpVector
	else
		local currentRight = hrp.CFrame.RightVector
		local targetForward = currentRight:Cross(targetUpVector).Unit
		local targetRight = targetUpVector:Cross(targetForward).Unit
		hrp.CFrame = CFrame.fromMatrix(hrp.Position, targetRight, targetUpVector, targetForward)
	end
end)