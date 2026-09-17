local Players = game:GetService("Players")

local ID = 11431783444
local description = Players:GetHumanoidDescriptionFromUserId(ID)

local bacon = Players:CreateHumanoidModelFromDescription(
	description, Enum.HumanoidRigType.R15
)

bacon.Name = "BaconBack"
bacon.Parent = workspace

print("done")