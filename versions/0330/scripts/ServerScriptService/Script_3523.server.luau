local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local bestTimeStore = DataStoreService:GetDataStore("SpeedrunBestTimes_V1")
local finishPart = workspace:WaitForChild("FinishPart")
local spawnLocation2 = workspace:WaitForChild("SpawnLocation2")

local startTimes = {}
local bestTimes = {}
local finishedThisRun = {}

print("================================")
print("[SPEEDRUN] SERVER SCRIPT STARTED")
print("[SPEEDRUN] FinishPart found:", finishPart:GetFullName())
print("[SPEEDRUN] CanTouch:", finishPart.CanTouch)
print("[SPEEDRUN] SpawnLocation2 found:", spawnLocation2:GetFullName())
print("================================")


--==================================================
-- LOAD DATA
--==================================================

Players.PlayerAdded:Connect(function(player)

	print("[SPEEDRUN] Player joined:", player.Name)

	local success, savedTime = pcall(function()
		return bestTimeStore:GetAsync("Player_" .. player.UserId)
	end)

	if success and typeof(savedTime) == "number" then

		bestTimes[player] = savedTime
		player:SetAttribute("BestTime", savedTime)

		print(
			"[SPEEDRUN] Loaded PB for",
			player.Name,
			string.format("%.3f", savedTime)
		)

	else

		bestTimes[player] = nil
		player:SetAttribute("BestTime", 0)

		if not success then
			warn(
				"[SPEEDRUN] Failed to load PB for",
				player.Name
			)
		end

	end


	--==================================================
	-- CHARACTER
	--==================================================

	player.CharacterAdded:Connect(function(character)

		local humanoid =
			character:WaitForChild("Humanoid")

		startTimes[player] = nil
		finishedThisRun[player] = false

		print(
			"[SPEEDRUN] Character loaded for",
			player.Name
		)


		--==================================================
		-- START TIMER WHEN PLAYER MOVES
		--==================================================

		humanoid.Running:Connect(function(speed)

			if speed > 0
				and not startTimes[player]
				and not finishedThisRun[player] then

				startTimes[player] = os.clock()

				print("================================")
				print("[SPEEDRUN] TIMER STARTED")
				print("[SPEEDRUN] Player:", player.Name)
				print("================================")

			end

		end)

	end)

end)


--==================================================
-- FINISH FUNCTION
--==================================================

local function finishPlayer(player)

	if not player then
		return
	end


	print(
		"[SPEEDRUN] Finish detected for:",
		player.Name
	)


	-- Already finished
	if finishedThisRun[player] then

		print(
			"[SPEEDRUN] Already finished this run."
		)

		return

	end


	-- Player never started
	if not startTimes[player] then

		warn(
			"[SPEEDRUN] Player touched finish but has NO START TIME:",
			player.Name
		)

		return

	end


	--==================================================
	-- STOP TIMER
	--==================================================

	local finalTime =
		os.clock() - startTimes[player]

	startTimes[player] = nil
	finishedThisRun[player] = true


	print("================================")
	print("[SPEEDRUN] FINISHED!")
	print("[SPEEDRUN] Player:", player.Name)
	print(
		"[SPEEDRUN] Time:",
		string.format("%.3f", finalTime)
	)
	print("================================")


	--==================================================
	-- CHECK PERSONAL BEST
	--==================================================

	local currentBest =
		bestTimes[player]

	local isNewBest = false


	if not currentBest
		or finalTime < currentBest then

		-- NEW PB
		isNewBest = true

		bestTimes[player] = finalTime

		player:SetAttribute(
			"BestTime",
			finalTime
		)


		print(
			"[SPEEDRUN] 🏆 NEW PERSONAL BEST!"
		)


		--==================================================
		-- CHANGE SPAWN LOCATION
		--==================================================

		player.RespawnLocation =
			spawnLocation2

		print(
			"[SPEEDRUN] Respawn changed to SpawnLocation2"
		)


		--==================================================
		-- SAVE NEW BEST
		--==================================================

		local success, errorMessage =
			pcall(function()

				bestTimeStore:SetAsync(
					"Player_" .. player.UserId,
					finalTime
				)

			end)


		if success then

			print(
				"[SPEEDRUN] PB SAVED SUCCESSFULLY"
			)

		else

			warn(
				"[SPEEDRUN] DATASTORE ERROR:",
				errorMessage
			)

		end


	else

		print(
			"[SPEEDRUN] Not a new PB."
		)

		print(
			"[SPEEDRUN] Existing PB:",
			currentBest
		)

	end


	--==================================================
	-- SEND RESULT TO CLIENT
	--==================================================

	-- Clear old values first so every run triggers
	-- the LocalScript event.

	player:SetAttribute(
		"FinalTime",
		nil
	)

	player:SetAttribute(
		"NewBest",
		nil
	)


	task.wait()


	player:SetAttribute(
		"FinalTime",
		finalTime
	)

	player:SetAttribute(
		"NewBest",
		isNewBest
	)


	print(
		"[SPEEDRUN] Result sent to client."
	)

end


--==================================================
-- NORMAL TOUCHED DETECTION
--==================================================

finishPart.Touched:Connect(function(hit)

	print(
		"[SPEEDRUN] FinishPart touched by:",
		hit:GetFullName()
	)


	local character =
		hit:FindFirstAncestorOfClass("Model")


	if not character then

		warn(
			"[SPEEDRUN] Touch was not a character."
		)

		return

	end


	local humanoid =
		character:FindFirstChildOfClass("Humanoid")


	if not humanoid then

		warn(
			"[SPEEDRUN] Touching object has no Humanoid."
		)

		return

	end


	local player =
		Players:GetPlayerFromCharacter(character)


	if not player then

		warn(
			"[SPEEDRUN] Could not find player."
		)

		return

	end


	finishPlayer(player)

end)


--==================================================
-- BACKUP DETECTION
--==================================================

-- Checks every 0.1 seconds if the player is physically
-- inside FinishPart.

task.spawn(function()

	while true do

		task.wait(0.1)


		for _, player in ipairs(
			Players:GetPlayers()
			) do

			local character =
				player.Character


			if character then

				local root =
					character:FindFirstChild(
						"HumanoidRootPart"
					)


				if root
					and startTimes[player]
					and not finishedThisRun[player] then


					local relativePosition =
						finishPart.CFrame:PointToObjectSpace(
							root.Position
						)


					local halfSize =
						finishPart.Size / 2


					if math.abs(relativePosition.X)
						<= halfSize.X

						and math.abs(relativePosition.Y)
						<= halfSize.Y

						and math.abs(relativePosition.Z)
						<= halfSize.Z then


						print(
							"[SPEEDRUN] BACKUP DETECTION FOUND PLAYER:",
							player.Name
						)


						finishPlayer(player)

					end

				end

			end

		end

	end

end)


--==================================================
-- PLAYER LEAVING
--==================================================

Players.PlayerRemoving:Connect(function(player)

	startTimes[player] = nil
	bestTimes[player] = nil
	finishedThisRun[player] = nil

end)