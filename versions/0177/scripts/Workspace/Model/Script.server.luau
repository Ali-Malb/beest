local part = script.Parent

local function onTouched(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.JumpPower = 80
		humanoid.UseJumpPower =  true
	end
end

for _, child in ipairs(part:GetChildren()) do
	if child:IsA("BasePart") then
		child.Touched:Connect(onTouched())
	end
end

part.Touched:Connect(onTouched)