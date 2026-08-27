--[[
	StatPriorityFirst - Guide pages + bottom tabs
	----
	Friendly How-It-Works and Diminishing Returns pages under the main panel.
	Tabs sit on the panel chrome; Priority page keeps the live build UI.
--]]

local _, ns = ...
local L = ns.L
local Skin = ns.Skin

ns.UI = ns.UI or {}

local CreateFrame = CreateFrame
local format = string.format
local max = math.max
local min = math.min

local TAB_H = 28
local TAB_GAP = 4
local GUIDE_WIDTH = 480
local GUIDE_FALLBACK_WIDTH = 520

local TAB_IDS = { "priority", "howto", "dr" }

local function MakeWrappedText(parent, font, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	fs:SetNonSpaceWrap(true)
	if r then
		fs:SetTextColor(r, g, b)
	end
	return fs
end

local function LayoutParagraphs(host, lines, width)
	local y = -4
	for i = 1, #lines do
		local line = lines[i]
		local fs = host.lines[i]
		if not fs then
			fs = MakeWrappedText(host, line.font, line.r, line.g, line.b)
			host.lines[i] = fs
		end
		fs:SetFontObject(line.font or "GameFontHighlight")
		if line.r then
			fs:SetTextColor(line.r, line.g, line.b)
		else
			fs:SetTextColor(0.85, 0.85, 0.85)
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", host, "TOPLEFT", 8, y)
		fs:SetWidth(width - 20)
		fs:SetText(line.text or "")
		fs:Show()
		y = y - (fs:GetStringHeight() or 12) - (line.pad or 8)
	end
	for i = #lines + 1, #host.lines do
		host.lines[i]:Hide()
	end
	host:SetHeight(max(40, -y + 8))
	return -y + 8
end

local function EnsureScrollPage(panel, key)
	if panel[key] then
		return panel[key]
	end

	local page = CreateFrame("Frame", nil, panel)
	page:SetPoint("TOPLEFT", panel.classBtn, "BOTTOMLEFT", 0, -10)
	page:SetPoint("BOTTOMRIGHT", panel.tabBar, "TOPRIGHT", 0, 8)
	page:Hide()

	local scroll = CreateFrame("ScrollFrame", nil, page)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -4, 0)
	page.scroll = scroll

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(GUIDE_WIDTH, 100)
	child.lines = {}
	scroll:SetScrollChild(child)
	page.child = child

	scroll:EnableMouse(true)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local cur = self:GetVerticalScroll()
		local maxScroll = max(0, (self:GetScrollChild():GetHeight() or 0) - self:GetHeight())
		self:SetVerticalScroll(min(maxScroll, max(0, cur - delta * 28)))
	end)

	panel[key] = page
	return page
end

local function BuildHowtoLines()
	return {
		{ text = L["GUIDE_HOWTO_TITLE"], font = "GameFontNormalLarge", r = 1, g = 0.82, b = 0, pad = 10 },
		{ text = L["GUIDE_HOWTO_INTRO"], pad = 12 },
		{ text = L["GUIDE_HOWTO_CHAIN"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 6 },
		{ text = L["GUIDE_HOWTO_CHAIN_BODY"], pad = 12 },
		{ text = L["GUIDE_HOWTO_GAPS"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 6 },
		{ text = L["GUIDE_HOWTO_GAPS_BODY"], pad = 12 },
		{ text = L["GUIDE_HOWTO_BUILDS"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 6 },
		{ text = L["GUIDE_HOWTO_BUILDS_BODY"], pad = 12 },
		{ text = L["GUIDE_HOWTO_GEAR"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 6 },
		{ text = L["GUIDE_HOWTO_GEAR_BODY"], pad = 12 },
		{ text = L["GUIDE_HOWTO_TIPS"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 6 },
		{ text = L["GUIDE_HOWTO_TIPS_BODY"], pad = 8 },
	}
end

local function BuildDRLines(specEntry)
	local lines = {
		{ text = L["GUIDE_DR_TITLE"], font = "GameFontNormalLarge", r = 1, g = 0.82, b = 0, pad = 10 },
		{ text = L["GUIDE_DR_INTRO"], pad = 12 },
		{ text = L["GUIDE_DR_MATH"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 6 },
		{ text = L["GUIDE_DR_MATH_BODY"], pad = 12 },
		{ text = L["GUIDE_DR_TABLE"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 6 },
	}

	for _, key in ipairs(ns.DR.STAT_ORDER) do
		local bp = ns.DR.GetBreakpoints(key, specEntry)
		if bp then
			lines[#lines + 1] = {
				text = format(
					L["GUIDE_DR_ROW"],
					ns.StatLabel(key),
					ns.DR.FormatRating(bp[1]),
					ns.DR.FormatRating(bp[2]),
					ns.DR.FormatRating(bp[3])
				),
				pad = 4,
				r = 0.9,
				g = 0.9,
				b = 0.9,
			}
		end
	end

	lines[#lines + 1] = { text = L["GUIDE_DR_EXAMPLE"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 10 }
	lines[#lines + 1] = { text = L["GUIDE_DR_EXAMPLE_BODY"], pad = 12 }
	lines[#lines + 1] = { text = L["GUIDE_DR_LIVE"], font = "GameFontNormal", r = 1, g = 0.82, b = 0, pad = 6 }

	local anyLive = false
	for _, key in ipairs(ns.DR.STAT_ORDER) do
		local live = ns.DR.DescribeLive(key, specEntry)
		if live and live.rating then
			anyLive = true
			local nextBit = live.nextNeed
					and format(L["GUIDE_DR_LIVE_NEXT"], ns.DR.FormatRating(live.nextNeed), live.nextLabel)
				or L["DR_NEXT_DONE"]
			lines[#lines + 1] = {
				text = format(
					L["GUIDE_DR_LIVE_ROW"],
					ns.StatShort(key),
					ns.DR.FormatRating(live.rating),
					live.trueRating and ns.DR.FormatTrueRating(live.trueRating) or "-",
					live.lostRating and ns.DR.FormatTrueRating(live.lostRating) or "0",
					L[live.statusKey],
					nextBit
				),
				pad = 4,
				r = live.color[1],
				g = live.color[2],
				b = live.color[3],
			}
		elseif live and live.secret then
			anyLive = true
			lines[#lines + 1] = { text = L["DR_SECRET"], pad = 6, r = 0.55, g = 0.55, b = 0.55 }
			break
		end
	end
	if not anyLive then
		lines[#lines + 1] = { text = L["GUIDE_DR_LIVE_EMPTY"], pad = 8, r = 0.65, g = 0.65, b = 0.65 }
	end

	lines[#lines + 1] = { text = L["GUIDE_DR_NOTE"], pad = 12, r = 0.65, g = 0.65, b = 0.65 }
	return lines
end

function ns.UI.RefreshGuidePages(panel, specEntry)
	if not panel or not panel.pageHowto then
		return
	end

	local width = max(GUIDE_WIDTH, (panel:GetWidth() or GUIDE_FALLBACK_WIDTH) - 36)
	local howtoH = LayoutParagraphs(panel.pageHowto.child, BuildHowtoLines(), width)
	panel.pageHowto.child:SetWidth(width)
	panel.pageHowto.child:SetHeight(howtoH)

	local drH = LayoutParagraphs(panel.pageDR.child, BuildDRLines(specEntry), width)
	panel.pageDR.child:SetWidth(width)
	panel.pageDR.child:SetHeight(drH)
end

function ns.UI.SetPanelTab(panel, tabId, state)
	if not panel or not panel.tabs then
		return
	end
	state.tab = tabId or "priority"

	for id, btn in pairs(panel.tabs) do
		if btn.SetActive then
			btn:SetActive(id == state.tab)
		end
	end

	local isPriority = state.tab == "priority"
	if panel.pagePriority then
		panel.pagePriority:SetShown(isPriority)
	end
	if panel.pageHowto then
		panel.pageHowto:SetShown(state.tab == "howto")
		if state.tab == "howto" and panel.pageHowto.scroll then
			panel.pageHowto.scroll:SetVerticalScroll(0)
		end
	end
	if panel.pageDR then
		panel.pageDR:SetShown(state.tab == "dr")
		if state.tab == "dr" and panel.pageDR.scroll then
			panel.pageDR.scroll:SetVerticalScroll(0)
		end
	end

	-- Class/spec chrome stays. Compare only on Priority.
	if panel.compareBtn and not isPriority then
		panel.compareBtn:Hide()
	end
end

function ns.UI.CreatePanelTabs(panel, state, onTabChanged)
	if panel.tabBar then
		return
	end

	local bar = CreateFrame("Frame", nil, panel)
	bar:SetHeight(TAB_H)
	bar:SetPoint("BOTTOMLEFT", 10, 8)
	bar:SetPoint("BOTTOMRIGHT", -10, 8)
	panel.tabBar = bar

	local labels = {
		priority = L["TAB_PRIORITY"],
		howto = L["TAB_HOWTO"],
		dr = L["TAB_DR"],
	}

	panel.tabs = {}
	local x = 0
	for i = 1, #TAB_IDS do
		local id = TAB_IDS[i]
		local btn = Skin.CreateFlatButton(bar, {
			height = TAB_H,
			minWidth = 90,
			padX = 14,
		})
		btn:SetText(labels[id])
		btn:ClearAllPoints()
		btn:SetPoint("LEFT", bar, "LEFT", x, 0)
		btn:SetScript("OnClick", function()
			if state.tab == id then
				return
			end
			ns.UI.SetPanelTab(panel, id, state)
			if onTabChanged then
				onTabChanged(id)
			end
		end)
		panel.tabs[id] = btn
		x = x + btn:GetWidth() + TAB_GAP
	end

	-- Priority content host (everything between class row and tabs).
	local pagePriority = CreateFrame("Frame", nil, panel)
	pagePriority:SetPoint("TOPLEFT", panel.classBtn, "BOTTOMLEFT", 0, -10)
	pagePriority:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 6)
	panel.pagePriority = pagePriority

	EnsureScrollPage(panel, "pageHowto")
	EnsureScrollPage(panel, "pageDR")

	ns.UI.SetPanelTab(panel, state.tab or "priority", state)
end
