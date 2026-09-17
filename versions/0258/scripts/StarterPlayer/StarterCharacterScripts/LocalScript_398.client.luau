local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local character = script.Parent
local hrp = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local controllerManager = character:findFirstChild("ControllerManager")

local loopModel = Workspace:WaitForChild("LoopModel")

local GRAVITY_STRENGTH = 196.2
local RAY_CAST_LENGTH = 15

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


RunService.Heartbeat:Connect(function()
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {loopModel}
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	local rayDirection = -hrp.CFrame.UpVector * RAY_CAST_LENGTH
	local raycastResult = Workspace:Raycast(hrp.Position, rayDirection, raycastParams)

	if raycastResult then
		if not controllerManager then humanoid.PlatformStand = true end
		local targetUpVector = raycastResult.Normal
		local surfacePosition = raycastResult.Position

		local antiWorldGravity = Vector3.new(0, Workspace.Gravity* totalMass, 0)
		local loopPullForce = -targetUpVector  * totalMass * GRAVITY_STRENGTH
		vectorForce.Force = antiWorldGravity + loopPullForce

		local currentRight = hrp.CFrame.RightVector
		local targetForward = currentRight:Cross(targetUpVector).Unit
		local targetRight = targetUpVector:Cross(targetForward).Unit
		local safePosition = surfacePosition + (targetUpVector * 3.8)
		hrp.CFrame = CFrame.fromMatrix(safePosition, targetRight, targetUpVector, -targetForward)

		local moveDirection = humanoid.MoveDirection
		if moveDirection.Magnitude > 0 then
			local speed = humanoid.WalkSpeed
			hrp.AssemblyLinearVelocity = hrp.CFrame.LookVector * speed
		else
			local verticalVelocity = hrp.AssemblyLinearVelocity:Dot(targetUpVector) * targetUpVector
			hrp.AssemblyLinearVelocity = verticalVelocity
		end
		if controllerManager then
			controllerManager.UpDirection = targetUpVector
		end
	else  
		humanoid.PlatformStand = false
		vectorForce.Force = Vector3.new(0,0, 0)
	end
end)