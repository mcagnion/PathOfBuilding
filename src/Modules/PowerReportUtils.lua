-- Path of Building
--
-- Module: Power Report Utils
-- Shared helper functions for Power Report filtering and labeling.
--

local powerReportUtils = { }

function powerReportUtils.isClusterJewelPassiveNode(node)
	return node
		and node.expansionSkill
		and node.id
		and node.id >= 65536
end

function powerReportUtils.makeAscendancyContext(spec)
	return {
		primaryAscendancy = spec.curAscendClassBaseName,
		secondaryAscendancy = spec.curSecondaryAscendClass and spec.curSecondaryAscendClass.id,
		currentClassId = spec.curClassId,
		ascendNameMap = spec.tree.ascendNameMap or { },
	}
end

function powerReportUtils.isCurrentAscendancyNode(context, node)
	return node
		and node.ascendancyName
		and (
			node.ascendancyName == context.primaryAscendancy
			or node.ascendancyName == context.secondaryAscendancy
		)
end

function powerReportUtils.isSameBaseClassAscendancyNode(context, node)
	if not (node and node.ascendancyName) then
		return false
	end
	local ascendInfo = context.ascendNameMap[node.ascendancyName]
	return ascendInfo and ascendInfo.classId == context.currentClassId
end

function powerReportUtils.isEnabledAscendancyType(options, node)
	if node.isBloodline and not options.includePowerReportBloodlineAscendancy then
		return false
	end
	if node.type == "Notable" then
		return options.includePowerReportAscNotables
	elseif node.type == "Keystone" then
		return options.includePowerReportAscKeystones
	elseif node.type == "Normal" then
		return options.includePowerReportAscSmalls
	end
	return true
end

function powerReportUtils.isForbiddenAscendancyNode(context, options, node)
	return options.includePowerReportForbiddenAscendancy
		and node
		and node.ascendancyName
		and not node.isBloodline
		and not powerReportUtils.isCurrentAscendancyNode(context, node)
		and powerReportUtils.isSameBaseClassAscendancyNode(context, node)
		and (node.type == "Notable" or node.type == "Keystone")
end

function powerReportUtils.isIncludedAscendancyNode(context, options, node)
	if not node.ascendancyName then
		return true
	end
	if powerReportUtils.isCurrentAscendancyNode(context, node) then
		return powerReportUtils.isEnabledAscendancyType(options, node)
	end
	if node.isBloodline then
		return options.includePowerReportBloodlineAscendancy
	end
	return powerReportUtils.isForbiddenAscendancyNode(context, options, node)
end

function powerReportUtils.isRemoteAscendancyCandidate(context, node)
	if not (node and node.ascendancyName) then
		return false
	end
	return not powerReportUtils.isCurrentAscendancyNode(context, node)
		and (
			node.isBloodline
			or (
				powerReportUtils.isSameBaseClassAscendancyNode(context, node)
				and (node.type == "Notable" or node.type == "Keystone")
			)
		)
end

function powerReportUtils.reportNodeType(node, isForbiddenNode)
	if isForbiddenNode then
		return "Forbidden " .. (node.type or "Node")
	end
	if node.ascendancyName then
		local prefix = node.isBloodline and "Bloodline" or "Asc"
		return prefix .. " " .. (node.type or "Node")
	end
	return node.type or "Node"
end

return powerReportUtils
