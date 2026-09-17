local part = script.Parent

local move_dist = 5
local speed = 3

local start_pos = part.Position
while true do 
	local currentTime = os.clock()
	local offset = math.sin(currentTime*speed) *move_dist
	part.Position = start_pos Vector3.new(0, offset, 0)
	task.wait()
end