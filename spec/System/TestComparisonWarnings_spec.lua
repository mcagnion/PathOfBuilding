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

	it("falls back to the highest failing source when no fail list is available", function()
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
			colorCodes.NEGATIVE .. "Would not meet Dexterity requirement of Slink Boots (120 required)",
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
end)
