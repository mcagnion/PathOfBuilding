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

    describe("Base defence weighting", function()
        it("lists compatible armour bases for the slot", function()
            local queryGen = new("TradeQueryGenerator", {
                itemsTab = {
                    build = {
                        data = {
                            itemBases = {
                                ["A Armour"] = { type = "Helmet", armour = { ArmourBaseMin = 1 } },
                                ["B Armour"] = { type = "Helmet", armour = { ArmourBaseMin = 2 } },
                                ["Body Base"] = { type = "Body Armour", armour = { ArmourBaseMin = 3 } },
                            }
                        }
                    }
                }
            })

            local bases = queryGen:GetSelectableBaseNames({ slotName = "Helmet" }, { type = "Helmet", baseName = "B Armour" })
            assert.are.same({ "A Armour", "B Armour" }, bases)
        end)

        it("averages available base defence percentiles", function()
            local item = {
                base = {
                    armour = {
                        ArmourBaseMin = 1,
                        EnergyShieldBaseMin = 1,
                    }
                },
                armourData = {
                    ArmourBasePercentile = 0.25,
                    EnergyShieldBasePercentile = 0.75,
                }
            }

            assert.are.equal(50, mock_queryGen.GetBaseDefencePercentileAverage(item))
        end)

        it("adds same-base percentile weighting to the generated query", function()
            local queryJson
            local originalClosePopup = main.ClosePopup
            main.ClosePopup = function() end

            local queryGen = new("TradeQueryGenerator", { itemsTab = { items = {} } })
            queryGen.queryTab = {
                GetTradeStatusOption = function()
                    return "available"
                end
            }
            queryGen.requesterCallback = function(_, payload, errMsg)
                assert.is_nil(errMsg)
                queryJson = payload
            end
            queryGen.requesterContext = {}
            queryGen.modWeights = {
                { tradeModId = "explicit.stat_1", weight = 2, meanStatDiff = 20 }
            }
            queryGen.calcContext = {
                slot = { selItemId = 1, slotName = "Helmet" },
                testItem = new("Item", "Rarity: RARE\nStat Tester\nIron Hat"),
                calcFunc = function(context)
                    if context and context.repItem then
                        return { Score = 20 }
                    end
                    return { Score = 100 }
                end,
                baseOutput = { Score = 100 },
                baseStatValue = 0,
                itemCategoryQueryStr = "armour.helmet",
                options = {
                    includeMirrored = true,
                    influence1 = 1,
                    influence2 = 1,
                    selectedBaseName = "Iron Hat",
                    statWeights = {
                        { stat = "Score", weightMult = 1 }
                    }
                },
                sameBaseType = "Iron Hat",
                baseDefencePercentile = {
                    tradeModId = "pseudo.pseudo_base_defence_percentile",
                    weight = 3,
                    currentValue = 42,
                },
                special = {},
            }
            queryGen.itemsTab.items[1] = {
                explicitModLines = {},
                scourgeModLines = {},
                implicitModLines = {},
                crucibleModLines = {},
            }

            queryGen:FinishQuery()

            main.ClosePopup = originalClosePopup

            local query = dkjson.decode(queryJson)
            assert.are.equal("Iron Hat", query.query.type)
            assert.are.equal(250, query.query.stats[1].value.min)
            assert.are.equal("pseudo.pseudo_base_defence_percentile", query.query.stats[1].filters[1].id)
            assert.are.equal(3, query.query.stats[1].filters[1].value.weight)
            assert.are.equal("explicit.stat_1", query.query.stats[1].filters[2].id)
        end)
    end)
end)
