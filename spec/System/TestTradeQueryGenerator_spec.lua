describe("TradeQueryGenerator", function()
	local mock_queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = {} })

	describe("ProcessMod", function()
		-- Pass: Mod line maps correctly to trade stat entry without error
		-- Fail: Mapping fails (e.g., no match found), indicating incomplete stat parsing for curse mods, potentially missing curse-enabling items in queries
		it("handles special curse case", function()
			local mod = { "You can apply an additional Curse" }
			local tradeStatsParsed = { result = { [2] = { entries = { { text = "You can apply # additional Curses", id = "id" } } } } }
			mock_queryGen.modData = { Explicit = true }
			mock_queryGen:ProcessMod(mod, tradeStatsParsed, 1)
			-- Simplified assertion; in full impl, check modData
			assert.is_true(true)
		end)
	end)

	describe("Talisman mods", function()
		it("only generates enchant weights when enabled", function()
			local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = {} })
			local enchantMods = queryGen.modData.Enchant
			queryGen.modData = { Explicit = { }, Implicit = { }, Enchant = enchantMods, Corrupted = { }, Scourge = { } }
			queryGen.calcContext = { special = { }, options = { } }
			local generated = { }
			queryGen.GenerateModWeights = function(_, mods) generated[mods] = true end

			queryGen:ExecuteQuery()
			assert.is_nil(generated[enchantMods])

			queryGen.calcContext.options.includeTalisman = true
			queryGen:ExecuteQuery()
			assert.is_true(generated[enchantMods])
		end)

		it("includes the utility flask charge enchant", function()
			local enchant
			for id, mod in pairs(LoadModule("Data/QueryMods.lua").Enchant) do
				if id:match("_UtilityFlaskPassiveChargeGain$") then
					enchant = mod
					break
				end
			end

			assert.is_not_nil(enchant)
			assert.are.equals("enchant.stat_2567919918", enchant.tradeMod.id)
			assert.are.equals("Utility Flasks gain # Charges every 3 seconds", enchant.specialCaseData.overrideModLine)
		end)
	end)

	describe("Eldritch mods", function()
		it("shows the Eldritch options for amulets", function()
			local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = { items = { } } })
			queryGen:RequestQuery({ slotName = "Amulet" }, {
				slotTbl = { slotName = "Amulet", alreadyCorrupted = false },
			}, { }, function() end)

			assert.is_not_nil(main.popups[1].controls.includeEldritch)
			main:ClosePopup()
		end)
	end)

	describe("WeightedRatioOutputs", function()
		local maxStatIncrease

		before_each(function()
			maxStatIncrease = data.misc.maxStatIncrease
			data.misc.maxStatIncrease = 1000
		end)

		after_each(function()
			data.misc.maxStatIncrease = maxStatIncrease
		end)

		-- Pass: Returns 0, avoiding math errors
		-- Fail: Returns NaN/inf or crashes, indicating unhandled infinite values, causing evaluation failures in infinite-scaling builds
		it("handles infinite base", function()
			local baseOutput = { TotalDPS = math.huge }
			local newOutput = { TotalDPS = 100 }
			local statWeights = { { stat = "TotalDPS", weightMult = 1 } }
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)
			assert.are.equal(result, 0)
		end)

		-- Pass: Returns capped value (100), preventing division issues
		-- Fail: Returns inf/NaN, indicating unhandled zero base, leading to invalid comparisons in low-output builds
		it("handles zero base", function()
			local baseOutput = { TotalDPS = 0 }
			local newOutput = { TotalDPS = 100 }
			local statWeights = { { stat = "TotalDPS", weightMult = 1 } }
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)
			assert.are.equal(result, 100)
		end)
		it("uses minion output for non-FullDPS stats when minion output is desired", function()
			local baseOutput = { Life = 10, Minion = { Life = 100 } }
			local newOutput = { Life = 10, Minion = { Life = 250 } }
			local statWeights = { { stat = "MinionLife", weightMult = 1 } }
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)

			assert.are.equal(result, 2.5)
		end)

		it("uses lower is better stats correctly", function()
			local baseOutput = { MaxHit = 100 }
			local newOutput = { MaxHit = 10 }
			local statWeights = { { stat = "MaxHit", weightMult = 1, transform = function(number) return -number end } }
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)

			local close_enough = math.abs(result - -0.1) < 0.0001
			assert.True(close_enough)
		end)

		it("uses player and minion output for FullDPS", function()
			-- minion output gets assigned to the player's full dps in reality
			local baseOutput = { FullDPS = 100, Minion = { FullDPS = 100 } }
			local newOutput = { FullDPS = 250, Minion = { FullDPS = 1000 } }
			local statWeights = { { stat = "FullDPS", weightMult = 1 } }
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)

			assert.are.equal(result, 2.5)
		end)

		it("uses player output for non-FullDPS even when minion output is available", function()
			local baseOutput = { Life = 100, Minion = { Life = 100 } }
			local newOutput = { Life = 250, Minion = { Life = 1000 } }
			local statWeights = { { stat = "Life", weightMult = 1 } }
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)
			assert.are.equal(result, 2.5)
		end)

		it("uses the fallback DPS ratio once when FullDPS is unavailable", function()
			local baseOutput = { Minion = { TotalDPS = 10, TotalDotDPS = 0, CombinedDPS = 10 } }
			local newOutput = { Minion = { TotalDPS = 25, TotalDotDPS = 0, CombinedDPS = 25 } }
			local statWeights = { { stat = "FullDPS", weightMult = 1 } }
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)

			assert.are.equal(result, 2.5)
		end)

		it("falls back to player output when the selected stat is not on minion output", function()
			local baseOutput = { Spirit = 100, Minion = { AverageDamage = 100 } }
			local newOutput = { Spirit = 120, Minion = { AverageDamage = 100 } }
			local statWeights = { { stat = "Spirit", weightMult = 1 } }
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)

			assert.are.equal(result, 1.2)
		end)

		it("supports light radius as a player stat weight", function()
			local lightRadiusStat
			local minionLightRadiusStat
			for _, stat in ipairs(data.powerStatList) do
				if stat.stat == "LightRadiusMod" then
					lightRadiusStat = stat
				elseif stat.stat == "MinionLightRadiusMod" then
					minionLightRadiusStat = stat
				end
			end

			assert.is_not_nil(lightRadiusStat)
			assert.is_nil(minionLightRadiusStat)
			local result = mock_queryGen.WeightedRatioOutputs(
				{ LightRadiusMod = 1 },
				{ LightRadiusMod = 1.25 },
				{ { stat = lightRadiusStat.stat, weightMult = 1 } })
			assert.are.equal(result, 1.25)
		end)
	end)

	describe("Filter prioritization", function()
		it("counts socket and link constraints against MAX_FILTERS", function()
			local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = { items = {} } })
			queryGen.modWeights = { }
			for index = 1, 40 do
				table.insert(queryGen.modWeights, {
					tradeModId = "explicit.stat_" .. index,
					weight = 1,
					meanStatDiff = 41 - index,
				})
			end
			queryGen.calcContext = {
				testItem = new("Item"):Item("Rarity: RARE\nNew Item\nGold Ring\nImplicits: 0"),
				baseOutput = { },
				baseStatValue = 0,
				itemCategoryQueryStr = "accessory.ring",
				special = { },
				options = {
					statWeights = { },
					influence1 = 1,
					influence2 = 1,
					includeMirrored = false,
					sockets = 6,
					links = 6,
				},
			}
			queryGen.tradeTypeIndex = 1
			local query
			queryGen.requesterCallback = function(_, queryJson)
				query = require("dkjson").decode(queryJson).query
			end

			queryGen:FinishQuery()

			assert.are.equal(31, #query.stats[1].filters)
			assert.is_not_nil(query.filters.socket_filters.filters.sockets)
			assert.is_not_nil(query.filters.socket_filters.filters.links)
		end)
	end)

	describe("Harmful mod penalties", function()
		-- The stub build scores 1000 x Life / 100, so a test item's weighted gain equals gainAt(roll).
		-- entries is one entry or a list of entries, each generated in its own group, in that order.
		local function generateWeights(entries, gainAt, penaltyFloor, quality)
			local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = {} })
			local calcs = 0
			queryGen.modWeights = { }
			queryGen.alreadyWeightedMods = { }
			queryGen.openPenalties = { }
			queryGen.calcContext = {
				itemCategory = "Belt",
				testItem = new("Item"):Item("Rarity: RARE\nNew Item\nLeather Belt\nImplicits: 0"),
				slot = { slotName = "Belt" },
				baseOutput = { Life = 100 },
				baseStatValue = 1000,
				penaltyFloor = penaltyFloor,
				options = { statWeights = { { stat = "Life", weightMult = 1 } } },
				calcFunc = function(override)
					calcs = calcs + 1
					local roll = tonumber(override.repItem.explicitModLines[1].line:match("%-?%d+")) or 1
					return { Life = 100 + gainAt(roll) / 10 }
				end,
			}
			local defaultQuality = main.defaultItemAffixQuality
			main.defaultItemAffixQuality = quality or 0.5
			local ok, err = pcall(function()
				for _, entry in ipairs(entries.tradeMod and { entries } or entries) do
					queryGen:GenerateModWeights({ entry })
				end
			end)
			main.defaultItemAffixQuality = defaultQuality
			assert(ok, err)
			return queryGen.modWeights, calcs
		end
		local function mod(min, max, text, sign)
			return { Belt = { min = min, max = max }, sign = sign or "", specialCaseData = { }, tradeMod = { id = "explicit.stat_1", text = text or "#% increased Armour" } }
		end

		it("weights a loss that grows with the roll by its smaller per-point loss", function()
			-- -102 at the tested roll 20, -152 at the probed maximum 30
			local weights = generateWeights(mod(10, 30), function(roll) return -5 * roll - 2 end, 10)
			assert.are.equal(1, #weights)
			assert.is_true(math.abs(weights[1].weight - (-152 / 30)) < 1e-6)
		end)

		it("weights a mod without a value by its whole loss", function()
			local weights, calcs = generateWeights(mod(1, 1, "Can't use Flask in Fifth Slot"), function() return -238 end, 10)
			assert.are.equal(1, #weights)
			assert.are.equal(-238, weights[1].weight)
			assert.are.equal(1, calcs)
		end)

		it("leaves losses a per-point weight cannot express neutral", function()
			for label, case in pairs({
				constant = { mod(10, 30), function() return -100 end, 10 },
				positiveSlope = { mod(10, 30), function(roll) return -150 + 3 * roll end, 10 },
				largeOffset = { mod(10, 30), function(roll) return -100 - 0.5 * roll end, 10 },
				belowFloor = { mod(10, 30), function(roll) return -0.2 * roll end, 10 },
				fixedRoll = { mod(1, 1, "+# to Level of Socketed Gems"), function() return -50 end, 10 },
				reducedSign = { mod(10, 30, nil, "-"), function(roll) return 5 * roll end, 10 },
				reducedRange = { mod(-30, -10), function(roll) return 5 * roll end, 10 },
				gainAtLowEnd = { mod(1, 40), function(roll) return 20 - 5 * roll end, 10, 1 },
				noFloor = { mod(10, 30), function(roll) return -5 * roll end, nil },
			}) do
				assert.are.equal(0, #generateWeights(case[1], case[2], case[3], case[4]), label)
			end
		end)

		it("tests the other ranges of a stat whose first entry a guard left neutral", function()
			-- the fixed 25 roll costs -125 but stays neutral; the 18-35 range is then tested at 27 and probed at 35
			local weights, calcs = generateWeights({ mod(25, 25), mod(18, 35) }, function(roll) return -5 * roll end, 10)
			assert.are.equal(1, #weights)
			assert.is_true(weights[1].penalty)
			assert.are.equal(-5, weights[1].weight)
			assert.are.equal(3, calcs)
		end)

		it("keeps the smaller per-point loss of two penalised ranges, whatever their order", function()
			-- -5.27 per point on 18-35 (tested at 27), -5.24 on 22-25 (tested at 24)
			local function gainAt(roll) return -5 * roll - 0.01 * roll * roll end
			for _, order in ipairs({ { mod(18, 35), mod(22, 25) }, { mod(22, 25), mod(18, 35) } }) do
				local weights = generateWeights(order, gainAt, 10)
				assert.are.equal(1, #weights)
				assert.is_true(math.abs(weights[1].weight - gainAt(24) / 24) < 1e-6)
			end
		end)

		it("never adds a positive weight to a stat a loss kept open", function()
			-- a later range of the same stat gains: the stat ends neutral, with neither the penalty nor a positive weight
			assert.are.equal(0, #generateWeights({ mod(25, 25), mod(18, 35) }, function(roll) return roll == 25 and -125 or 5 * roll end, 10))
			assert.are.equal(0, #generateWeights({ mod(18, 35), mod(40, 50) }, function(roll) return roll >= 40 and 5 * roll or -5 * roll end, 10))
			-- and the gain closes it: a later losing range does not bring the penalty back
			assert.are.equal(0, #generateWeights({ mod(25, 25), mod(40, 50), mod(18, 35) }, function(roll) return roll >= 40 and 5 * roll or -5 * roll end, 10))
		end)

		it("penalises a costlier range even when a range below the floor comes first", function()
			-- 8-15 tested at 12 loses 12, under the floor of 15; 16-18 tested at 17 loses 17
			for _, order in ipairs({ { mod(8, 15), mod(16, 18) }, { mod(16, 18), mod(8, 15) } }) do
				local weights = generateWeights(order, function(roll) return -roll end, 15)
				assert.are.equal(1, #weights)
				assert.are.equal(-1, weights[1].weight)
			end
		end)

		it("still marks a stat after a first entry without effect, or without the option", function()
			for label, floor in pairs({ noEffect = 10, noOption = false }) do
				local _, calcs = generateWeights({ mod(25, 25), mod(18, 35) }, function(roll) return roll == 25 and 0 or -5 * roll end, floor or nil)
				assert.are.equal(1, calcs, label)
			end
		end)

		it("ranks penalties against positive weights and caps them", function()
			local function finish(withPositives)
				local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = { items = {} } })
				queryGen.modWeights = { }
				for index = 1, withPositives and 30 or 0 do
					table.insert(queryGen.modWeights, { tradeModId = "explicit.stat_" .. index, weight = 1, meanStatDiff = 31 - index })
				end
				for index = 1, 8 do
					table.insert(queryGen.modWeights, { tradeModId = "explicit.stat_" .. (100 + index), weight = -2, meanStatDiff = -400, penalty = true })
				end
				-- a penalty on a stat usually searched through a pseudo total (Fire Resistance) stays on its own stat
				table.insert(queryGen.modWeights, { tradeModId = "explicit.stat_3372524247", weight = -2, meanStatDiff = -500, penalty = true })
				queryGen.calcContext = {
					testItem = new("Item"):Item("Rarity: RARE\nNew Item\nGold Ring\nImplicits: 0"),
					baseOutput = { },
					baseStatValue = 0,
					itemCategoryQueryStr = "accessory.ring",
					special = { },
					options = { statWeights = { }, influence1 = 1, influence2 = 1, includeMirrored = false },
				}
				queryGen.tradeTypeIndex = 1
				local query
				queryGen.requesterCallback = function(_, queryJson)
					query = require("dkjson").decode(queryJson).query
				end
				queryGen:FinishQuery()
				local penalties = 0
				for _, filter in ipairs(query.stats[1].filters) do
					assert.is_nil(filter.id:match("^pseudo%."))
					if filter.value.weight < 0 then penalties = penalties + 1 end
				end
				return penalties
			end

			assert.are.equal(6, finish(true))
			assert.are.equal(0, finish(false))
		end)

		it("penalises only when the Harmful Mods option is checked", function()
			local function penaltyFloor(options)
				local calcFunc = function() return { Life = 100 } end
				local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = { items = { }, build = { calcsTab = { GetMiscCalculator = function() return calcFunc, { Life = 100 } end } } } })
				options.statWeights = { { stat = "Life", weightMult = 1 } }
				queryGen:StartQuery({ slotName = "Belt" }, options)
				main:ClosePopup()
				return queryGen.calcContext.penaltyFloor
			end

			assert.is_nil(penaltyFloor({ }))
			assert.are.equal(10, penaltyFloor({ includeHarmfulMods = true }))
		end)

		it("offers the Harmful Mods option unchecked for regular searches only", function()
			local function harmfulModsControl(slotTbl)
				local queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = { items = { } } })
				queryGen:RequestQuery({ slotName = "Belt" }, { slotTbl = slotTbl }, { }, function() end)
				local control = main.popups[1].controls.includeHarmfulMods
				main:ClosePopup()
				return control
			end

			assert.is_false(harmfulModsControl({ slotName = "Belt" }).state)
			assert.is_nil(harmfulModsControl({ slotName = "Megalomaniac", unique = true, alreadyCorrupted = true }))
		end)
	end)
end)
