local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local character = script.Parent
local hrp = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local controllerManager = character:findFirstChild("ControllerManager")

local loopModel = Workspace:WaitForChild("LoopModel")

local GRAVITY_STRENGTH = 196.2
local RAY_CAST_LENGTH = 12

local attachment = Instance.new("Attachment", )