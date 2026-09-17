local part = script.Parent

local function onTouched(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.JumpPower = 50
		humanoid.UseJumpPower = true
	end
end


part.Touched:Connect(onTouched)