describe("TestImportReimport", function()
	before_each(function()
		newBuild()
	end)

	it("preserves manually disabled gems when reimporting items and skills", function()
		build.skillsTab:PasteSocketGroup([[
Slot: Helmet
Cleave 1/0 Default  1
Added Fire Damage 1/0 Default DISABLED 1
]])
		runCallback("OnFrame")

		build.importTab.controls.charImportItemsClearSkills.state = true
		build.importTab.controls.charImportItemsClearItems.state = false
		build.importTab:ImportItemsAndSkills([=[
{
	"character": {
		"level": 12
	},
	"items": [
		{
			"id": "helm-1",
			"frameType": 0,
			"name": "",
			"typeLine": "Iron Hat",
			"inventoryId": "Helm",
			"ilvl": 10,
			"properties": [],
			"sockets": [
				{ "group": 0, "sColour": "R" },
				{ "group": 0, "sColour": "R" }
			],
			"socketedItems": [
				{
					"socket": 0,
					"support": false,
					"typeLine": "Cleave",
					"properties": [
						{ "name": "Level", "values": [["1", 0]] },
						{ "name": "Quality", "values": [["+0%", 0]] }
					]
				},
				{
					"socket": 1,
					"support": true,
					"typeLine": "Added Fire Damage Support",
					"properties": [
						{ "name": "Level", "values": [["2", 0]] },
						{ "name": "Quality", "values": [["+0%", 0]] }
					]
				}
			]
		}
	]
}
]=])
		runCallback("OnFrame")

		local socketGroup = build.skillsTab.socketGroupList[1]
		assert.are.equal("Helmet", socketGroup.slot)
		assert.are.equal(2, socketGroup.gemList[2].level)
		assert.is_false(socketGroup.gemList[2].enabled)
	end)
end)
