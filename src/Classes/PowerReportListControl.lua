-- Path of Building
--
-- Class: Power Report
-- Power Report control.
--

local t_insert = table.insert
local t_remove = table.remove
local t_sort = table.sort
local t_concat = table.concat
local m_min = math.min
local enemyConditionUtils = LoadModule("Modules/EnemyConditionUtils")

local PowerReportListClass = newClass("PowerReportListControl", "ListControl", function(self, anchor, rect, nodeSelectCallback)
	self.ListControl(anchor, rect, 16, "VERTICAL", false)

	local width = rect[3]
	self.powerColumn = { width = width * 0.14, label = "", sortable = true }
	self.powerPercentColumn = { width = width * 0.11, label = "%", sortable = true }
	self.pathPowerColumn = { width = width * 0.12, label = "Per Point", sortable = true }
	self.pathPowerPercentColumn = { width = width * 0.11, label = "%/Point", sortable = true }
	self.colList = {
		{ width = width * 0.13, label = "Type", sortable = true },
		{ width = width * 0.33, label = "Node Name" },
		self.powerColumn,
		self.powerPercentColumn,
		{ width = width * 0.06, label = "Points", sortable = true },
		self.pathPowerColumn,
		self.pathPowerPercentColumn,
	}
	self.colLabels = true
	self.nodeSelectCallback = nodeSelectCallback
	self.showClusters = false
	self.allocated = false
	self.label = "Building Tree..."
	
	self.controls.filterSelect = new("DropDownControl", {"BOTTOMRIGHT", self, "TOPRIGHT"}, {0, -2, 200, 20},
		{ "Show Unallocated", "Show Unallocated & Clusters", "Show Allocated" },
		function(index, value)
			self.showClusters = index == 2
			self.allocated = index == 3
			self:ReList()
			self:ReSort(3) -- Sort by power
		end)
end)

function PowerReportListClass:SetReport(stat, report)
	self.powerColumn.label = stat and stat.label or ""
	self.powerPercentColumn.label = self.powerColumn.label ~= "" and (self.powerColumn.label .. " %") or "%"
	self.originalList = report or {}

	if stat and stat.stat then
		self.label = report and "Click to focus node on tree (tooltips show assumed enemy conditions)" or "Building Tree..."
	else
		self.label = "^7\""..self.powerColumn.label.."\" not supported.  Select a specific stat from the dropdown."
	end

	self:ReList()
end

function PowerReportListClass:ReSort(colIndex)
	-- Reverse power sort for allocated because it uses negative numbers
	local compare = self.allocated and 
		function(a, b) return a < b end
		or function(a, b) return a > b end

	if colIndex == 1 then
		t_sort(self.list, function (a,b)
			if a.type == b.type then
				return compare(a.power, b.power)
			end
			return a.type < b.type
		end)
	elseif colIndex == 3 then
		t_sort(self.list, function (a,b)
			return compare(a.power, b.power)
		end)
	elseif colIndex == 4 then
		t_sort(self.list, function (a,b)
			local aPercent = a.powerPercent
			local bPercent = b.powerPercent
			if aPercent == bPercent then
				return compare(a.power, b.power)
			end
			if aPercent == nil then
				return false
			end
			if bPercent == nil then
				return true
			end
			return compare(aPercent, bPercent)
		end)
	elseif colIndex == 5 then
		t_sort(self.list, function (a,b)
			if type(a.pathDist) ~= "number" then
				return false
			end
			if type(b.pathDist) ~= "number" then
				return true
			end
			if a.pathDist == b.pathDist then
				return compare(a.power, b.power)
			end
			return a.pathDist < b.pathDist
		end)
	elseif colIndex == 6 then
		t_sort(self.list, function (a,b)
			if a.pathPower == b.pathPower and type(a.pathDist) == "number" and type(b.pathDist) == "number" then
				return a.pathDist < b.pathDist
			end
			return compare(a.pathPower, b.pathPower)
		end)
	elseif colIndex == 7 then
		t_sort(self.list, function (a,b)
			local aPercent = a.pathPowerPercent
			local bPercent = b.pathPowerPercent
			if aPercent == bPercent then
				return compare(a.pathPower, b.pathPower)
			end
			if aPercent == nil then
				return false
			end
			if bPercent == nil then
				return true
			end
			return compare(aPercent, bPercent)
		end)
	end
end

function PowerReportListClass:ReList()
	self.list = { }
	if not self.originalList then
		return
	end

	for _, item in ipairs(self.originalList) do
		local isTattooType = item.type == "Runegraft"
			or (item.type and item.type:find("Tattoo", 1, true) ~= nil)
		local canAlwaysShow = item.alwaysShow and (not isTattooType or item.power > 0)
		local insert = item.power > 0 or canAlwaysShow
		if isTattooType and item.power <= 0 then
			insert = false
		end
		if not self.showClusters and item.pathDist == "Cluster" then
			insert = false
		end
		if self.allocated then
			insert = item.allocated
		end

		if insert then
			t_insert(self.list, item)
		end
	end
end

function PowerReportListClass:OnSelClick(index, report, doubleClick)
	if self.nodeSelectCallback then
		self.nodeSelectCallback(report)
	end
end

function PowerReportListClass:AddValueTooltip(tooltip, index, report)
	tooltip:Clear()
	if not report then
		return
	end

	tooltip:AddLine(16, colorCodes.CRAFTED..report.name)
	if report.cluster then
		tooltip:AddLine(16, "^7Source: Cluster Jewel passive")
	end

	if report.stats and report.stats[1] then
		tooltip:AddSeparator(14)
		for _, line in ipairs(report.stats) do
			if line ~= " " then
				tooltip:AddLine(16, colorCodes.MAGIC..line)
			end
		end
	end

	local build = self.build
	local showStatDifferences = self.getShowStatDifferences and self.getShowStatDifferences()
	if build and showStatDifferences ~= nil then
		if showStatDifferences then
			local calcFunc, calcBase = build.calcsTab:GetMiscCalculator(build)
			local count = 0
			tooltip:AddSeparator(14)

			local function isGeneratedTattooOption()
				return report.type == "Runegraft"
					or (report.type and report.type:find("Tattoo", 1, true) ~= nil)
			end
			local function findClusterNodeById(nodeId)
				for _, node in pairs(build.spec.tree.clusterNodeMap or { }) do
					if node.id == nodeId then
						return node
					end
				end
			end

			if isGeneratedTattooOption() then
				tooltip:AddLine(14, "^8Stat-difference details are not available for this generated option.")
			else
				local node = report.cluster and findClusterNodeById(report.id) or build.spec.nodes[report.id]
				if node then
					local path = (node.alloc and node.depends) or node.path or { }
					local pathLength = #path
					local intuitiveLeapCount = #(node.intuitiveLeapLikesAffecting or { })
					local pathNodes = { }
					for _, pathNode in pairs(path) do
						pathNodes[pathNode] = true
					end
					local nodeOutput, pathOutput
					local isGranted = build.calcsTab.mainEnv.grantedPassives[node.id]
					local realloc = false
					if node.alloc and node.type == "Mastery" and main.popups[1] then
						realloc = true
						nodeOutput = calcFunc({ addNodes = { [node] = true } })
					elseif node.alloc then
						nodeOutput = calcFunc({ removeNodes = { [node] = true } })
						if pathLength > 1 then
							pathOutput = calcFunc({ removeNodes = pathNodes })
						end
					elseif isGranted then
						nodeOutput = calcFunc({ removeNodes = { [node.id] = true } })
					else
						nodeOutput = calcFunc({ addNodes = { [node] = true } })
						if pathLength > 1 then
							pathOutput = calcFunc({ addNodes = pathNodes })
						end
					end
					count = build:AddStatComparesToTooltip(
						tooltip,
						calcBase,
						nodeOutput,
						realloc and "^7Reallocating this node will give you:"
							or node.alloc and "^7Unallocating this node will give you:"
							or isGranted and "^7This node is granted by an item. Removing it will give you:"
							or "^7Allocating this node will give you:"
					)
					if pathLength > 1 and not isGranted and (intuitiveLeapCount == 0 or node.alloc) then
						count = count + build:AddStatComparesToTooltip(
							tooltip,
							calcBase,
							pathOutput,
							node.alloc and "^7Unallocating this node and all nodes depending on it will give you:"
								or "^7Allocating this node and all nodes leading to it will give you:",
							pathLength
						)
					end
					if count == 0 then
						if isGranted then
							tooltip:AddLine(14, "^7This node is granted by an item. Removing it will cause no changes")
						else
							tooltip:AddLine(14, string.format(
								"^7No changes from %s this node%s.",
								node.alloc and "unallocating" or "allocating",
								intuitiveLeapCount == 0 and pathLength > 1 and " or the nodes leading to it" or ""
							))
						end
					end
				else
					tooltip:AddLine(14, "^8Stat-difference details are unavailable for this entry.")
				end
			end
			tooltip:AddLine(14, colorCodes.TIP.."Tip: Press Ctrl+D to disable the display of stat differences.")
		else
			tooltip:AddSeparator(14)
			tooltip:AddLine(14, colorCodes.TIP.."Tip: Press Ctrl+D to enable the display of stat differences.")
		end
	end

	local function findConditionSources(condition)
		local sourceMap = report.enemyConditionSourceMap
		if sourceMap then
			return sourceMap[condition]
		end
	end
	local function formatSources(sources)
		if not sources or #sources == 0 then
			return nil
		end
		local limit = 3
		local shown = { }
		for i = 1, m_min(limit, #sources) do
			t_insert(shown, sources[i])
		end
		local out = t_concat(shown, ", ")
		if #sources > limit then
			out = out .. " +" .. (#sources - limit) .. " more"
		end
		return out
	end
	local function addAssumedConditionBlock(title, conditions)
		if not conditions or #conditions == 0 then
			return false
		end
		tooltip:AddSeparator(14)
		tooltip:AddLine(16, "^7" .. title)
		for _, condition in ipairs(conditions) do
			local sourceText = formatSources(findConditionSources(condition))
			if sourceText then
				tooltip:AddLine(16, "^7- " .. condition .. "^8 (" .. sourceText .. ")")
			else
				tooltip:AddLine(16, "^7- " .. condition)
			end
		end
		return true
	end

	local nodeAssumptions = enemyConditionUtils.subtractConditionLists(
		report.assumedEnemyConditions,
		report.baseAssumedEnemyConditions
	)
	local pathAssumptions = enemyConditionUtils.subtractConditionLists(
		report.pathAssumedEnemyConditions,
		report.baseAssumedEnemyConditions
	)
	local hasAssumptions = addAssumedConditionBlock(
		"Power Report assumptions added by this node:",
		nodeAssumptions
	)
	if enemyConditionUtils.conditionKey(pathAssumptions) ~= enemyConditionUtils.conditionKey(nodeAssumptions) then
		hasAssumptions = addAssumedConditionBlock(
			"Power Report assumptions added by node/path:",
			pathAssumptions
		) or hasAssumptions
	end
	if hasAssumptions then
		tooltip:AddLine(16, "^8Affects Power/Per Point values only.")
		tooltip:AddLine(16, "^8Enable matching Configuration options to match these values.")
	end
end

function PowerReportListClass:GetRowValue(column, index, report)
	return column == 1 and report.type
		or column == 2 and report.name
		or column == 3 and report.powerStr
		or column == 4 and (report.powerPercentStr or "--")
		or column == 5 and (
			report.pathDist == 1000 and "Anoint"
			or report.pathDist
			or "--"
		)
		or column == 6 and report.pathPowerStr
		or column == 7 and (report.pathPowerPercentStr or "--")
		or ""
end
