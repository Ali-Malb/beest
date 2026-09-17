local model = script.Parent

local move_dist = 10
local speed = 5

local start_p = model:GetPivot()

while true do local currentTime = os.clock()
	local offset = math.sin(currentTime * speed) * move_dist
	model:PivotTo(start_p + Vector3.new(0, offset, 0))
	task.wait()
end