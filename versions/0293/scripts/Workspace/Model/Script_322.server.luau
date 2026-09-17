local model = script.Parent

local function onTouched(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 200
		humanoid.UseWalkSpeed =  true
	end
end

for _, child in ipairs(model:GetChildren()) do
	if child:IsA("BasePart") then
		child.Touched:Connect(onTouched)
	end
end
