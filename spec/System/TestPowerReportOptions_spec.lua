describe("PowerReportOptions", function()
	local powerReportOptions = LoadModule("Modules/PowerReportOptions")

	it("applies, persists and restores the report content defaults", function()
		local defaults = { }
		powerReportOptions.applyDefaults(defaults)

		assert.is_true(defaults.includePowerReportNormals)
		assert.is_true(defaults.includePowerReportRunegrafts)
		assert.is_false(defaults.includePowerReportMasteries)

		defaults.includePowerReportNotables = false
		local attrib = { }
		powerReportOptions.writeToXmlAttrib(defaults, attrib)

		local restored = { }
		powerReportOptions.applyDefaults(restored)
		powerReportOptions.readFromXmlAttrib(restored, attrib)
		assert.is_false(restored.includePowerReportNotables)
		assert.is_true(restored.includePowerReportClusters)
		assert.is_true(powerReportOptions.hasAnyEnabled(restored))
		assert.is_false(powerReportOptions.hasAnyEnabled(powerReportOptions.buildStateByKey(false)))
	end)
end)
