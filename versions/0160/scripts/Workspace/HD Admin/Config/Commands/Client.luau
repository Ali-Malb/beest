-- << RETRIEVE FRAMEWORK >>
local main = _G.HDAdminMain



-- << CLIENT COMMANDS >>
local module = {
	
	----------------------------------------------------------------------
	["example2"] = {
		Function = function(speaker, args)
			print("HELLO (Client)")
		end;
		UnFunction = function(speaker, args)
			print("GOODBYE (Client)")
		end;
		};
	
	
	
	
	----------------------------------------------------------------------
	
};



-- << SETUP >>
for commandName, command in pairs(module) do
	command.Name = commandName
end



return module