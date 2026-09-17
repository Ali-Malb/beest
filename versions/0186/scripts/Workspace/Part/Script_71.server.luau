local part = script.Parent


local NEW_SPEED = 50
local OLD_SPEED = 10

local function onTouched(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = NEW_SPEED
	end
	local sprintScript = character:FindFirstChild("LocalScript")
	if sprintScript then
		local Touchedblock = true
	end
end


part.Touched:Connect(onTouched)