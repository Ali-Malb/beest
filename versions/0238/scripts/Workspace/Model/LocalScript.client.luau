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
end

