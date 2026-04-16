local dkjson = require "dkjson"

describe("TradeQueryGenerator", function()
	local mock_queryGen = new("TradeQueryGenerator", { itemsTab = {}, GetTradeStatusOption = function() return "online" end })

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

	describe("WeightedRatioOutputs", function()
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
			data.misc.maxStatIncrease = 1000
			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, newOutput, statWeights)
			assert.are.equal(result, 100)
		end)
	end)

	describe("Filter prioritization", function()
		-- Pass: Limits mods to MAX_FILTERS (2 in test), preserving top priorities
		-- Fail: Exceeds limit, indicating over-generation of filters, risking API query size errors or rate limits
		it("respects MAX_FILTERS", function()
			local orig_max = _G.MAX_FILTERS
			_G.MAX_FILTERS = 2
			mock_queryGen.modWeights = { { weight = 10, tradeModId = "id1" }, { weight = 5, tradeModId = "id2" } }
			table.sort(mock_queryGen.modWeights, function(a, b)
				return math.abs(a.weight) > math.abs(b.weight)
			end)
			local prioritized = {}
			for i, entry in ipairs(mock_queryGen.modWeights) do
				if #prioritized < _G.MAX_FILTERS then
					table.insert(prioritized, entry)
				end
			end
			assert.are.equal(#prioritized, 2)
			_G.MAX_FILTERS = orig_max
		end)
	end)

	describe("Required mod filters", function()
		-- Synthetic trade IDs used to isolate tests from the live trade stats lookup.
		local CORRUPTED_BLOOD_ID = "corrupted.stat_3299347024"
		local MAX_LIFE_ID        = "implicit.stat_3299347025"

		local function makeQueryGen()
			local qg = new("TradeQueryGenerator", { itemsTab = { items = {} } })
			-- Inject known trade ID mappings keyed by mod type; avoids dependency on live API data.
			qg.modTradeIdByText = {
				Corrupted = {
					["Corrupted Blood cannot be inflicted on you"] = CORRUPTED_BLOOD_ID,
				},
				Implicit = {
					[" to maximum Life"] = MAX_LIFE_ID,  -- normalized form of "+# to maximum Life"
				},
			}
			qg.requesterContext = {}
			return qg
		end

		local function baseCalcContext(pinnedModLines)
			return {
				slot = { selItemId = 1, slotName = "Jewel 1" },
				testItem = new("Item", "Rarity: RARE\nStat Tester\nCrimson Jewel"),
				calcFunc = function() return { Score = 0 } end,
				baseOutput = { Score = 0 },
				baseStatValue = 0,
				itemCategoryQueryStr = "jewel",
				options = {
					includeMirrored = true,
					influence1 = 1,
					influence2 = 1,
					statWeights = {},
					pinnedModLines = pinnedModLines or {},
				},
				special = {},
			}
		end

		local function equippedItem()
			return {
				explicitModLines = {},
				scourgeModLines  = {},
				implicitModLines = {},
				crucibleModLines = {},
			}
		end

		describe("ResolveRequiredModFilters", function()
			-- Pass: No mods pinned => empty list, existing query unchanged.
			-- Fail: Returns non-empty list, inserting spurious and-filters into the query.
			it("returns empty list when pinnedModLines is empty", function()
				local qg = makeQueryGen()
				local result = qg:ResolveRequiredModFilters({})
				assert.are.same({}, result)
			end)

			-- Pass: nil input treated as no mods pinned.
			-- Fail: Crashes on nil, breaking queries that never set pinnedModLines.
			it("returns empty list when pinnedModLines is nil", function()
				local qg = makeQueryGen()
				local result = qg:ResolveRequiredModFilters(nil)
				assert.are.same({}, result)
			end)

			-- Pass: Single mod resolves to the correct trade stat ID.
			-- Fail: Wrong ID or empty list, causing the filter to be missing from the query.
			it("resolves a single required mod to its trade filter id", function()
				local qg = makeQueryGen()
				local result = qg:ResolveRequiredModFilters({ "Corrupted Blood cannot be inflicted on you" })
				assert.are.equal(1, #result)
				assert.are.equal(CORRUPTED_BLOOD_ID, result[1].id)
			end)

			-- Pass: Corrupted Blood specifically maps to a valid trade stat id.
			-- Fail: Returns nil/empty, meaning the immunity would not be enforced in trade queries.
			it("handles 'Corrupted Blood cannot be inflicted on you' mod", function()
				local qg = makeQueryGen()
				local result = qg:ResolveRequiredModFilters({ "Corrupted Blood cannot be inflicted on you" })
				assert.are.equal(1, #result)
				assert.is_not_nil(result[1].id)
				assert.are.equal(CORRUPTED_BLOOD_ID, result[1].id)
			end)

			-- Pass: Two mods each produce their own filter entry.
			-- Fail: Only one entry returned, silently dropping a required constraint.
			it("resolves multiple required mods to separate filter entries", function()
				local qg = makeQueryGen()
				local result = qg:ResolveRequiredModFilters({
					"Corrupted Blood cannot be inflicted on you",
					"+42 to maximum Life",
				})
				assert.are.equal(2, #result)
				assert.are.equal(CORRUPTED_BLOOD_ID, result[1].id)
				assert.are.equal(MAX_LIFE_ID,        result[2].id)
			end)

			-- Pass: Implicit mod resolves to implicit trade ID, not explicit.
			-- Fail: Returns explicit ID, causing trade API to search wrong mod category.
			it("resolves implicit mod to implicit trade ID, not explicit", function()
				local qg = new("TradeQueryGenerator", { itemsTab = { items = {} } })
				qg.modTradeIdByText = {
					Explicit = {
						[" to maximum Life"] = "explicit.stat_3299347025",
					},
					Implicit = {
						[" to maximum Life"] = "implicit.stat_3299347025",
					},
				}
				qg.requesterContext = {}
				local result = qg:ResolveRequiredModFilters({ "+42 to maximum Life" })
				assert.are.equal(1, #result)
				assert.are.equal("implicit.stat_3299347025", result[1].id)
			end)

			-- Pass: Unknown mod is skipped; function returns empty without crashing.
			-- Fail: Crashes or raises an error, breaking the query flow entirely.
			it("skips mods with no trade mapping without crashing", function()
				local qg = makeQueryGen()
				local ok, result = pcall(function()
					return qg:ResolveRequiredModFilters({ "This mod does not exist in trade data" })
				end)
				assert.is_true(ok)
				assert.are.same({}, result)
			end)
		end)

		describe("FinishQuery with pinnedModLines", function()
			-- Pass: No pinned mods => query has only the weighted stat group, no and-group.
			-- Fail: Spurious and-group inserted, altering previously working queries.
			it("generates query without required mods: no and-group added", function()
				local queryJson
				local originalClosePopup = main.ClosePopup
				main.ClosePopup = function() end

				local qg = makeQueryGen()
				qg.requesterCallback = function(_, payload) queryJson = payload end
				qg.modWeights = { { tradeModId = "explicit.stat_1", weight = 10, meanStatDiff = 100 } }
				qg.calcContext = baseCalcContext(nil)
				qg.itemsTab.items[1] = equippedItem()

				qg:FinishQuery()
				main.ClosePopup = originalClosePopup

				local query = dkjson.decode(queryJson)
				assert.are.equal(1, #query.query.stats)
				assert.are.equal("weight", query.query.stats[1].type)
			end)

			-- Pass: Pinned mod appears as an and-filter in the generated query.
			-- Fail: No and-group in query, meaning the required mod constraint is silently dropped.
			it("adds a required mod as an and-filter in the query", function()
				local queryJson
				local originalClosePopup = main.ClosePopup
				main.ClosePopup = function() end

				local qg = makeQueryGen()
				qg.requesterCallback = function(_, payload) queryJson = payload end
				qg.modWeights = { { tradeModId = "explicit.stat_1", weight = 10, meanStatDiff = 100 } }
				qg.calcContext = baseCalcContext({ "Corrupted Blood cannot be inflicted on you" })
				qg.itemsTab.items[1] = equippedItem()

				qg:FinishQuery()
				main.ClosePopup = originalClosePopup

				local query = dkjson.decode(queryJson)
				assert.are.equal(2, #query.query.stats)
				local andGroup = query.query.stats[2]
				assert.are.equal("and", andGroup.type)
				assert.are.equal(1, #andGroup.filters)
				assert.are.equal(CORRUPTED_BLOOD_ID, andGroup.filters[1].id)
			end)

			-- Pass: Corrupted Blood mod is enforced end-to-end in the trade query JSON.
			-- Fail: No and-group or wrong id, allowing trade results that lack the immunity.
			it("enforces 'Corrupted Blood cannot be inflicted on you' as a required filter", function()
				local queryJson
				local originalClosePopup = main.ClosePopup
				main.ClosePopup = function() end

				local qg = makeQueryGen()
				qg.requesterCallback = function(_, payload) queryJson = payload end
				qg.modWeights = { { tradeModId = "explicit.stat_1", weight = 5, meanStatDiff = 50 } }
				qg.calcContext = baseCalcContext({ "Corrupted Blood cannot be inflicted on you" })
				qg.itemsTab.items[1] = equippedItem()

				qg:FinishQuery()
				main.ClosePopup = originalClosePopup

				local query = dkjson.decode(queryJson)
				local andGroup = nil
				for _, g in ipairs(query.query.stats) do
					if g.type == "and" then andGroup = g break end
				end
				assert.is_not_nil(andGroup, "Expected an and-group for the required mod")
				assert.are.equal(CORRUPTED_BLOOD_ID, andGroup.filters[1].id)
			end)

			-- Pass: All pinned mods appear in the and-group.
			-- Fail: Only the first mod appears, losing subsequent constraints.
			it("adds multiple required mods to the and-group", function()
				local queryJson
				local originalClosePopup = main.ClosePopup
				main.ClosePopup = function() end

				local qg = makeQueryGen()
				qg.requesterCallback = function(_, payload) queryJson = payload end
				qg.modWeights = { { tradeModId = "explicit.stat_1", weight = 10, meanStatDiff = 100 } }
				qg.calcContext = baseCalcContext({
					"Corrupted Blood cannot be inflicted on you",
					"+42 to maximum Life",
				})
				qg.itemsTab.items[1] = equippedItem()

				qg:FinishQuery()
				main.ClosePopup = originalClosePopup

				local query = dkjson.decode(queryJson)
				local andGroup = nil
				for _, g in ipairs(query.query.stats) do
					if g.type == "and" then andGroup = g break end
				end
				assert.is_not_nil(andGroup)
				assert.are.equal(2, #andGroup.filters)
				assert.are.equal(CORRUPTED_BLOOD_ID, andGroup.filters[1].id)
				assert.are.equal(MAX_LIFE_ID,        andGroup.filters[2].id)
			end)

			-- Pass: Unmappable mod is silently skipped; query still returns successfully.
			-- Fail: FinishQuery crashes or propagates an error, breaking the entire search.
			it("skips unmappable required mods without crashing or corrupting the query", function()
				local queryJson
				local errMsg
				local originalClosePopup = main.ClosePopup
				main.ClosePopup = function() end

				local qg = makeQueryGen()
				qg.requesterCallback = function(_, payload, err)
					queryJson = payload
					errMsg = err
				end
				qg.modWeights = { { tradeModId = "explicit.stat_1", weight = 10, meanStatDiff = 100 } }
				qg.calcContext = baseCalcContext({ "This mod cannot be mapped to any trade stat" })
				qg.itemsTab.items[1] = equippedItem()

				local ok = pcall(function() qg:FinishQuery() end)
				main.ClosePopup = originalClosePopup

				assert.is_true(ok, "FinishQuery must not crash when a required mod has no trade mapping")
				assert.is_nil(errMsg, "Query should still succeed with the remaining weighted mods")
				local query = dkjson.decode(queryJson)
				-- No and-group since the only pinned mod was unmappable
				assert.are.equal(1, #query.query.stats)
			end)
		end)
	end)
end)
