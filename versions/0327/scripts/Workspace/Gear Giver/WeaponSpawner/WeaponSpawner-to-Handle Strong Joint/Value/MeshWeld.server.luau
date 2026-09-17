local serverstate = game.JobId ~= ""

if serverstate then
	return require(script.Parent.MaxValue)
end