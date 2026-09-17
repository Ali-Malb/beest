-- << RETRIEVE FRAMEWORK >>
local main = _G.HDAdminMain
local settings = main.settings



-- << COMMANDS >>
local module = {
	
	--[[ -- Remove this to test custom commands!!
	-----------------------------------
	{
	Name = "example1";
	Aliases	= {};
	Prefixes = {};
	Rank = 0;
	RankLock = false;
	Loopable = false;
	Tags = {};
	Description = "";
	Contributors = {};
	--
	Args = {};
	Function = function(speaker, args)
		print("HELLO (Server)")
	end;
	UnFunction = function(speaker, args)
		print("GOODBYE (Server)")
	end;
	--
	};
	
	
	
	
	-----------------------------------
	{
	Name = "example2";
	Aliases	= {};
	Prefixes = {};
	Rank = 0;
	RankLock = false;
	Loopable = false;
	Tags = {};
	Description = "";
	Contributors = {};
	--
	Args = {};
	ClientCommand = true;
	FireAllClients = true;
	CanUndo = true;
	Function = function(speaker, args)
		print("HELLO (Server -> Client)")
	end;
	UnFunction = function(speaker, args)
		print("GOODBYE (Server -> Client)")
	end;
	--
	};
	
	
	
	--]]
	-----------------------------------
	
};



return module
