local portal = script.Parent

portal.Touched:Connect(function(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		character:PivotTo(CFrame.new(-546.97, 14.978, -1002.983))
	end
end)