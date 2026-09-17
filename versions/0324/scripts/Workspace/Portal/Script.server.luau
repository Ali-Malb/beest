local portal = script.Parent

portal.Touched:Connect(function(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		character:PivotTo(CFrame.new(1102.98, 115.962, 825.32))
	end
end)