describe("PowerReportUtils", function()
	local powerReportUtils = LoadModule("Modules/PowerReportUtils")

	it("filters current, bloodline and forbidden ascendancy candidates", function()
		local context = {
			primaryAscendancy = "Juggernaut",
			currentClassId = 1,
			ascendNameMap = {
				Juggernaut = { classId = 1 },
				Guardian = { classId = 1 },
				Pathfinder = { classId = 2 },
			},
		}
		local options = {
			includePowerReportAscSmalls = false,
			includePowerReportAscNotables = true,
			includePowerReportAscKeystones = true,
			includePowerReportBloodlineAscendancy = false,
			includePowerReportForbiddenAscendancy = true,
		}

		assert.is_false(powerReportUtils.isIncludedAscendancyNode(context, options, {
			ascendancyName = "Juggernaut",
			type = "Normal",
		}))
		assert.is_true(powerReportUtils.isIncludedAscendancyNode(context, options, {
			ascendancyName = "Guardian",
			type = "Notable",
		}))
		assert.is_false(powerReportUtils.isIncludedAscendancyNode(context, options, {
			ascendancyName = "Juggernaut",
			type = "Normal",
			isBloodline = true,
		}))

		options.includePowerReportForbiddenAscendancy = false
		assert.is_false(powerReportUtils.isIncludedAscendancyNode(context, options, {
			ascendancyName = "Guardian",
			type = "Notable",
		}))
	end)
end)
