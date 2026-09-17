local teleportPart = script.Parent
local destination = workspace:WaitForChild("Destination")

teleportPart.Touched:Connect(function(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")

	if humanoid then
		character:PivotTo(destination.CFrame + Vector3.new(0, 3, 0))
	end
end)print("Hello world!")
