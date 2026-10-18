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

	describe("results of a running search", function()
		-- Row 1 priced from a trade URL; each listing's Stat Value comes from statValues by id
		local function newPricedRow(statValues)
			local tq = new("TradeQuery"):TradeQuery({ itemsTab = {} })
			tq.itemsTab.activeItemSet = {}
			tq.itemsTab.slots = {}
			tq.itemsTab.build = { calcsTab = { GetMiscCalculator = function() end } }
			tq.slotTables[1] = { slotName = "Ring 1" }
			tq.controls.pbNotice = {}
			tq.controls.fullPrice = {}
			tq.sortModes = { StatValue = "(Highest) Stat Value" }
			tq.itemSortSelectionList = { tq.sortModes.StatValue }
			tq.GetResultEvaluation = function(self, rowIdx, resultIndex)
				return { { weight = statValues[self.resultTbl[rowIdx][resultIndex].id] } }
			end
			local searches = { }
			tq.tradeQueryRequests = {
				SearchWithURL = function(_, url, callback, params)
					table.insert(searches, { callback = callback, params = params })
				end,
			}
			tq:PriceItemRowDisplay(1, nil, 0, 20)
			tq.controls.uri1.buf = "https://www.pathofexile.com/trade/search/Standard/abc"
			return tq, searches
		end
		local function listings(...)
			local items = { }
			for _, id in ipairs({ ... }) do
				table.insert(items, { id = id, item_string = "Rarity: RARE\n" .. id .. "\nGold Ring", amount = 1, currency = "chaos" })
			end
			return items
		end
		local function listedIds(tq)
			local ids = { }
			for _, sorted in ipairs(tq.sortedResultTbl[1]) do
				table.insert(ids, tq.resultTbl[1][sorted.index].id)
			end
			return ids
		end
		local function selectedId(tq)
			return tq.resultTbl[1][tq.itemIndexTbl[1]].id
		end

		it("ranks each fetched block with the earlier ones", function()
			local tq, searches = newPricedRow({ a = 1, b = 3, c = 2, d = 5 })
			tq.controls.priceButton1.onClick()
			local block1, block2 = listings("a", "b"), listings("c", "d")

			searches[1].params.onFetchedItems(block1, "query")
			assert.are.same({ "b", "a" }, listedIds(tq))
			assert.are.equal("b", selectedId(tq))
			searches[1].params.onFetchedItems(block2, "query")
			assert.are.same({ "d", "b", "c", "a" }, listedIds(tq))
			assert.are.equal("d", selectedId(tq))
			assert.are.equal("Searching...", tq.controls.priceButton1.label)

			searches[1].callback({ block1[1], block1[2], block2[1], block2[2] }, nil, "query")
			assert.are.same({ "d", "b", "c", "a" }, listedIds(tq))
			assert.are.equal("Price Item", tq.controls.priceButton1.label)
		end)

		it("waits for the open list to close and keeps the picked result", function()
			local tq, searches = newPricedRow({ a = 1, b = 3, d = 5 })
			tq.controls.priceButton1.onClick()
			searches[1].params.onFetchedItems(listings("a", "b"), "query")
			tq.controls.resultDropdown1:SetSel(2)
			assert.are.equal("a", selectedId(tq))

			tq.controls.resultDropdown1.dropped = true
			searches[1].params.onFetchedItems(listings("d"), "query")
			assert.are.same({ "b", "a" }, listedIds(tq))

			tq.controls.resultDropdown1.dropped = false
			tq:RefreshFetchedResults(1)
			assert.are.same({ "d", "b", "a" }, listedIds(tq))
			assert.are.equal("a", selectedId(tq))
			assert.are.equal(3, tq.controls.resultDropdown1.selIndex)
		end)

		it("forgets the picked result once a new sort selects the best one", function()
			local tq, searches = newPricedRow({ a = 1, b = 3, d = 5 })
			tq.controls.priceButton1.onClick()
			searches[1].params.onFetchedItems(listings("a", "b"), "query")
			tq.controls.resultDropdown1:SetSel(2)
			-- what a sort mode or stat weight change does
			tq:UpdateControlsWithItems(1)
			searches[1].params.onFetchedItems(listings("d"), "query")
			assert.are.equal("d", selectedId(tq))
		end)

		it("replaces the previous results and ignores a replaced search", function()
			local tq, searches = newPricedRow({ a = 1, b = 3, c = 2 })
			tq.controls.priceButton1.onClick()
			searches[1].params.onFetchedItems(listings("a"), "query")
			tq.controls.priceButton1.onClick()

			searches[2].params.onFetchedItems(listings("b"), "query")
			assert.are.same({ "b" }, listedIds(tq))
			searches[1].params.onFetchedItems(listings("c"), "query")
			searches[1].callback(listings("a", "c"), nil, "query")
			assert.are.same({ "b" }, listedIds(tq))
			assert.are.equal("Searching...", tq.controls.priceButton1.label)
		end)
	end)
end)
