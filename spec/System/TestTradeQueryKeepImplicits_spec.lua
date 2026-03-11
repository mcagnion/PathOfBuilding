describe("TradeQuery keep implicits", function()
	local function rawItem(base, extra)
		return table.concat({
			"Rarity: Rare",
			"Test Item",
			base,
			extra,
		}, "\n")
	end

	local function makeItem(base, extra)
		return new("Item", rawItem(base, extra))
	end

	local function implicitLines(item)
		local lines = { }
		for _, modLine in ipairs(item.implicitModLines or { }) do
			table.insert(lines, modLine.line)
		end
		return lines
	end

	before_each(function()
		newBuild()
		main.migrateEldritchImplicits = true
	end)

	it("overwrites existing eldritch implicits when the query does not target eldritch mods", function()
		local itemsTab = build.itemsTab
		local equippedGloves = makeItem("Velour Gloves", [[
Searing Exarch Item
Eater of Worlds Item
Implicits: 2
Projectiles Pierce an additional Target
Gain 1 Rage on Attack Hit
]])
		local tradeGloves = makeItem("Velour Gloves", [[
Searing Exarch Item
Eater of Worlds Item
Implicits: 2
+5% to Cold Resistance
+6% to Chaos Resistance
]])
		itemsTab.items = { [1] = equippedGloves }
		itemsTab.activeItemSet = { Gloves = { selItemId = 1 } }

		itemsTab:ApplyComparisonItemOverrides(tradeGloves, { preserveExistingEldritchImplicits = false })

		assert.are.same({
			"Projectiles Pierce an additional Target",
			"Gain 1 Rage on Attack Hit",
		}, implicitLines(tradeGloves))
	end)

	it("preserves existing eldritch implicits when the query explicitly targets eldritch mods", function()
		local itemsTab = build.itemsTab
		local equippedGloves = makeItem("Velour Gloves", [[
Searing Exarch Item
Eater of Worlds Item
Implicits: 2
Projectiles Pierce an additional Target
Gain 1 Rage on Attack Hit
]])
		local tradeGloves = makeItem("Velour Gloves", [[
Searing Exarch Item
Eater of Worlds Item
Implicits: 2
+5% to Cold Resistance
+6% to Chaos Resistance
]])
		itemsTab.items = { [1] = equippedGloves }
		itemsTab.activeItemSet = { Gloves = { selItemId = 1 } }

		itemsTab:ApplyComparisonItemOverrides(tradeGloves, { preserveExistingEldritchImplicits = true })

		assert.are.same({
			"+5% to Cold Resistance",
			"+6% to Chaos Resistance",
		}, implicitLines(tradeGloves))
	end)
end)
