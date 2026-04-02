-- Path of Building
--
-- Class: Support Replacement Report
-- Support replacement report list control.
--

local t_sort = table.sort
local s_format = string.format
local m_max = math.max

local function compareMixed(a, b)
	if type(a) == "number" and type(b) == "number" then
		return a < b
	end
	a = tostring(a or "")
	b = tostring(b or "")
	return a < b
end

local function formatStatePreservingLabel(name, state, maxNameLen)
	name = tostring(name or "")
	state = tostring(state or "")
	if state == "" then
		return name
	end
	if #name <= maxNameLen then
		return name .. " " .. state
	end
	return name:sub(1, m_max(1, maxNameLen - 3)) .. "... " .. state
end

local SupportReplacementReportListClass = newClass("SupportReplacementReportListControl", "ListControl", function(self, anchor, rect, selectCallback, tooltipCallback)
	self.ListControl(anchor, rect, 16, "VERTICAL", false)

	local width = rect[3]
	self.deltaColumn = { width = width * 0.19, label = "Delta", sortable = true }
	self.colList = {
		{ width = width * 0.16, label = "Skill", sortable = true },
		{ width = width * 0.20, label = "Current", sortable = true },
		{ width = width * 0.20, label = "Candidate", sortable = true },
		self.deltaColumn,
		{ width = width * 0.08, label = "Gain", sortable = true },
		{ width = width * 0.08, label = "Price", sortable = true },
		{ width = width * 0.09, label = "Value", sortable = true },
	}
	self.colLabels = true
	self.selectCallback = selectCallback
	self.tooltipCallback = tooltipCallback
	self.label = "Calculating support replacements..."
	self.sortColumn = 4
end)

function SupportReplacementReportListClass:SetReport(stat, report)
	self.deltaColumn.label = stat and (stat.label .. " Delta") or "Delta"
	self.list = report or { }
	self.label = #self.list > 0 and "^8Hover columns for details, double-click to jump to gem" or "No support replacement candidate found."
	self:ReSort(self.sortColumn or 4)
	self:SelectIndex(1)
end

function SupportReplacementReportListClass:ReSort(colIndex)
	self.sortColumn = colIndex or self.sortColumn or 4
	if colIndex == 1 then
		t_sort(self.list, function(a, b)
			if a.skillName == b.skillName then
				return a.score > b.score
			end
			return a.skillName < b.skillName
		end)
	elseif colIndex == 2 then
		t_sort(self.list, function(a, b)
			if a.currentLabel == b.currentLabel then
				return a.score > b.score
			end
			return compareMixed(a.curSort, b.curSort)
		end)
	elseif colIndex == 3 then
		t_sort(self.list, function(a, b)
			if a.candidateLabel == b.candidateLabel then
				return a.score > b.score
			end
			return compareMixed(a.nextSort, b.nextSort)
		end)
	elseif colIndex == 5 then
		t_sort(self.list, function(a, b)
			if a.improvementPct == b.improvementPct then
				return a.score > b.score
			end
			return a.improvementPct > b.improvementPct
		end)
	elseif colIndex == 6 then
		t_sort(self.list, function(a, b)
			local priceA = a.priceSort or math.huge
			local priceB = b.priceSort or math.huge
			if priceA == priceB then
				return a.score > b.score
			end
			return priceA < priceB
		end)
	elseif colIndex == 7 then
		t_sort(self.list, function(a, b)
			local valueA = a.valueSort or -math.huge
			local valueB = b.valueSort or -math.huge
			if valueA == valueB then
				return a.score > b.score
			end
			return valueA > valueB
		end)
	else
		t_sort(self.list, function(a, b)
			if a.score == b.score then
				return a.skillName < b.skillName
			end
			return a.score > b.score
		end)
	end
end

function SupportReplacementReportListClass:OnSelClick(index, value, doubleClick)
	if self.selectCallback then
		self.selectCallback(value, doubleClick)
	end
end

function SupportReplacementReportListClass:GetHoverColumnIndex()
	local x = self:GetPos()
	local cursorX = GetCursorPos()
	local relX = cursorX - (x + 2) + self.controls.scrollBarH.offset
	for colIndex, column in ipairs(self.colList) do
		if relX >= column._offset and relX <= column._offset + column._width then
			return colIndex
		end
	end
end

function SupportReplacementReportListClass:AddValueTooltip(tooltip, index, report)
	if self.tooltipCallback then
		self.tooltipCallback(tooltip, report, self:GetHoverColumnIndex())
	end
end

function SupportReplacementReportListClass:GetRowValue(column, index, report)
	return column == 1 and report.skillName
		or column == 2 and formatStatePreservingLabel(report.name, report.currentState, 18)
		or column == 3 and formatStatePreservingLabel(report.candidateName, report.candidateState, 18)
		or column == 4 and report.deltaStr
		or column == 5 and (report.hasImprovementPct and s_format("%+.2f%%", report.improvementPct) or "--")
		or column == 6 and (report.priceText or "--")
		or column == 7 and (report.valueText or "--")
		or ""
end
