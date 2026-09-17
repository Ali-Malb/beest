local part = script.Parent


local NEW_SPEED = 50
local OLD_SPEED = 10

local function onTouched(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = OLD_SPEED
		humanoid.JumpPower = 50
		humanoid.UseJumpPower =  true
	end
	local sprintScript = character:FindFirstChild("LocalScript")
	if sprintScript == false then
		sprintScript.Enabled = true
	end
end


part.Touched:Connect(onTouched)