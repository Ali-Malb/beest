local model = script.Parent

local function onTouched(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.JumpPower = 80
		humanoid.UseJumpPower =  true
	end
end

for _, child in ipairs(model:GetChildren()) do
	if child:IsA("BasePart") then
		child.Touched:Connect(onTouched()
	end
end