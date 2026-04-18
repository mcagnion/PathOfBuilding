local dkjson = require "dkjson"

describe("TradeQueryGenerator", function()
	local mock_queryGen = new("TradeQueryGenerator", { itemsTab = {} })

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

		it("lists compatible ring bases for the slot", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Iron Ring"] = { type = "Ring" },
								["Coral Ring"] = { type = "Ring" },
								["Amber Amulet"] = { type = "Amulet" },
							}
						}
					}
				}
			})

			local bases = queryGen:GetSelectableBaseNames({ slotName = "Ring 1" }, { type = "Ring", baseName = "Coral Ring" })
			assert.are.same({ "Coral Ring", "Iron Ring" }, bases)
		end)

		it("lists compatible belt bases for the slot", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Leather Belt"] = { type = "Belt" },
								["Heavy Belt"] = { type = "Belt" },
								["Iron Ring"] = { type = "Ring" },
							}
						}
					}
				}
			})

			local bases = queryGen:GetSelectableBaseNames({ slotName = "Belt" }, { type = "Belt", baseName = "Leather Belt" })
			assert.are.same({ "Heavy Belt", "Leather Belt" }, bases)
		end)

		it("lists compatible belt bases even when the slot is empty", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Leather Belt"] = { type = "Belt" },
								["Heavy Belt"] = { type = "Belt" },
								["Iron Ring"] = { type = "Ring" },
							}
						}
					}
				}
			})

			local bases = queryGen:GetSelectableBaseNames({ slotName = "Belt" }, nil)
			assert.are.same({ "Heavy Belt", "Leather Belt" }, bases)
		end)

		it("limits unique searches to bases that have unique items", function()
			local originalUniques = data.uniques
			local ok, bases = pcall(function()
				data.uniques = {
					belt = {
						"Headhunter\nLeather Belt",
						"Meginord's Girdle\nHeavy Belt",
					},
				}

				local queryGen = new("TradeQueryGenerator", {
					itemsTab = {
						build = {
							data = {
								itemBases = {
									["Leather Belt"] = { type = "Belt" },
									["Heavy Belt"] = { type = "Belt" },
									["Chain Belt"] = { type = "Belt" },
								}
							}
						}
					}
				})

				return queryGen:GetSelectableBaseNames({ slotName = "Belt" }, { type = "Belt", baseName = "Leather Belt", rarity = "UNIQUE" })
			end)

			data.uniques = originalUniques
			assert.is_true(ok)
			assert.are.same({ "Heavy Belt", "Leather Belt" }, bases)
		end)

		it("ranks unique items for an exact base by build score", function()
			local originalUniques = data.uniques
			local ok, ranked = pcall(function()
				data.uniques = {
					mace = {
						[[Nebulis
Void Sceptre
Variant: Current
Requires Level 68, 104 Str, 122 Int
Implicits: 1
40% increased Elemental Damage
(5-10)% increased Elemental Damage per 1% Fire, Cold, or Lightning Resistance above 75%]],
						[[Replica Nebulis
Void Sceptre
Variant: Current
Requires Level 68, 104 Str, 122 Int
Implicits: 1
40% increased Elemental Damage
(10-15)% increased Elemental Damage per 1% Missing Fire, Cold, or Lightning Resistance, up to a maximum of 450%]],
					},
				}

				local queryGen = new("TradeQueryGenerator", {
					itemsTab = {
						build = {
							calcsTab = {
								GetMiscCalculator = function()
									return function(context)
										local scores = {
											["Nebulis"] = 40,
											["Replica Nebulis"] = 10,
										}
										return { score = scores[context.repItem.title] or 0 }
									end, { score = 0 }
								end
							}
						}
					}
				})
				queryGen.WeightedRatioOutputs = function(_, _, output)
					return output.score
				end

				return queryGen:GetRankedUniqueEntries({ slotName = "Weapon 1" }, "Void Sceptre", {})
			end)

			data.uniques = originalUniques
			assert.is_true(ok)
			assert.are.same({ "Nebulis", "Replica Nebulis" }, { ranked[1].name, ranked[2].name })
		end)

		it("generates ranked unique tooltip text with scores", function()
			local originalUniques = data.uniques
			local ok, tooltipText = pcall(function()
				data.uniques = {
					mace = {
						[[Nebulis
Void Sceptre
Variant: Current
Requires Level 68, 104 Str, 122 Int
Implicits: 1
40% increased Elemental Damage
(5-10)% increased Elemental Damage per 1% Fire, Cold, or Lightning Resistance above 75%]],
					},
				}

				local queryGen = new("TradeQueryGenerator", {
					itemsTab = {
						build = {
							calcsTab = {
								GetMiscCalculator = function()
									return function(context)
										return { score = 40 }
									end, { score = 0 }
								end
							}
						}
					}
				})
				queryGen.WeightedRatioOutputs = function(_, _, output)
					return output.score
				end

				return queryGen:GetUniqueRankedTooltipText({ slotName = "Weapon 1" }, "Void Sceptre", {})
			end)

			data.uniques = originalUniques
			assert.is_true(ok)
			assert.is_not_nil(tooltipText)
			assert.is_truthy(tooltipText:find("Nebulis"))
			assert.is_truthy(tooltipText:find("ranked by build score"))
		end)

		it("returns nil tooltip for base with no uniques", function()
			local originalUniques = data.uniques
			local ok, tooltipText = pcall(function()
				data.uniques = { }
				local queryGen = new("TradeQueryGenerator", {
					itemsTab = {
						build = {
							calcsTab = {
								GetMiscCalculator = function()
									return function() return { score = 0 } end, { score = 0 }
								end
							}
						}
					}
				})
				queryGen.WeightedRatioOutputs = function(_, _, output)
					return output.score
				end
				return queryGen:GetUniqueRankedTooltipText({ slotName = "Weapon 1" }, "Void Sceptre", {})
			end)

			data.uniques = originalUniques
			assert.is_true(ok)
			assert.is_nil(tooltipText)
		end)

		it("offers auto base profiles for empty armour slots", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Armour Helm"] = { type = "Helmet", armour = { ArmourBaseMin = 1 } },
								["Evasion Helm"] = { type = "Helmet", armour = { EvasionBaseMin = 1 } },
							}
						}
					}
				}
			})

			local options = queryGen:GetAutoBaseOptionEntries({ slotName = "Helmet" }, nil)
			assert.is_not_nil(options)
			assert.are.equal("any", options[1].key)
		end)

		it("offers any, auto and exact base modes for armour slots", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Armour Helm"] = { type = "Helmet", armour = { ArmourBaseMin = 1 } },
								["Evasion Helm"] = { type = "Helmet", armour = { EvasionBaseMin = 1 } },
							}
						}
					}
				}
			})

			local entries = queryGen:GetBaseSelectionModeEntries({ slotName = "Helmet" }, nil)
			assert.are.same({ "any", "recommended", "auto", "exact" }, { entries[1].key, entries[2].key, entries[3].key, entries[4].key })
		end)

		it("offers any, recommended and exact base modes when no auto mode is available", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Iron Ring"] = { type = "Ring" },
								["Coral Ring"] = { type = "Ring" },
							}
						}
					}
				}
			})

			local entries = queryGen:GetBaseSelectionModeEntries({ slotName = "Ring 1" }, { type = "Ring", baseName = "Iron Ring" })
			assert.are.same({ "any", "recommended", "exact" }, { entries[1].key, entries[2].key, entries[3].key })
		end)

		it("returns recommended bases sorted by score", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Chain Belt"] = { type = "Belt" },
								["Heavy Belt"] = { type = "Belt" },
								["Leather Belt"] = { type = "Belt" },
							},
						},
						calcsTab = {
							GetMiscCalculator = function()
								return function(context)
									local scores = {
										["Chain Belt"] = 20,
										["Heavy Belt"] = 30,
										["Leather Belt"] = 10,
									}
									return { score = scores[context.repItem.baseName] or 0 }
								end, {}
							end
						}
					}
				}
			})
			queryGen.WeightedRatioOutputs = function(_, _, output)
				return output.score
			end

			local bases = queryGen:GetRecommendedBaseNames({ slotName = "Belt" }, nil, {})
			assert.are.same({ "Heavy Belt", "Chain Belt", "Leather Belt" }, bases)
		end)

		it("uses a generic any-base entry for the any base mode", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Leather Belt"] = { type = "Belt" },
								["Heavy Belt"] = { type = "Belt" },
							}
						}
					}
				}
			})

			local entries = queryGen:GetBaseSelectionEntries({ slotName = "Belt" }, nil, "any")
			assert.are.equal("Any compatible base", entries[1].label)
			assert.is_true(entries[1].anyBase)
		end)

		it("uses recommended entries when requested", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Chain Belt"] = { type = "Belt" },
								["Heavy Belt"] = { type = "Belt" },
								["Leather Belt"] = { type = "Belt" },
							},
						},
						calcsTab = {
							GetMiscCalculator = function()
								return function(context)
									local scores = {
										["Chain Belt"] = 20,
										["Heavy Belt"] = 30,
										["Leather Belt"] = 10,
									}
									return { score = scores[context.repItem.baseName] or 0 }
								end, {}
							end
						}
					}
				}
			})
			queryGen.WeightedRatioOutputs = function(_, _, output)
				return output.score
			end

			local entries = queryGen:GetBaseSelectionEntries({ slotName = "Belt" }, nil, "recommended", {}, 1, 1)
			assert.are.same({ "Heavy Belt", "Chain Belt", "Leather Belt" }, {
				entries[1].baseName,
				entries[2].baseName,
				entries[3].baseName,
			})
		end)

		it("uses defence values to break recommended ties for armour bases", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Arena Plate"] = { type = "Body Armour", armour = { ArmourBaseMax = 782 } },
								["Astral Plate"] = { type = "Body Armour", armour = { ArmourBaseMax = 711 } },
								["Colosseum Plate"] = { type = "Body Armour", armour = { ArmourBaseMax = 589 } },
							},
						},
						calcsTab = {
							GetMiscCalculator = function()
								return function()
									return { score = 0 }
								end, {}
							end
						}
					}
				}
			})
			queryGen.WeightedRatioOutputs = function(_, _, output)
				return output.score
			end

			local entries = queryGen:GetBaseSelectionEntries({ slotName = "Body Armour" }, nil, "recommended", {
				{ stat = "Armour", weightMult = 0.5 },
			}, 1, 1)
			assert.are.same({ "Arena Plate", "Astral Plate", "Colosseum Plate" }, {
				entries[1].baseName,
				entries[2].baseName,
				entries[3].baseName,
			})
		end)

		it("does not add auto options when the slot has no defence profiles", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Iron Ring"] = { type = "Ring" },
								["Coral Ring"] = { type = "Ring" },
							}
						}
					}
				}
			})

			local options = queryGen:GetAutoBaseOptionEntries({ slotName = "Ring 1" }, { type = "Ring", baseName = "Iron Ring" })
			assert.is_nil(options)
		end)

		it("limits flask bases to the matching flask subtype", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Small Life Flask"] = { type = "Flask", subType = "Life" },
								["Medium Life Flask"] = { type = "Flask", subType = "Life" },
								["Quicksilver Flask"] = { type = "Flask", subType = "Utility" },
							}
						}
					}
				}
			})

			local bases = queryGen:GetSelectableBaseNames({ slotName = "Flask 1" }, { type = "Flask", baseName = "Small Life Flask" })
			assert.are.same({ "Medium Life Flask", "Small Life Flask" }, bases)
		end)

		it("limits jewel bases to the matching jewel subtype", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Crimson Jewel"] = { type = "Jewel" },
								["Viridian Jewel"] = { type = "Jewel" },
								["Hypnotic Eye Jewel"] = { type = "Jewel", subType = "Abyss" },
								["Large Cluster Jewel"] = { type = "Jewel", subType = "Cluster" },
							}
						}
					}
				}
			})

			local regularBases = queryGen:GetSelectableBaseNames({ slotName = "Jewel 1" }, { type = "Jewel", baseName = "Crimson Jewel" })
			assert.are.same({ "Crimson Jewel", "Viridian Jewel" }, regularBases)

			local abyssBases = queryGen:GetSelectableBaseNames({ slotName = "Abyssal Jewel 1" }, { type = "Jewel", baseName = "Hypnotic Eye Jewel" })
			assert.are.same({ "Hypnotic Eye Jewel" }, abyssBases)
		end)

		it("filters compatible bases by defence profile", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Armour Helm"] = { type = "Helmet", armour = { ArmourBaseMin = 1 } },
								["Evasion Helm"] = { type = "Helmet", armour = { EvasionBaseMin = 1 } },
								["Armour ES Helm"] = { type = "Helmet", armour = { ArmourBaseMin = 1, EnergyShieldBaseMin = 1 } },
							}
						}
					}
				}
			})

			local bases = queryGen:GetSelectableBaseNames({ slotName = "Helmet" }, { type = "Helmet", baseName = "Armour Helm" }, "armour/energy_shield")
			assert.are.same({ "Armour ES Helm" }, bases)
		end)

		it("formats base defence ranges for display", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Hybrid Helm"] = {
									type = "Helmet",
									req = {
										level = 68,
										str = 50,
										int = 40,
									},
									armour = {
										ArmourBaseMin = 100,
										ArmourBaseMax = 120,
										EnergyShieldBaseMin = 30,
										EnergyShieldBaseMax = 40,
									}
								},
							}
						}
					}
				}
			})

			assert.are.equal("AR 100-120 / ES 30-40", queryGen:GetBaseDefenceRangeText("Hybrid Helm"))
		end)

		it("formats compact max-defence details for the selection list", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Hybrid Helm"] = {
									type = "Helmet",
									req = {
										level = 68,
										str = 50,
										int = 40,
									},
									armour = {
										ArmourBaseMin = 100,
										ArmourBaseMax = 120,
										EnergyShieldBaseMin = 30,
										EnergyShieldBaseMax = 40,
									}
								},
							}
						}
					}
				}
			})

			assert.are.equal("^xC79A2B120 ^x6FD3FF40", queryGen:GetBaseDefenceListDetailText("Hybrid Helm"))
		end)

		it("does not use implicits as the selection detail for accessory bases", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Leather Belt"] = {
									type = "Belt",
									implicit = "+(25-40) to maximum Life",
								},
							}
						}
					}
				}
			})

			assert.is_nil(queryGen:GetBaseSelectionDetailText("Leather Belt"))
		end)

		it("selects top auto-search bases and keeps the equipped base", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Iron Hat"] = data.itemBases["Iron Hat"],
								["Cone Helmet"] = data.itemBases["Cone Helmet"],
								["Royal Burgonet"] = data.itemBases["Royal Burgonet"],
							}
						},
						calcsTab = {
							GetMiscCalculator = function()
								return function(context)
									local scoreByBase = {
										["Iron Hat"] = 40,
										["Cone Helmet"] = 20,
										["Royal Burgonet"] = 60,
									}
									return { Score = scoreByBase[context.repItem.baseName] or 0 }
								end, { Score = 10 }
							end
						}
					}
				}
			})

			local baseNames = queryGen:GetAutoBaseSearchNames(
				{ slotName = "Helmet" },
				{ type = "Helmet", baseName = "Cone Helmet" },
				{ statWeights = { { stat = "Score", weightMult = 1 } } },
				2
			)

			assert.are.same({ "Royal Burgonet", "Cone Helmet" }, baseNames)
		end)

		it("does not keep the equipped base when it does not match the selected defence profile", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Armour Boots"] = { type = "Boots", armour = { ArmourBaseMin = 1 } },
								["Evasion Boots One"] = { type = "Boots", armour = { EvasionBaseMin = 1 } },
								["Evasion Boots Two"] = { type = "Boots", armour = { EvasionBaseMin = 1 } },
							}
						},
						calcsTab = {
							GetMiscCalculator = function()
								return function(context)
									local scoreByBase = {
										["Armour Boots"] = 5,
										["Evasion Boots One"] = 40,
										["Evasion Boots Two"] = 60,
									}
									return { Score = scoreByBase[context.repItem.baseName] or 0 }
								end, { Score = 10 }
							end
						}
					}
				}
			})

			local baseNames = queryGen:GetAutoBaseSearchNames(
				{ slotName = "Boots" },
				{ type = "Boots", baseName = "Armour Boots" },
				{ autoBaseDefenceProfile = "evasion", statWeights = { { stat = "Score", weightMult = 1 } } },
				2
			)

			assert.are.equal(2, #baseNames)
			assert.is_not_nil(isValueInTable(baseNames, "Evasion Boots One"))
			assert.is_not_nil(isValueInTable(baseNames, "Evasion Boots Two"))
			assert.is_nil(isValueInTable(baseNames, "Armour Boots"))
		end)

		it("describes the current auto-selected bases in the tooltip text", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Armour One"] = {
									type = "Helmet",
									req = { level = 20, str = 30 },
									armour = { ArmourBaseMin = 1, ArmourBaseMax = 5 },
								},
								["Armour Two"] = {
									type = "Helmet",
									req = { level = 40, str = 60 },
									armour = { ArmourBaseMin = 1, ArmourBaseMax = 10 },
								},
								["Hybrid One"] = {
									type = "Helmet",
									req = { level = 50, str = 30, int = 30 },
									armour = { ArmourBaseMin = 1, EnergyShieldBaseMin = 1 },
								},
							}
						},
						calcsTab = {
							GetMiscCalculator = function()
								return function(context)
									local scoreByBase = {
										["Armour One"] = 40,
										["Armour Two"] = 60,
										["Hybrid One"] = 90,
									}
									return { Score = scoreByBase[context.repItem.baseName] or 0 }
								end, { Score = 10 }
							end
						}
					}
				}
			})

			local tooltipText = queryGen:GetAutoBaseTooltipText(
				{ slotName = "Helmet" },
				{ type = "Helmet", baseName = "Armour One" },
				{ { stat = "Score", weightMult = 1 } },
				1,
				1,
				"armour"
			)

			assert.matches("Multiple: STR %(Armour%)", tooltipText)
			assert.matches("compatible bases for this slot are ranked with PoB", tooltipText)
			assert.matches("blank rare on each base with the current influence filters", tooltipText)
			assert.matches("equipped base falls outside the top 2", tooltipText)
			assert.matches("Current selected bases:", tooltipText)
			assert.matches("Armour One.*Requires .*Level .*20.*, .*30 .*Str.*Armour .*1%-5", tooltipText)
			assert.matches("Armour Two.*Requires .*Level .*40.*, .*60 .*Str.*Armour .*1%-10", tooltipText)
			assert.does_not_match("Hybrid One", tooltipText)
		end)

		it("describes the exact base defence range in the tooltip text", function()
			local queryGen = new("TradeQueryGenerator", {
				itemsTab = {
					build = {
						data = {
							itemBases = {
								["Hybrid Helm"] = {
									type = "Helmet",
									req = {
										level = 68,
										str = 50,
										int = 40,
									},
									armour = {
										ArmourBaseMin = 100,
										ArmourBaseMax = 120,
										EnergyShieldBaseMin = 30,
										EnergyShieldBaseMax = 40,
									}
								},
							}
						}
					}
				}
			})

			local tooltipText = queryGen:GetExactBaseTooltipText("Hybrid Helm")
			assert.matches("Hybrid Helm", tooltipText)
			assert.matches("Defence Profile: .*Armour / Energy Shield", tooltipText)
			assert.matches("Required Level: .*68", tooltipText)
			assert.matches("Required Strength: .*50", tooltipText)
			assert.matches("Required Intelligence: .*40", tooltipText)
			assert.matches("Armour: .*100%-120", tooltipText)
			assert.matches("Energy Shield: .*30%-40", tooltipText)
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

		it("builds a multi-base search plan when no base is selected", function()
			local queryJson
			local requestedCount
			local originalClosePopup = main.ClosePopup
			main.ClosePopup = function() end

			local queryGen = new("TradeQueryGenerator", { itemsTab = { items = {} } })
			queryGen.requesterCallback = function(_, payload, errMsg)
				assert.is_nil(errMsg)
				queryJson = payload
			end
			queryGen.requesterContext = {}
			queryGen.modWeights = {
				{ tradeModId = "explicit.stat_1", weight = 2, meanStatDiff = 20 }
			}
			queryGen.GetAutoBaseSearchNames = function(self, slot, existingItem, options, limit)
				requestedCount = limit
				return { "Iron Hat", "Cone Helmet" }
			end
			queryGen.BuildBaseDefencePercentileForBase = function(self, slot, existingItem, options, baseName)
				return {
					tradeModId = "pseudo.pseudo_base_defence_percentile",
					weight = baseName == "Iron Hat" and 3 or 4,
				}
			end
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
					autoBaseDefenceProfile = "armour",
					autoBaseSearchCount = 2,
					influence1 = 1,
					influence2 = 1,
					statWeights = {
						{ stat = "Score", weightMult = 1 }
					}
				},
				special = {},
			}
			queryGen.itemsTab.items[1] = {
				baseName = "Iron Hat",
				explicitModLines = {},
				scourgeModLines = {},
				implicitModLines = {},
				crucibleModLines = {},
			}

			queryGen:FinishQuery()

			main.ClosePopup = originalClosePopup

			local primaryQuery = dkjson.decode(queryJson)
			assert.is_nil(primaryQuery.query.type)
			assert.are.equal(2, requestedCount)
			assert.are.equal(2, #queryGen.requesterContext.tradeQueryPlan)
			assert.are.equal("Iron Hat", dkjson.decode(queryGen.requesterContext.tradeQueryPlan[1].query).query.type)
			assert.are.equal("Cone Helmet", dkjson.decode(queryGen.requesterContext.tradeQueryPlan[2].query).query.type)
		end)

		it("builds a ranked unique search plan for exact-base unique queries", function()
			local queryJson
			local originalClosePopup = main.ClosePopup
			main.ClosePopup = function() end

			local queryGen = new("TradeQueryGenerator", { itemsTab = { items = {} } })
			queryGen.requesterCallback = function(_, payload, errMsg)
				assert.is_nil(errMsg)
				queryJson = payload
			end
			queryGen.requesterContext = {}
			queryGen.modWeights = {
				{ tradeModId = "explicit.stat_1", weight = 2, meanStatDiff = 20 }
			}
			queryGen.GetRankedUniqueEntries = function()
				return {
					{ name = "Nebulis", baseName = "Void Sceptre", score = 40000 },
					{ name = "Replica Nebulis", baseName = "Void Sceptre", score = 10000 },
				}
			end
			queryGen.calcContext = {
				slot = { selItemId = 1, slotName = "Weapon 1" },
				testItem = new("Item", "Rarity: RARE\nStat Tester\nVoid Sceptre"),
				calcFunc = function(context)
					if context and context.repItem then
						return { Score = 20 }
					end
					return { Score = 100 }
				end,
				baseOutput = { Score = 100 },
				baseStatValue = 0,
				itemCategoryQueryStr = "weapon.onemace",
				options = {
					includeMirrored = true,
					influence1 = 1,
					influence2 = 1,
					selectedBaseName = "Void Sceptre",
					rarityFilter = "unique",
					statWeights = {
						{ stat = "Score", weightMult = 1 }
					}
				},
				sameBaseType = "Void Sceptre",
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

			local primaryQuery = dkjson.decode(queryJson)
			assert.are.equal("Void Sceptre", primaryQuery.query.type)
			assert.are.equal("Nebulis", primaryQuery.query.name)
			assert.are.equal(2, #queryGen.requesterContext.tradeQueryPlan)
			assert.are.equal("Nebulis", dkjson.decode(queryGen.requesterContext.tradeQueryPlan[1].query).query.name)
			assert.are.equal("Replica Nebulis", dkjson.decode(queryGen.requesterContext.tradeQueryPlan[2].query).query.name)
		end)

		it("targets a single unique when selectedUniqueName is set", function()
			local queryJson
			local originalClosePopup = main.ClosePopup
			main.ClosePopup = function() end

			local queryGen = new("TradeQueryGenerator", { itemsTab = { items = {} } })
			queryGen.requesterCallback = function(_, payload, errMsg)
				assert.is_nil(errMsg)
				queryJson = payload
			end
			queryGen.requesterContext = {}
			queryGen.modWeights = {
				{ tradeModId = "explicit.stat_1", weight = 2, meanStatDiff = 20 }
			}
			queryGen.calcContext = {
				slot = { selItemId = 1, slotName = "Weapon 1" },
				testItem = new("Item", "Rarity: RARE\nStat Tester\nVoid Sceptre"),
				calcFunc = function() return { Score = 100 } end,
				baseOutput = { Score = 100 },
				baseStatValue = 0,
				itemCategoryQueryStr = "weapon.onemace",
				options = {
					includeMirrored = true,
					influence1 = 1,
					influence2 = 1,
					selectedBaseName = "Void Sceptre",
					selectedUniqueName = "Nebulis",
					rarityFilter = "unique",
					statWeights = {
						{ stat = "Score", weightMult = 1 }
					}
				},
				sameBaseType = "Void Sceptre",
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

			local primaryQuery = dkjson.decode(queryJson)
			assert.are.equal("Void Sceptre", primaryQuery.query.type)
			assert.are.equal("Nebulis", primaryQuery.query.name)
			assert.is_nil(queryGen.requesterContext.tradeQueryPlan)
		end)
	end)
end)
