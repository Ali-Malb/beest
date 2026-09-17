print("Hello world!")

local part = script.Parent


local NEW_SPEED = 50
local OLD_SPEED = 10

local function onTouched(hit)
	local character = hit.Parent
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.JumpPower = 5000
	end
end


part.Touched:Connect(onTouched)