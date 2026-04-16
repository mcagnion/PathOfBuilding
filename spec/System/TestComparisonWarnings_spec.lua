local function newItemSource(name, slot)
	return {
		source = "Item",
		sourceItem = { name = name },
		sourceSlot = slot or "",
	}
end

local function newGemSource(name, level, quality)
	return {
		source = "Gem",
		sourceGem = {
			nameSpec = name,
			level = level or 20,
			quality = quality or 0,
		},
	}
end

local function newFakeTooltip()
	return {
		lines = { },
		AddLine = function(self, _, text)
			table.insert(self.lines, text)
		end,
	}
end

local function createComparisonItem(raw)
	build.itemsTab:CreateDisplayItemFromRaw(raw)
	return build.itemsTab.displayItem
end

local function rebuildWithCustomMods(customMods)
	build.configTab.input.customMods = customMods
	build.configTab:BuildModList()
	build.modFlag = true
	build.buildFlag = true
	runCallback("OnFrame")
end

local function collectTooltipLines(tooltip)
	local lines = { }
	for _, line in ipairs(tooltip.lines) do
		if line.text then
			table.insert(lines, line.text)
		end
	end
	return lines
end

describe("TestComparisonWarnings", function()
	before_each(function()
		newBuild()
	end)

	it("lists only newly failing requirement sources", function()
		local baseOutput = {
			Str = 120,
			ReqStr = 100,
			ReqStrFailList = {
				{ source = newGemSource("Existing Gem"), req = 130 },
			},
		}
		local compareOutput = {
			Str = 90,
			ReqStr = 130,
			ReqStrFailList = {
				{ source = newGemSource("Existing Gem"), req = 130 },
				{ source = newItemSource("Astral Plate", "Body Armour"), req = 111 },
				{ source = newGemSource("Added Fire Damage", 20, 20), req = 100 },
			},
		}

		assert.are.same({
			colorCodes.NEGATIVE .. "Astral Plate requires 111 Strength",
			colorCodes.NEGATIVE .. "Added Fire Damage requires 100 Strength",
		}, build:GetRequirementComparisonWarnings(baseOutput, compareOutput))
	end)

	it("still lists newly failing sources when the base state already fails the attribute", function()
		local baseOutput = {
			Dex = 90,
			ReqDex = 110,
			ReqDexFailList = {
				{ source = newGemSource("Existing Gem"), req = 110 },
			},
		}
		local compareOutput = {
			Dex = 80,
			ReqDex = 110,
			ReqDexFailList = {
				{ source = newGemSource("Existing Gem"), req = 110 },
				{ source = newItemSource("Slink Boots", "Boots"), req = 100 },
			},
		}

		assert.are.same({
			colorCodes.NEGATIVE .. "Slink Boots requires 100 Dexterity",
		}, build:GetRequirementComparisonWarnings(baseOutput, compareOutput))
	end)

	it("falls back to item requirement wording when no fail list is available", function()
		local baseOutput = {
			Dex = 120,
			ReqDex = 100,
		}
		local compareOutput = {
			Dex = 80,
			ReqDex = 120,
			ReqDexItem = newItemSource("Slink Boots", "Boots"),
		}

		assert.are.same({
			colorCodes.NEGATIVE .. "Slink Boots requires 120 Dexterity",
		}, build:GetRequirementComparisonWarnings(baseOutput, compareOutput))
	end)

	it("adds the header only when requirement warnings are the first comparison lines", function()
		local baseOutput = {
			Int = 120,
			ReqInt = 100,
		}
		local compareOutput = {
			Int = 90,
			ReqInt = 110,
			ReqIntFailList = {
				{ source = newGemSource("Increased Critical Damage", 20, 0), req = 110 },
			},
		}
		local tooltip = newFakeTooltip()

		local count = build:AddRequirementWarningsToTooltip(tooltip, baseOutput, compareOutput, "^7Header", 0)

		assert.are.equal(1, count)
		assert.are.same({
			"^7Header",
			colorCodes.NEGATIVE .. "Increased Critical Damage requires 110 Intelligence",
		}, tooltip.lines)
	end)

	it("does not repeat the header when stat comparison lines already exist", function()
		local baseOutput = {
			Int = 120,
			ReqInt = 100,
		}
		local compareOutput = {
			Int = 90,
			ReqInt = 110,
			ReqIntFailList = {
				{ source = newGemSource("Increased Critical Damage", 20, 0), req = 110 },
			},
		}
		local tooltip = newFakeTooltip()

		local count = build:AddRequirementWarningsToTooltip(tooltip, baseOutput, compareOutput, "^7Header", 1)

		assert.are.equal(1, count)
		assert.are.same({
			colorCodes.NEGATIVE .. "Increased Critical Damage requires 110 Intelligence",
		}, tooltip.lines)
	end)

	it("exposes gem fail lists from real calculator output", function()
		rebuildWithCustomMods("+200 to Intelligence")
		build.skillsTab:PasteSocketGroup("Fireball 20/0  1\n")
		runCallback("OnFrame")

		local compareItem = createComparisonItem("New Item\nAmber Amulet\n-150 to Intelligence")
		local calcFunc, baseOutput = build.calcsTab:GetMiscCalculator()
		local compareOutput = calcFunc({ repSlotName = "Amulet", repItem = compareItem })

		assert.is_nil(baseOutput.ReqIntFailList)
		assert.are.equal("Gem", compareOutput.ReqIntFailList[1].source.source)
		assert.are.equal("Fireball", compareOutput.ReqIntFailList[1].source.sourceGem.nameSpec)
		assert.are.equal("Fireball requires " .. compareOutput.ReqIntFailList[1].req .. " Intelligence", build:GetRequirementComparisonWarnings(baseOutput, compareOutput)[1]:gsub("^" .. colorCodes.NEGATIVE, ""))
	end)

	it("writes requirement warnings through AddStatComparesToTooltip with a real tooltip", function()
		build.skillsTab:PasteSocketGroup("Fireball 1/0  1\n")
		rebuildWithCustomMods("+90 to Strength")

		local compareItem = createComparisonItem("New Item\nTitan Greaves")
		local calcFunc, baseOutput = build.calcsTab:GetMiscCalculator()
		local compareOutput = calcFunc({ repSlotName = "Boots", repItem = compareItem })
		local tooltip = new("Tooltip")

		build:AddStatComparesToTooltip(tooltip, baseOutput, compareOutput, "^7Comparison")

		local lines = collectTooltipLines(tooltip)
		local headerCount = 0
		local foundWarning = false
		for _, line in ipairs(lines) do
			if line == "^7Comparison" then
				headerCount = headerCount + 1
			end
			if line:find("Titan Greaves requires", 1, true) then
				foundWarning = true
			end
		end

		assert.are.equal(1, headerCount)
		assert.is_true(foundWarning)
	end)
end)
