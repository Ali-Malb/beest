local core = script.Parent
local loader = core.Parent
local mainModule = require(core:WaitForChild("MainModule"))
mainModule.initialize(loader)