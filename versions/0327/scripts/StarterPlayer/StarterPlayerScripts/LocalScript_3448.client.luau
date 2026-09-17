local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local WALL_NAME = "Barrier"
local OVERLAY_NAME = "Overlay"
local MAX_DISTANCE = 10
local MIN_DISTANCE = 2
local FADE_EXPONENT = 2

local barriers = {}

local function registerBarrier(part: Instance)
	if part.Name == WALL_NAME and part:IsA("BasePart") then
		local decal = part:FindFirstChildOfClass("Decal") or part:FindFirstChild(OVERLAY_NAME)
		if decal and decal:IsA("Decal") then 
			table.insert(barriers, { wall = part, decal = decal })
		end
	end
end
for _, descendant in ipairs(Workspace:GetDescendants()) do
	registerBarrier(descendant)
end
Workspace.DescendantAdded:Connect(registerBarrier)

RunService.RenderStepped:Connect(function()
	local character	= player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart") ::BasePart?
	if not root then return end

	for _, item in ipairs(barriers) do
		local wall = item.wall
		local decal = item.decal
		
		if wall and wall.Parent and decal and decal.Parent then
			local localPoint = wall.CFrame:PointToObjectSpace(root.Position)
			local halfSize = wall.Size / 2
			local closestPoint = Vector3.new(
				math.clamp(localPoint.X, -halfSize.X, halfSize.X),
				math.clamp(localPoint.Y, -halfSize.Y, halfSize.Y),
				math.clamp(localPoint.Z, -halfSize.Z, halfSize.Z)
			)
			local distance = (localPoint - closestPoint).Magnitude
			local alpha = math.clamp(
				(distance - MIN_DISTANCE) / (MAX_DISTANCE - MIN_DISTANCE), 0, 1
			)
			decal.Transparency = alpha ^ FADE_EXPONENT
		end
	end
end)

print("Complete!")