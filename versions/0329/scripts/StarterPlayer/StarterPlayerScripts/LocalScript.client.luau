local remote = game.ReplicatedStorage:WaitForChild("PickUpBacon")

print("Pickup LocalScript loaded")

remote.OnClientEvent:Connect(function(model)
	print("Received pickup:", model.Name)

	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.LocalTransparencyModifier = 1
		end
	end
end)