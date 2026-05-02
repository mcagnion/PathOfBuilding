describe("TradeQuery", function()
	describe("UpdateRealms", function()
		it("falls back to public realms when private league loading fails", function()
			local orig_poesessid = main.POESESSID
			main.POESESSID = "1234567890ABCDEF1234567890ABCDEF"

			local tq = new("TradeQuery", { itemsTab = {} })
			tq.controls.pbNotice = { label = "" }
			tq.controls.realm = {
				list = {},
				selIndex = 1,
				SetList = function(self, list)
					self.list = list
				end,
				SetSel = function(self, index)
					self.selIndex = index
				end,
			}
			tq.tradeQueryRequests.FetchRealmsAndLeaguesHTML = function(self, callback)
				callback(nil, "JSON object not found on the page.")
			end

			tq:UpdateRealms()

			main.POESESSID = orig_poesessid
			assert.are.equal("pc", tq.realmIds["PC"])
			assert.are.equal("sony", tq.realmIds["PS4"])
			assert.are.equal("xbox", tq.realmIds["Xbox"])
			assert.are.equal("PC", tq.controls.realm.list[1])
			assert.is_not_nil(tq.controls.pbNotice.label:find("Private league list unavailable", 1, true))
		end)

		it("clears the public league fallback notice after leagues load", function()
			local tq = new("TradeQuery", { itemsTab = {} })
			tq.controls.pbNotice = { label = colorCodes.WARNING .. "Private league list unavailable; using public leagues." }

			tq:ClearPublicLeagueFallbackNotice()

			assert.are.equal("", tq.controls.pbNotice.label)
		end)

		it("shows a specific notice when the session id expired", function()
			local orig_poesessid = main.POESESSID
			main.POESESSID = "1234567890ABCDEF1234567890ABCDEF"

			local tq = new("TradeQuery", { itemsTab = {} })
			tq.controls.pbNotice = { label = "" }
			tq.controls.realm = {
				list = {},
				selIndex = 1,
				SetList = function(self, list)
					self.list = list
				end,
				SetSel = function(self, index)
					self.selIndex = index
				end,
			}
			tq.tradeQueryRequests.FetchRealmsAndLeaguesHTML = function(self, callback)
				callback(nil, self:GetInvalidPOESESSIDMessage())
			end

			tq:UpdateRealms()

			main.POESESSID = orig_poesessid
			assert.is_not_nil(tq.controls.pbNotice.label:find("POESESSID expired or invalid", 1, true))
			assert.is_not_nil(tq.controls.pbNotice.label:find("using public leagues", 1, true))
		end)
	end)

	describe("result dropdown tooltipFunc", function()
		-- Builds a TradeQuery with the strict minimum needed for
		-- PriceItemRowDisplay to construct row 1 without exploding. Only the
		-- two itemsTab subtables read by the slot lookup at the top of
		-- PriceItemRowDisplay need to be created here; everything else either
		-- lives behind a callback we never trigger, or is already initialized
		-- by the TradeQuery constructor.
		local function newTradeQuery(state)
			local tq = new("TradeQuery", { itemsTab = {} })
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
			local tooltip = new("Tooltip")

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
			local tooltip = new("Tooltip")

			assert.has_no.errors(function()
				dropdown.tooltipFunc(tooltip, "DROP", 1, nil)
			end)
			assert.are.equal(0, #tooltip.lines)
		end)
	end)
end)
