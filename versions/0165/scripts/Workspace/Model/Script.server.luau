local part = script.Parent

local move_dist = 50
local speed = 30

local start_pos = part.CFrame
while true do 
	local currentTime = os.clock()
	local offset = math.sin(currentTime*speed) *move_dist
	part.CFrame = start_pos + Vector3.new(0, offset, 0)
	task.wait()
end