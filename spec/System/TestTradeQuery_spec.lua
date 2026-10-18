local dkjson = require "dkjson"

describe("TradeQuery", function()
	local mock_tradeQuery
	local mock_queryGen

	before_each(function()
		mock_tradeQuery = new("TradeQuery"):TradeQuery({ itemsTab = {} })
		mock_queryGen = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = {} })
	end)
	describe("result dropdown tooltipFunc", function()
		-- Builds a TradeQuery with the strict minimum needed for
		-- PriceItemRowDisplay to construct row 1 without exploding. Only the
		-- two itemsTab subtables read by the slot lookup at the top of
		-- PriceItemRowDisplay need to be created here; everything else either
		-- lives behind a callback we never trigger, or is already initialized
		-- by the TradeQuery constructor.
		local function newTradeQuery(state)
			local tq = new("TradeQuery"):TradeQuery({ itemsTab = {} })
			tq.itemsTab.activeItemSet = {}
			tq.itemsTab.slots         = {}
			tq.slotTables[1] = { slotName = "Ring 1" }
			if state.resultTbl       then tq.resultTbl       = state.resultTbl       end
			if state.sortedResultTbl then tq.sortedResultTbl = state.sortedResultTbl end
			return tq
		end

		-- Builds row 1 of the trader UI and returns the dropdown that owns the
		-- tooltipFunc we want to exercise.
		local function buildRow1Dropdown(tq)
			tq:PriceItemRowDisplay(1, nil, 0, 20)
			return tq.controls.resultDropdown1
		end

		it("returns early when sortedResultTbl[row_idx] is missing", function()
			-- No sorted results at all -> first guard must short-circuit.
			local tq = newTradeQuery({})
			local dropdown = buildRow1Dropdown(tq)
			local tooltip = new("Tooltip"):Tooltip()

			assert.has_no.errors(function()
				dropdown.tooltipFunc(tooltip, "DROP", 1, nil)
			end)
			assert.are.equal(0, #tooltip.lines)
		end)

		it("returns early when the backing result entry has been cleared", function()
			-- The dropdown must be built against a valid result so that
			-- PriceItemRowDisplay's construction loop succeeds; we wipe
			-- resultTbl[1] only afterwards, to simulate a stale tooltip
			-- callback firing after the results were invalidated.
			local tq = newTradeQuery({
				resultTbl       = { [1] = { [1] = { item_string = "Rarity: RARE\nBehemoth Hold\nGold Ring", amount = 1, currency = "chaos" } } },
				sortedResultTbl = { [1] = { { index = 1 } } },
			})
			local dropdown = buildRow1Dropdown(tq)
			tq.resultTbl[1] = {}
			local tooltip = new("Tooltip"):Tooltip()

			assert.has_no.errors(function()
				dropdown.tooltipFunc(tooltip, "DROP", 1, nil)
			end)
			assert.are.equal(0, #tooltip.lines)
		end)
	end)
	describe("GetResultEvaluation", function()
		it("uses the first visible ring for a Pearl result without a selected slot", function()
			local tq = new("TradeQuery"):TradeQuery({ itemsTab = {} })
			tq.statSortSelectionList = {}
			tq.tradeQueryGenerator = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = {} })
			tq.itemsTab.slots = {
				["Ring 1"] = { slotName = "Ring 1", shown = function() return false end },
				["Ring 2"] = { slotName = "Ring 2", shown = function() return true end },
			}
			tq.slotTables[1] = { slotName = "Pearl of Tsoatha", unique = true }
			tq.resultTbl[1] = {
				[1] = { item_string = "Rarity: RARE\nBehemoth Hold\nGold Ring" },
			}
			local evaluatedSlot

			tq:GetResultEvaluation(1, 1, function(override)
				evaluatedSlot = override.repSlotName
				return {}
			end, {})

			assert.are.equal("Ring 2", evaluatedSlot)
			assert.are.equal("Ring 2", tq.slotTables[1].selectedSlotName)
		end)

		it("evaluates a socketed Megalomaniac by node combination", function()
			local slotTbl = {
				slotName = "Megalomaniac", unique = true, alreadyCorrupted = true, selectedJewelNodeId = 12345,
			}
			local tq = new("TradeQuery"):TradeQuery({ itemsTab = {} })
			tq.statSortSelectionList = {}
			tq.tradeQueryGenerator = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = {} })
			tq.itemsTab.build = {
				spec = {
					tree = {
						clusterNodeMap = {
							["Node One"] = { dn = "Node One" },
							["Node Two"] = { dn = "Node Two" },
							["Node Three"] = { dn = "Node Three" },
						}
					}
				}
			}
			tq.slotTables[1] = slotTbl
			tq.resultTbl[1] = {
				[1] = {
					item_string = table.concat({
						"1 Added Passive Skill is Node One",
						"1 Added Passive Skill is Node Two",
						"1 Added Passive Skill is Node Three",
					}, "\n")
				}
			}

			local evaluation = tq:GetResultEvaluation(1, 1, function() return {} end, {})

			assert.are.equal(4, #evaluation)
			for _, entry in ipairs(evaluation) do
				assert.is_table(entry.DNs)
				assert.is_true(#entry.DNs >= 2)
			end
		end)
	end)
	describe("Stat Gain vs Budget sort", function()
		-- Stat Value 1 means the current item: gain = Stat Value - 1.
		-- Results as { Stat Value, price in divines }.
		local upgradeResults = {
			{ 0.875, 0.0625 }, -- cheap downgrade
			{ 1.5, 64 },       -- best gain, most expensive
			{ 1.375, 16 },     -- near-best at a mid price
			{ 1.3125, 8 },     -- ties with result 3 when Max Price is 64
			{ 1.0625, 1 },     -- cheap small upgrade
		}
		local downgradeResults = {
			{ 0.875, 0.0625 }, -- smallest loss
			{ 0.75, 64 },      -- largest loss
			{ 0.8125, 64 },    -- expensive mid loss
		}

		local function newBudgetTradeQuery(results, query)
			local tq = new("TradeQuery"):TradeQuery({ itemsTab = {} })
			-- sort modes are defined with the Trader window controls
			tq.sortModes = { StatGainBudget = "budget" }
			tq.statSortSelectionList = { { stat = "FullDPS", weightMult = 1 } }
			tq.tradeQueryGenerator = new("TradeQueryGenerator"):TradeQueryGenerator({ itemsTab = {} })
			tq.itemsTab.build = { calcsTab = { GetMiscCalculator = function() return nil, { FullDPS = 100 } end } }
			tq.slotTables[1] = { slotName = "Ring 1" }
			tq.lastQueries[1] = query and dkjson.encode(query)
			tq.resultTbl[1] = {}
			for index, result in ipairs(results) do
				tq.resultTbl[1][index] = { currency = "divine", amount = result[2] }
			end
			tq.GetResultEvaluation = function(_, _, resultIndex)
				return { { weight = results[resultIndex][1] } }
			end
			local divsPerUnit = { divine = 1, chaos = 1 / 256 }
			tq.ConvertCurrencyToDivs = function(_, currency, amount)
				return divsPerUnit[currency] and amount * divsPerUnit[currency]
			end
			return tq
		end

		local function sortedIndices(tq)
			local sorted, errMsg = tq:SortFetchResults(1, tq.sortModes.StatGainBudget)
			assert.is_nil(errMsg)
			local indices = {}
			for _, entry in ipairs(sorted) do
				table.insert(indices, entry.index)
			end
			return indices
		end

		it("charges price against the Max Price the search used", function()
			-- 32768 Chaos Orb Equivalent = 128 divines
			local tq = newBudgetTradeQuery(upgradeResults, {
				query = { filters = { trade_filters = { filters = { price = { max = 32768 } } } } },
			})

			assert.are.same({ 3, 4, 2, 5, 1 }, sortedIndices(tq))
		end)

		it("uses the highest fetched price without a Max Price, cheaper first on ties", function()
			local tq = newBudgetTradeQuery(upgradeResults, { query = {} })

			assert.are.same({ 4, 3, 5, 2, 1 }, sortedIndices(tq))
		end)

		it("does not reward price when no result is an upgrade", function()
			local tq = newBudgetTradeQuery(downgradeResults, {
				query = { filters = { trade_filters = { filters = { price = { option = "divine", max = 64 } } } } },
			})

			assert.are.same({ 1, 3, 2 }, sortedIndices(tq))
		end)

		it("ranks Megalomaniac results by Stat Value, cheaper first on ties", function()
			local tq = newBudgetTradeQuery({ { 1.5, 64 }, { 1.375, 1 }, { 1.5, 32 } }, { query = {} })
			tq.slotTables[1] = { slotName = "Megalomaniac" }

			assert.are.same({ 3, 1, 2 }, sortedIndices(tq))
		end)

		it("reports missing conversion rates", function()
			local tq = newBudgetTradeQuery(upgradeResults, { query = {} })
			tq.ConvertCurrencyToDivs = function() end

			local sorted, errMsg = tq:SortFetchResults(1, tq.sortModes.StatGainBudget)

			assert.is_nil(sorted)
			assert.are.equal("MissingConversionRates", errMsg)
		end)
	end)
	describe("ReduceOutput", function()
		it("preserves lower-is-better values for weighted result comparison", function()
			local weights = {
				{ stat = "PhysicalTakenHit", weightMult = 1, transform = function(value) return -value end },
			}
			mock_tradeQuery.statSortSelectionList = weights

			local baseOutput = { PhysicalTakenHit = 100 }
			local betterOutput = mock_tradeQuery:ReduceOutput({ PhysicalTakenHit = 80 })
			local worseOutput = mock_tradeQuery:ReduceOutput({ PhysicalTakenHit = 120 })
			local betterWeight = mock_queryGen.WeightedRatioOutputs(baseOutput, betterOutput, weights)
			local worseWeight = mock_queryGen.WeightedRatioOutputs(baseOutput, worseOutput, weights)

			assert.are.equal(80, betterOutput.PhysicalTakenHit)
			assert.is_true(betterWeight > worseWeight)
		end)

		it("uses selected minion stats for weighted result comparison", function()
			mock_tradeQuery.statSortSelectionList = { { stat = "AverageDamage" } }

			local result = mock_tradeQuery:ReduceOutput({
				AverageDamage = 10,
				Life = 100,
				Minion = {
					AverageDamage = 250,
					Life = 200,
				},
			})

			assert.are.equals(260, result.AverageDamage)
			assert.is_nil(result.Life)
		end)

		it("keeps fallback DPS stats when FullDPS is selected but not present", function()
			mock_tradeQuery.statSortSelectionList = { { stat = "FullDPS", weightMult = 1 } }

			local baseOutput = {
				CombinedDPS = 100,
				TotalDPS = 100,
				TotalDotDPS = 0,
			}
			local reducedOutput = mock_tradeQuery:ReduceOutput({
				CombinedDPS = 120,
				TotalDPS = 120,
				TotalDotDPS = 0,
			})

			local result = mock_queryGen.WeightedRatioOutputs(baseOutput, reducedOutput,
				mock_tradeQuery.statSortSelectionList)

			assert.are.equals(1.2, result)
		end)
	end)
end)
