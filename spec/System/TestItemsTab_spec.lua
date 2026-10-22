describe("ItemsTab", function()
	before_each(function()
		newBuild()
	end)

	it("lists an edited item saved after its original was deleted", function()
		local itemsTab = build.itemsTab
		itemsTab:CreateDisplayItemFromRaw("Rarity: RARE\nTest Spark\nCrimson Jewel\n+10 to maximum Life")
		itemsTab:AddDisplayItem(true)
		local item = itemsTab.items[itemsTab.itemOrderList[1]]
		-- Opening an item from the item list edits a copy that keeps the original's ID
		local editedItem = new("Item"):Item(item:BuildRaw())
		editedItem.id = item.id
		itemsTab:SetDisplayItem(editedItem)
		itemsTab:DeleteItem(item)

		itemsTab:AddDisplayItem(true)

		assert.are.same({ editedItem.id }, itemsTab.itemOrderList)
	end)

	it("keeps a new item that reuses the ID of an edited item's deleted original", function()
		local itemsTab = build.itemsTab
		itemsTab:CreateDisplayItemFromRaw("Rarity: RARE\nTest Spark\nCrimson Jewel\n+10 to maximum Life")
		itemsTab:AddDisplayItem(true)
		local item = itemsTab.items[itemsTab.itemOrderList[1]]
		-- Opening an item from the item list edits a copy that keeps the original's ID
		local editedItem = new("Item"):Item(item:BuildRaw())
		editedItem.id = item.id
		itemsTab:SetDisplayItem(editedItem)
		itemsTab:DeleteItem(item)
		local otherItem = new("Item"):Item("Rarity: RARE\nOther Spark\nCobalt Jewel\n+10 to maximum Mana")
		itemsTab:AddItem(otherItem, true)

		itemsTab:AddDisplayItem(true)

		assert.are.equal("Other Spark, Cobalt Jewel", itemsTab.items[otherItem.id].name)
	end)
end)
