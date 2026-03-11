-- Path of Building
--
-- Class: Gem Upgrade Report
-- Gem upgrade report list control.
--

local t_sort = table.sort
local s_format = string.format

local function compareMixed(a, b)
	if type(a) == "number" and type(b) == "number" then
		return a < b
	end
	a = tostring(a or "")
	b = tostring(b or "")
	return a < b
end

local GemUpgradeReportListClass = newClass("GemUpgradeReportListControl", "ListControl", function(self, anchor, rect, selectCallback, tooltipCallback)
	self.ListControl(anchor, rect, 16, "VERTICAL", false)

	local width = rect[3]
	self.deltaColumn = { width = width * 0.22, label = "Delta", sortable = true }
	self.colList = {
		{ width = width * 0.18, label = "Change", sortable = true },
		{ width = width * 0.22, label = "Gem", sortable = true },
		{ width = width * 0.26, label = "Next", sortable = true },
		self.deltaColumn,
		{ width = width * 0.12, label = "Improvement", sortable = true },
	}
	self.colLabels = true
	self.selectCallback = selectCallback
	self.tooltipCallback = tooltipCallback
	self.label = "Calculating gem upgrades..."
end)

function GemUpgradeReportListClass:SetReport(stat, report)
	self.deltaColumn.label = stat and (stat.label .. " Delta") or "Delta"
	self.list = report or { }
	self.label = #self.list > 0 and "Hover columns for details, double-click to jump to gem" or "No gem can be upgraded for this report."
	self:ReSort(4)
	self:SelectIndex(1)
end

function GemUpgradeReportListClass:ReSort(colIndex)
	if colIndex == 1 then
		t_sort(self.list, function(a, b)
			if a.upgradeLabel == b.upgradeLabel then
				return a.score > b.score
			end
			return a.upgradeLabel < b.upgradeLabel
		end)
	elseif colIndex == 2 then
		t_sort(self.list, function(a, b)
			if a.name == b.name then
				if a.curSort and b.curSort and a.curSort ~= b.curSort then
					return a.curSort < b.curSort
				end
				return a.score > b.score
			end
			return a.name < b.name
		end)
	elseif colIndex == 3 then
		t_sort(self.list, function(a, b)
			if a.nextLevel == b.nextLevel then
				return a.score > b.score
			end
			if a.nextSort and b.nextSort then
				return a.nextSort < b.nextSort
			end
			return compareMixed(a.nextLevel, b.nextLevel)
		end)
	elseif colIndex == 5 then
		t_sort(self.list, function(a, b)
			if a.improvementPct == b.improvementPct then
				return a.score > b.score
			end
			return a.improvementPct > b.improvementPct
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

function GemUpgradeReportListClass:OnSelClick(index, value, doubleClick)
	if self.selectCallback then
		self.selectCallback(value, doubleClick)
	end
end

function GemUpgradeReportListClass:GetHoverColumnIndex()
	local x = self:GetPos()
	local cursorX = GetCursorPos()
	local relX = cursorX - (x + 2) + self.controls.scrollBarH.offset
	for colIndex, column in ipairs(self.colList) do
		if relX >= column._offset and relX <= column._offset + column._width then
			return colIndex
		end
	end
end

function GemUpgradeReportListClass:AddValueTooltip(tooltip, index, report)
	if self.tooltipCallback then
		self.tooltipCallback(tooltip, report, self:GetHoverColumnIndex())
	end
end

function GemUpgradeReportListClass:GetRowValue(column, index, report)
	return column == 1 and report.upgradeLabel
		or column == 2 and (report.name .. " " .. tostring(report.currentState or report.level))
		or column == 3 and report.nextLevel
		or column == 4 and report.deltaStr
		or column == 5 and (report.hasImprovementPct and s_format("%+.2f%%", report.improvementPct) or "--")
		or ""
end
