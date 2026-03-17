-- Path of Building
--
-- Module: Power Report Options
-- Shared option definitions for Power Report filters and persistence.
--

local ipairs = ipairs

local powerReportOptions = { }

local optionList = {
	{ key = "includePowerReportNormals", label = "Include Normal Passives", default = true },
	{ key = "includePowerReportNotables", label = "Include Notables", default = true },
	{ key = "includePowerReportKeystones", label = "Include Keystones", default = true },
	{ key = "includePowerReportMasteries", label = "Include Masteries", default = false },
	{ key = "includePowerReportTattoos", label = "Include Tattoos", default = true },
	{ key = "includePowerReportRunegrafts", label = "Include Runegrafts", default = true },
	{ key = "includePowerReportAscSmalls", label = "Include Ascendancy Small Passives", default = true },
	{ key = "includePowerReportAscNotables", label = "Include Ascendancy Notables", default = true },
	{ key = "includePowerReportAscKeystones", label = "Include Ascendancy Keystones", default = true },
	{ key = "includePowerReportBloodlineAscendancy", label = "Include Bloodline Ascendancy Passives", default = true },
	{ key = "includePowerReportForbiddenAscendancy", label = "Include Forbidden Ascendancy Candidates", default = true },
}

function powerReportOptions.getList()
	return optionList
end

function powerReportOptions.applyDefaults(target)
	for _, option in ipairs(optionList) do
		target[option.key] = option.default
	end
end

function powerReportOptions.readFromXmlAttrib(target, attrib)
	for _, option in ipairs(optionList) do
		local value = attrib[option.key]
		if value ~= nil then
			target[option.key] = value == "true"
		end
	end
end

function powerReportOptions.writeToXmlAttrib(target, attrib)
	for _, option in ipairs(optionList) do
		attrib[option.key] = tostring(target[option.key])
	end
end

function powerReportOptions.buildStateByKey(state)
	local out = { }
	for _, option in ipairs(optionList) do
		out[option.key] = state == nil and option.default or state
	end
	return out
end

function powerReportOptions.getKeys()
	local keys = { }
	for _, option in ipairs(optionList) do
		keys[#keys + 1] = option.key
	end
	return keys
end

function powerReportOptions.hasAnyEnabled(target)
	for _, option in ipairs(optionList) do
		if target[option.key] then
			return true
		end
	end
	return false
end

return powerReportOptions
