-- Path of Building
--
-- Class: Gem Trade Report
-- Gem trade report list control.
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

local GemTradeReportListClass = newClass("GemTradeReportListControl", "ListControl", function(self, anchor, rect, selectCallback, tooltipCallback)
	self.ListControl(anchor, rect, 16, "VERTICAL", false)

	local width = rect[3]
	self.deltaColumn = { width = width * 0.18, label = "Delta", sortable = true }
	self.colList = {
		{ width = width * 0.30, label = "Gem", sortable = true },
		{ width = width * 0.24, label = "Candidate", sortable = true },
		self.deltaColumn,
		{ width = width * 0.09, label = "Gain", sortable = true },
		{ width = width * 0.10, label = "Price", sortable = true },
		{ width = width * 0.09, label = "Value", sortable = true },
	}
	self.colLabels = true
	self.selectCallback = selectCallback
	self.tooltipCallback = tooltipCallback
	self.label = "Calculating gem trade upgrades..."
	self.sortColumn = 3
end)

function GemTradeReportListClass:SetReport(stat, report)
	local selectedRow = self.selValue
	self.deltaColumn.label = stat and (stat.label .. " Delta") or "Delta"
	self.list = report or { }
	self.label = #self.list > 0 and "^8Hover columns for details, double-click to jump to gem" or "No trade gem upgrade candidate found."
	self:ReSort(self.sortColumn or 3)
	if selectedRow then
		for index, row in ipairs(self.list) do
			if row == selectedRow then
				self:SelectIndex(index)
				return
			end
		end
	end
	self:SelectIndex(1)
end

function GemTradeReportListClass:ReSort(colIndex)
	self.sortColumn = colIndex or self.sortColumn or 5
	if colIndex == 1 then
		t_sort(self.list, function(a, b)
			if a.name == b.name then
				if a.curSort and b.curSort and a.curSort ~= b.curSort then
					return compareMixed(a.curSort, b.curSort)
				end
				return a.score > b.score
			end
			return a.name < b.name
		end)
	elseif colIndex == 2 then
		t_sort(self.list, function(a, b)
			if a.nextLevel == b.nextLevel then
				return a.score > b.score
			end
			if a.nextSort and b.nextSort then
				return compareMixed(a.nextSort, b.nextSort)
			end
			return compareMixed(a.nextLevel, b.nextLevel)
		end)
	elseif colIndex == 4 then
		t_sort(self.list, function(a, b)
			local improvementA = a.hasImprovementPct and a.improvementPct or -math.huge
			local improvementB = b.hasImprovementPct and b.improvementPct or -math.huge
			if improvementA == improvementB then
				return a.score > b.score
			end
			return improvementA > improvementB
		end)
	elseif colIndex == 5 then
		t_sort(self.list, function(a, b)
			local priceA = a.priceSort or math.huge
			local priceB = b.priceSort or math.huge
			if priceA == priceB then
				return a.score > b.score
			end
			return priceA < priceB
		end)
	elseif colIndex == 6 then
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
				return a.name < b.name
			end
			return a.score > b.score
		end)
	end
end

function GemTradeReportListClass:OnSelClick(index, value, doubleClick)
	if self.selectCallback then
		self.selectCallback(value, doubleClick)
	end
end

function GemTradeReportListClass:GetHoverColumnIndex()
	local x, y = self:GetPos()
	local cursorX = GetCursorPos()
	local relX = cursorX - (x + 2) + self.controls.scrollBarH.offset
	for colIndex, column in ipairs(self.colList) do
		if relX >= column._offset and relX <= column._offset + column._width then
			return colIndex
		end
	end
end

function GemTradeReportListClass:AddValueTooltip(tooltip, index, report)
	if self.tooltipCallback then
		self.tooltipCallback(tooltip, report, self:GetHoverColumnIndex())
	end
end

function GemTradeReportListClass:GetRowValue(column, index, report)
	return column == 1 and formatStatePreservingLabel(report.name, report.currentState or report.level, 24)
		or column == 2 and report.nextLevel
		or column == 3 and report.deltaStr
		or column == 4 and (report.hasImprovementPct and s_format("%+.2f%%", report.improvementPct) or "--")
		or column == 5 and (report.priceText or "--")
		or column == 6 and (report.valueText or "--")
		or ""
end
