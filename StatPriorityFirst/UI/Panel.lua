--[[
	StatPriorityFirst - Panel
	----
	Flat Wowhead-inspired shell + priority chain (icon · colored name · >> / >).
	Bottom tabs swap Priority / How It Works / Diminishing Returns pages.
--]]

local _, ns = ...
local L = ns.L
local Skin = ns.Skin

ns.UI = ns.UI or {}

local CreateFrame = CreateFrame
local UIParent = UIParent
local format = string.format
local max = math.max
local min = math.min
local floor = math.floor
local tinsert = table.insert
local tconcat = table.concat
local UISpecialFrames = rawget(_G, "UISpecialFrames")

local PANEL_WIDTH = 520
local PANEL_COMPARE_WIDTH = 560
local CHIP_ICON = 20
local CHAIN_HEIGHT = 40
local DROP_MAX_HEIGHT = 220
local DROP_ROW = 24

local panel
local state = {
	classFile = nil,
	specID = nil,
	variantIndex = 1,
	followPlayer = true,
	compare = false,
	tab = "priority",
}

local TAB_BAR_SPACE = 40 -- bottom tabs + padding
local SOURCE_LINK_SPACE = 18 -- Wowhead row above tabs on Priority

local variantButtons = {}
local chainPools = {}

local CLASS_ATLAS = {
	WARRIOR = "classicon-warrior",
	PALADIN = "classicon-paladin",
	HUNTER = "classicon-hunter",
	ROGUE = "classicon-rogue",
	PRIEST = "classicon-priest",
	DEATHKNIGHT = "classicon-deathknight",
	SHAMAN = "classicon-shaman",
	MAGE = "classicon-mage",
	WARLOCK = "classicon-warlock",
	MONK = "classicon-monk",
	DRUID = "classicon-druid",
	DEMONHUNTER = "classicon-demonhunter",
	EVOKER = "classicon-evoker",
}

-- ---
-- Helpers
-- ---

local function ClassColor(classFile)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 0.82, 0
end

local function StatColor(key)
	local c = ns.STAT_COLORS and ns.STAT_COLORS[key]
	if c then
		return c[1], c[2], c[3]
	end
	return 1, 1, 1
end

local function GetEntry(classFile, specID)
	return ns.GetSpecData(classFile, specID)
end

local function PrioritiesDiffer(variants)
	if not variants or #variants < 2 then
		return false
	end
	local function key(p)
		return p and tconcat(p, ",") or ""
	end
	local first = key(variants[1].priority)
	for i = 2, #variants do
		if key(variants[i].priority) ~= first then
			return true
		end
	end
	return false
end

-- Disc/Holy scrapes sometimes duplicate the first two pills with identical chains.
-- Compare should pick the first real disagreeing pair, not [1] vs [2] by index.
local function CompareVariantPair(variants)
	if not variants or #variants < 2 then
		return nil, nil
	end
	local function key(p)
		return p and tconcat(p, ",") or ""
	end
	for i = 1, #variants - 1 do
		local ki = key(variants[i].priority)
		for j = i + 1, #variants do
			if key(variants[j].priority) ~= ki then
				return variants[i], variants[j]
			end
		end
	end
	return variants[1], variants[2]
end

local function EnsureStateFromPlayer()
	local classFile, specID = ns.GetPlayerClassFile(), ns.GetPlayerSpecID()
	if classFile and specID then
		state.classFile = classFile
		state.specID = specID
		return true
	end
	-- Follow-you with no active spec: keep class for chrome, clear invent-a-spec.
	if state.followPlayer then
		if classFile then
			state.classFile = classFile
		end
		state.specID = nil
		return false
	end
	if not state.classFile then
		local file = ns.CatalogOrder[1]
		local c = ns.Catalog[file]
		state.classFile = file
		state.specID = c.specs[1].specID
	end
	return state.specID ~= nil
end

local function ShowEmptyPriority(emptyMsg)
	panel.empty:SetText(emptyMsg)
	panel.empty:Show()
	if panel.hint then
		panel.hint:Hide()
	end
	panel.chainBox:Hide()
	panel.compareFrame:Hide()
	if panel.gearGrid then
		panel.gearGrid:Hide()
	end
	if panel.gearHeader then
		panel.gearHeader:Hide()
		panel.gearHeaderBg:Hide()
		panel.gearRule:Hide()
	end
	panel.priorityHeader:Hide()
	panel.priorityHeaderBg:Hide()
	panel.priorityRule:Hide()
	panel:SetWidth(PANEL_WIDTH)
	panel:SetHeight(220 + TAB_BAR_SPACE)
	if state.tab ~= "priority" then
		panel:SetHeight(max(panel:GetHeight() or 0, 460))
	end
end

local function RestoreLastBrowsed()
	local key = ns.db and ns.db.lastKey
	if not key then
		return false
	end
	local classFile, specID = key:match("^([A-Z]+)%-(%d+)$")
	specID = tonumber(specID)
	if classFile and specID and ns.Catalog[classFile] then
		state.classFile = classFile
		state.specID = specID
		state.followPlayer = false
		-- Restore last build tab if it still exists on this spec.
		state.variantIndex = 1
		local entry = GetEntry(classFile, specID)
		local want = ns.GetRememberedVariant(classFile, specID)
		if want and entry and entry.variants then
			for i = 1, #entry.variants do
				if entry.variants[i].id == want then
					state.variantIndex = i
					break
				end
			end
		end
		return true
	end
	return false
end

local function ApplyVariantMemory(classFile, specID)
	state.variantIndex = 1
	local entry = GetEntry(classFile, specID)
	local want = ns.GetRememberedVariant(classFile, specID)
	if want and entry and entry.variants then
		for i = 1, #entry.variants do
			if entry.variants[i].id == want then
				state.variantIndex = i
				return
			end
		end
	end
end

local function SelectClassSpec(classFile, specID)
	state.classFile = classFile
	state.specID = specID
	state.followPlayer = false
	state.compare = false
	ApplyVariantMemory(classFile, specID)
	ns.UI.Refresh()
end

function ns.UI.ApplyPanelChrome()
	if not panel then
		return
	end
	local db = ns.db and ns.db.panel
	panel:SetScale((db and db.scale) or 1)
	local locked = db and db.locked
	panel:EnableMouse(not locked)
	panel:SetMovable(not locked)
	if locked then
		panel:RegisterForDrag()
	else
		panel:RegisterForDrag("LeftButton")
	end
end

-- ---
-- Priority chain
-- ---

local function EnsureChainPool(name, parent)
	if chainPools[name] then
		return chainPools[name]
	end
	local pool = { chips = {}, seps = {}, parent = parent }
	chainPools[name] = pool
	return pool
end

local function AcquireChip(pool, i)
	local chip = pool.chips[i]
	if chip then
		return chip
	end
	chip = CreateFrame("Button", nil, pool.parent)
	chip:SetHeight(CHAIN_HEIGHT)
	chip:RegisterForClicks("LeftButtonUp")
	chip:EnableMouse(true)

	-- TGA glyphs are colored + transparent. A solid color plate behind them
	-- (same hue as the glyph) turns Crit/Mastery into featureless blocks.
	chip.iconBg = chip:CreateTexture(nil, "BACKGROUND")
	chip.iconBg:SetSize(CHIP_ICON + 2, CHIP_ICON + 2)
	chip.iconBg:SetPoint("LEFT", 0, 0)
	chip.iconBg:SetColorTexture(0.10, 0.10, 0.11, 1)

	chip.icon = chip:CreateTexture(nil, "ARTWORK")
	chip.icon:SetSize(CHIP_ICON, CHIP_ICON)
	chip.icon:SetPoint("CENTER", chip.iconBg, "CENTER", 0, 0)

	chip.label = chip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	chip.label:SetPoint("LEFT", chip.iconBg, "RIGHT", 5, 0)
	chip.label:SetJustifyH("LEFT")

	chip:SetScript("OnEnter", function(self)
		if self.label and self.statKey then
			local r, g, b = StatColor(self.statKey)
			self.label:SetTextColor(min(1, r + 0.12), min(1, g + 0.12), min(1, b + 0.12))
		end
		if self.statKey and self.specEntry then
			ns.UI.ShowStatTooltip(self, self.specEntry, self.statKey)
		end
	end)
	chip:SetScript("OnLeave", function(self)
		if self.label and self.statKey then
			self.label:SetTextColor(StatColor(self.statKey))
		end
		ns.UI.HideStatTooltip()
	end)

	pool.chips[i] = chip
	return chip
end

local function AcquireSep(pool, i)
	local sep = pool.seps[i]
	if sep then
		return sep
	end
	sep = CreateFrame("Frame", nil, pool.parent)
	sep:SetSize(22, CHAIN_HEIGHT)
	sep.text = sep:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sep.text:SetPoint("CENTER")
	pool.seps[i] = sep
	return sep
end

local function HideChain(pool)
	if not pool then
		return
	end
	for i = 1, #pool.chips do
		pool.chips[i]:Hide()
	end
	for i = 1, #pool.seps do
		pool.seps[i]:Hide()
	end
end

local function LayoutPriorityChain(pool, priority, entry, anchorFrame, yOffset, gaps)
	HideChain(pool)
	if not priority or #priority == 0 then
		return 0, 0
	end

	local midY = yOffset or -8
	local muted = Skin.Color.textMuted
	local pieces = {}

	for i = 1, #priority do
		local key = priority[i]
		local chip = AcquireChip(pool, i)
		chip.statKey = key
		chip.specEntry = entry

		local iconPath = ns.STAT_ICONS[key]
		if iconPath then
			chip.icon:SetTexture(iconPath)
			chip.icon:SetVertexColor(1, 1, 1)
			chip.icon:Show()
			chip.iconBg:Show()
		else
			chip.icon:Hide()
			chip.iconBg:Hide()
		end

		local r, g, b = StatColor(key)
		chip.label:SetText(ns.StatShort(key))
		chip.label:SetTextColor(r, g, b)

		local textW = chip.label:GetStringWidth() or 40
		local chipW = CHIP_ICON + 2 + 5 + textW + 2
		chip:SetWidth(chipW)
		pieces[#pieces + 1] = { frame = chip, width = chipW }

		if i < #priority then
			local sep = AcquireSep(pool, i)
			local glyph = ns.PrioritySeparator(priority, i, gaps)
			sep.text:SetText(glyph)
			sep.text:SetTextColor(muted[1], muted[2], muted[3])
			local sepW = max(18, (sep.text:GetStringWidth() or 12) + 14)
			sep:SetWidth(sepW)
			pieces[#pieces + 1] = { frame = sep, width = sepW }
		end
	end

	local contentW = 0
	for i = 1, #pieces do
		contentW = contentW + pieces[i].width
	end

	-- Center in the inset, and fall back to a sensible width before first layout pass.
	local parentW = anchorFrame:GetWidth() or 0
	if parentW < 32 then
		parentW = max(PANEL_WIDTH - 28, contentW + 24)
	end
	local startX = max(8, floor((parentW - contentW) / 2))

	local prev
	for i = 1, #pieces do
		local piece = pieces[i]
		piece.frame:ClearAllPoints()
		if not prev then
			piece.frame:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", startX, midY)
		else
			piece.frame:SetPoint("LEFT", prev, "RIGHT", 0, 0)
		end
		piece.frame:Show()
		prev = piece.frame
	end

	return contentW + 16, CHAIN_HEIGHT + 8
end

-- ---
-- Strengths / Weaknesses removed. BiS gear grid lives in UI/GearCards.lua
-- ---

-- ---
-- Variant tabs (active pill = class accent)
-- ---

local function VariantLabel(v)
	if not v then
		return "?"
	end
	local label = v.label or v.id or "?"
	if v.context == "raid" then
		label = label .. " " .. L["CTX_RAID_TAG"]
	elseif v.context == "mythicplus" then
		label = label .. " " .. L["CTX_MPLUS_TAG"]
	end
	return label
end

local function ClearVariantButtons()
	for i = 1, #variantButtons do
		variantButtons[i]:Hide()
	end
end

local function RefreshVariantTabs(entry)
	ClearVariantButtons()
	if not entry or not entry.variants or #entry.variants == 0 then
		panel.variantBar:SetHeight(1)
		panel.compareBtn:Hide()
		return
	end

	local differ = PrioritiesDiffer(entry.variants)
	if differ and state.tab == "priority" then
		panel.compareBtn:Show()
		panel.compareBtn:SetText(state.compare and L["COMPARE_OFF"] or L["COMPARE"])
		panel.compareBtn:SetActive(state.compare)
	else
		panel.compareBtn:Hide()
		if not differ then
			state.compare = false
		end
	end

	local x = 0
	for i = 1, #entry.variants do
		local v = entry.variants[i]
		local btn = variantButtons[i]
		if not btn then
			btn = Skin.CreateFlatButton(panel.variantBar, { height = 24, minWidth = 72, padX = 18 })
			btn:SetScript("OnClick", function(self)
				state.variantIndex = self.variantIndex
				state.followPlayer = false
				state.compare = false
				ns.UI.Refresh()
			end)
			variantButtons[i] = btn
		end
		btn.variantIndex = i
		btn:SetText(VariantLabel(v))
		btn:ClearAllPoints()
		btn:SetPoint("LEFT", panel.variantBar, "LEFT", x, 0)
		btn:Show()
		btn:SetActive((not state.compare) and i == state.variantIndex)
		x = x + btn:GetWidth() + 6
	end
	panel.variantBar:SetHeight(28)
end

-- ---
-- Flat dropdown
-- ---

local dropList
local dropButtons = {}
local dropScrollChild

local function HideDropList()
	if dropList then
		dropList:Hide()
	end
end

local function EnsureDropList()
	if dropList then
		return dropList
	end
	dropList = CreateFrame("Frame", "StatPriorityFirstDropList", panel, "BackdropTemplate")
	dropList:SetFrameStrata("FULLSCREEN_DIALOG")
	dropList:SetFrameLevel(1000)
	Skin.ApplyFlatBackdrop(dropList, Skin.Color.bgPanel, Skin.Color.border)
	dropList:EnableMouse(true)
	dropList:Hide()

	local scroll = CreateFrame("ScrollFrame", nil, dropList)
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	dropList.scroll = scroll

	dropScrollChild = CreateFrame("Frame", nil, scroll)
	dropScrollChild:SetSize(140, 10)
	scroll:SetScrollChild(dropScrollChild)

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local cur = self:GetVerticalScroll() or 0
		local maxScroll = max(0, (dropScrollChild:GetHeight() or 0) - (self:GetHeight() or 0))
		self:SetVerticalScroll(min(maxScroll, max(0, cur - delta * DROP_ROW)))
	end)

	return dropList
end

local function ShowDropList(owner, items)
	local list = EnsureDropList()
	local width = 160
	local y = -2
	local count = #items

	for i = 1, max(count, #dropButtons) do
		local btn = dropButtons[i]
		if not btn then
			btn = CreateFrame("Button", nil, dropScrollChild)
			btn:SetHeight(DROP_ROW)
			btn:EnableMouse(true)
			btn:RegisterForClicks("LeftButtonUp")
			btn.bg = btn:CreateTexture(nil, "BACKGROUND")
			btn.bg:SetAllPoints()
			btn.bg:SetColorTexture(0, 0, 0, 0)
			btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			btn.label:SetPoint("LEFT", 10, 0)
			btn.label:SetPoint("RIGHT", -10, 0)
			btn.label:SetJustifyH("LEFT")
			btn:SetScript("OnEnter", function(self)
				local r, g, b = Skin.GetAccent()
				self.bg:SetColorTexture(r, g, b, 0.35)
			end)
			btn:SetScript("OnLeave", function(self)
				self.bg:SetColorTexture(0, 0, 0, 0)
			end)
			dropButtons[i] = btn
		end

		local item = items[i]
		if item then
			btn.label:SetText(item.text)
			local fn = item.func
			btn:SetScript("OnClick", function()
				HideDropList()
				if fn then
					fn()
				end
			end)
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", dropScrollChild, "TOPLEFT", 0, y)
			btn:SetPoint("TOPRIGHT", dropScrollChild, "TOPRIGHT", 0, y)
			btn:Show()
			y = y - DROP_ROW
			width = max(width, (btn.label:GetStringWidth() or 0) + 28)
		else
			btn:Hide()
		end
	end

	local contentH = count * DROP_ROW + 4
	dropScrollChild:SetSize(width - 8, contentH)
	list:SetSize(width, min(DROP_MAX_HEIGHT, contentH + 8))
	list.scroll:SetVerticalScroll(0)
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
	list:Show()
end

local function BuildClassMenu(owner)
	local items = {}
	for i = 1, #ns.CatalogOrder do
		local file = ns.CatalogOrder[i]
		local c = ns.Catalog[file]
		local classFile = file
		local firstSpecID = c.specs[1].specID
		items[i] = {
			text = ns.GetLocalizedClassName(classFile),
			func = function()
				SelectClassSpec(classFile, firstSpecID)
			end,
		}
	end
	ShowDropList(owner, items)
end

local function BuildSpecMenu(owner)
	local c = ns.Catalog[state.classFile]
	if not c then
		return
	end
	local items = {}
	local classFile = state.classFile
	for i = 1, #c.specs do
		local s = c.specs[i]
		local specID = s.specID
		items[i] = {
			text = ns.GetLocalizedSpecName(specID, s.name),
			func = function()
				SelectClassSpec(classFile, specID)
			end,
		}
	end
	ShowDropList(owner, items)
end

-- ---
-- Refresh
-- ---

-- Keep the DR tab honest while you swap gear with the panel open.
local liveRatingFrame
local liveRatingPending
local itemInfoFrame

local function EnsureLiveRatingEvents(enable)
	if enable then
		if not liveRatingFrame then
			liveRatingFrame = CreateFrame("Frame")
			liveRatingFrame:SetScript("OnEvent", function()
				if not panel or not panel:IsShown() or state.tab ~= "dr" then
					return
				end
				if liveRatingPending then
					return
				end
				liveRatingPending = true
				C_Timer.After(0, function()
					liveRatingPending = false
					if panel and panel:IsShown() and state.tab == "dr" then
						local entry = GetEntry(state.classFile, state.specID)
						ns.UI.RefreshGuidePages(panel, entry)
					end
				end)
			end)
		end
		liveRatingFrame:RegisterEvent("COMBAT_RATING_UPDATE")
		liveRatingFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	elseif liveRatingFrame then
		liveRatingFrame:UnregisterAllEvents()
	end
end

-- BiS icons request item data, then fill textures when the cache catches up.
local function EnsureItemInfoEvents(enable)
	if enable then
		if not itemInfoFrame then
			itemInfoFrame = CreateFrame("Frame")
			itemInfoFrame:SetScript("OnEvent", function()
				if panel and panel:IsShown() and panel.gearGrid then
					ns.UI.RefreshGearIcons(panel.gearGrid)
				end
			end)
		end
		itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	elseif itemInfoFrame then
		itemInfoFrame:UnregisterAllEvents()
	end
end

function ns.UI.Refresh()
	if not panel then
		return
	end

	if state.followPlayer or not state.classFile or not state.specID then
		EnsureStateFromPlayer()
	end

	local classFile, specID = state.classFile, state.specID

	-- Follow-you + unspecced: never invent catalog priority for another class/spec.
	if state.followPlayer and not ns.GetPlayerSpecID() then
		Skin.SetAccentClass(classFile)
		local r, g, b = ClassColor(classFile)
		panel.title:SetText(L["ADDON_NAME"])
		panel.title:SetTextColor(r, g, b)
		local atlas = CLASS_ATLAS[classFile]
		if atlas then
			panel.classIcon:SetAtlas(atlas)
			panel.classIcon:Show()
		else
			panel.classIcon:Hide()
		end
		local className = ns.GetLocalizedClassName(classFile)
		panel.subtitle:SetText(className)
		panel.classBtn:SetText(className)
		panel.specBtn:SetText(L["NO_SPEC_SHORT"])
		panel.updated:SetText("")
		panel.contextNote:Hide()
		panel.sourceURL = nil
		panel.sourceLink:Hide()
		RefreshVariantTabs(nil)
		HideChain(EnsureChainPool("main", panel.chainBox))
		HideChain(EnsureChainPool("cmp1", panel.compareLeft))
		HideChain(EnsureChainPool("cmp2", panel.compareRight))
		ShowEmptyPriority(L["NO_SPEC"])
		ns.UI.SetPanelTab(panel, state.tab, state)
		ns.UI.RefreshGuidePages(panel, nil)
		return
	end

	local _, specInfo = ns.GetCatalogSpec(classFile, specID)
	local entry = GetEntry(classFile, specID)

	-- Accent follows the browsed class (Wowhead pills are class-colored).
	Skin.SetAccentClass(classFile)
	local ar, ag, ab = Skin.GetAccent()
	local accentHex = Skin.GetAccentHex()

	local r, g, b = ClassColor(classFile)
	panel.title:SetText(L["ADDON_NAME"])
	panel.title:SetTextColor(r, g, b)

	local atlas = CLASS_ATLAS[classFile]
	if atlas then
		panel.classIcon:SetAtlas(atlas)
		panel.classIcon:Show()
	else
		panel.classIcon:Hide()
	end

	local className = ns.GetLocalizedClassName(classFile)
	local catalogSpecName = specInfo and specInfo.name
	local specName = ns.GetLocalizedSpecName(specID, catalogSpecName)
	panel.subtitle:SetText(className .. " - " .. specName)
	panel.classBtn:SetText(className)
	panel.specBtn:SetText(specName)

	local muted = Skin.Color.textMuted
	if entry and entry.updated and entry.updated ~= "unknown" then
		panel.updated:SetText(format(L["UPDATED"], entry.updated))
		panel.updated:SetTextColor(muted[1], muted[2], muted[3])
	elseif ns.Data and ns.Data.meta and ns.Data.meta.scrapedAt then
		panel.updated:SetText(format(L["UPDATED"], ns.Data.meta.scrapedAt))
		panel.updated:SetTextColor(muted[1], muted[2], muted[3])
	else
		panel.updated:SetText("")
	end

	if entry and entry.contextNote then
		panel.contextNote:SetText(entry.contextNote)
		panel.contextNote:SetTextColor(ar, ag, ab)
		panel.contextNote:Show()
	else
		panel.contextNote:SetText("")
		panel.contextNote:Hide()
	end

	-- Prefer bis-gear URL when cards exist, else priority guide. Never LaunchURL.
	local copyURL = entry and entry.gear and entry.gear.sourceURL
	if (not copyURL or copyURL == "") and entry then
		copyURL = entry.sourceURL
	end
	if copyURL and copyURL ~= "" then
		panel.sourceURL = copyURL
		panel.sourceLink.text:SetText(format("|cff%s[%s]|r", accentHex, L["COPY_WOWHEAD"]))
		panel.sourceLink:Show()
	else
		panel.sourceURL = nil
		panel.sourceLink:Hide()
	end

	-- Re-tint chrome that was created with a stale accent
	panel.compareLeftTitle:SetTextColor(ar, ag, ab)
	panel.compareRightTitle:SetTextColor(ar, ag, ab)
	if panel.classBtn.RefreshSkin then
		panel.classBtn:RefreshSkin()
		panel.specBtn:RefreshSkin()
		panel.youBtn:RefreshSkin()
		panel.compareBtn:RefreshSkin()
	end
	if panel.tabs then
		for _, btn in pairs(panel.tabs) do
			if btn.RefreshSkin then
				btn:RefreshSkin()
			end
		end
	end

	RefreshVariantTabs(entry)

	local mainPool = EnsureChainPool("main", panel.chainBox)
	local cmp1 = EnsureChainPool("cmp1", panel.compareLeft)
	local cmp2 = EnsureChainPool("cmp2", panel.compareRight)
	HideChain(mainPool)
	HideChain(cmp1)
	HideChain(cmp2)

	if not entry or not entry.variants or #entry.variants == 0 then
		ShowEmptyPriority(L["NO_DATA"])
		ns.UI.SetPanelTab(panel, state.tab, state)
		ns.UI.RefreshGuidePages(panel, entry)
		return
	end
	panel.empty:Hide()
	if panel.hint then
		panel.hint:Show()
	end
	panel.priorityHeader:Show()
	panel.priorityHeaderBg:Show()
	panel.priorityRule:Show()

	if state.variantIndex > #entry.variants then
		state.variantIndex = 1
	end

	local chrome = 178 + panel.variantBar:GetHeight() + TAB_BAR_SPACE + SOURCE_LINK_SPACE
	if panel.contextNote:IsShown() then
		chrome = chrome + 16
	end

	local gearH = 0
	local GEAR_HEADER_SPACE = 26 -- rule + title chip gap (matches Stat Priority section)

	local function PlaceGearSection(anchor)
		-- Same Wowhead section-title trick as Stat Priority: line + chip over it.
		panel.gearRule:ClearAllPoints()
		panel.gearRule:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
		panel.gearRule:SetPoint("TOPRIGHT", panel.pagePriority, "TOPRIGHT", -4, 0)
		panel.gearHeader:ClearAllPoints()
		panel.gearHeader:SetPoint("CENTER", panel.gearRule, "CENTER", 0, 0)
		panel.gearHeaderBg:ClearAllPoints()
		panel.gearHeaderBg:SetPoint("TOPLEFT", panel.gearHeader, "TOPLEFT", -8, 3)
		panel.gearHeaderBg:SetPoint("BOTTOMRIGHT", panel.gearHeader, "BOTTOMRIGHT", 8, -3)
		panel.gearGrid:ClearAllPoints()
		panel.gearGrid:SetPoint("TOPLEFT", panel.gearRule, "BOTTOMLEFT", 0, -12)
		panel.gearGrid:SetPoint("RIGHT", panel.pagePriority, "RIGHT", -4, 0)
		gearH = ns.UI.RefreshGearGrid(panel.gearGrid, entry, panel:GetWidth() - 28)
		if gearH > 0 then
			panel.gearRule:Show()
			panel.gearHeader:Show()
			panel.gearHeaderBg:Show()
			gearH = gearH + GEAR_HEADER_SPACE
		else
			panel.gearRule:Hide()
			panel.gearHeader:Hide()
			panel.gearHeaderBg:Hide()
		end
	end

	if state.compare and PrioritiesDiffer(entry.variants) then
		panel.chainBox:Hide()
		panel.compareFrame:Show()

		local v1, v2 = CompareVariantPair(entry.variants)
		panel.compareLeftTitle:SetText(VariantLabel(v1))
		panel.compareRightTitle:SetText(VariantLabel(v2))

		local gaps1 = v1.gaps or entry.chainGaps
		local gaps2 = v2.gaps or entry.chainGaps
		-- Width first so each pane GetWidth() is real for centering.
		panel:SetWidth(PANEL_COMPARE_WIDTH)
		local w1 = LayoutPriorityChain(cmp1, v1.priority, entry, panel.compareLeft, -6, gaps1)
		local w2 = LayoutPriorityChain(cmp2, v2.priority, entry, panel.compareRight, -6, gaps2)
		local needW = max(PANEL_COMPARE_WIDTH, w1 + 40, w2 + 40)
		if needW > PANEL_COMPARE_WIDTH then
			panel:SetWidth(needW)
			LayoutPriorityChain(cmp1, v1.priority, entry, panel.compareLeft, -6, gaps1)
			LayoutPriorityChain(cmp2, v2.priority, entry, panel.compareRight, -6, gaps2)
		end
		panel.compareFrame:SetHeight(112)
		PlaceGearSection(panel.compareFrame)
		panel:SetHeight(chrome + 132 + gearH)
	else
		panel.compareFrame:Hide()
		panel.chainBox:Show()

		local variant = entry.variants[state.variantIndex]
		local priority = variant.priority or {}
		local gaps = variant.gaps or entry.chainGaps
		panel:SetWidth(PANEL_WIDTH)
		local chainW = LayoutPriorityChain(mainPool, priority, entry, panel.chainBox, -8, gaps)
		local needW = max(PANEL_WIDTH, chainW + 28)
		if needW > PANEL_WIDTH then
			panel:SetWidth(needW)
			LayoutPriorityChain(mainPool, priority, entry, panel.chainBox, -8, gaps)
		end
		panel.chainBox:SetHeight(CHAIN_HEIGHT + 18)
		PlaceGearSection(panel.chainBox)
		panel:SetHeight(chrome + CHAIN_HEIGHT + 56 + gearH)
	end

	-- Guide tabs prefer a readable fixed height, and Priority keeps content-sized height.
	if state.tab ~= "priority" then
		panel:SetHeight(max(panel:GetHeight() or 0, 460))
		panel:SetWidth(max(panel:GetWidth() or 0, PANEL_WIDTH))
	end

	ns.UI.SetPanelTab(panel, state.tab, state)
	ns.UI.RefreshGuidePages(panel, entry)

	if ns.db then
		local variant = entry.variants[state.variantIndex]
		ns.RememberVariant(classFile, specID, variant and variant.id)
	end
end

-- ---
-- Create
-- ---

function ns.UI.CreatePanel()
	if panel then
		return panel
	end

	panel = CreateFrame("Frame", "StatPriorityFirstPanel", UIParent, "BackdropTemplate")
	panel:SetSize(PANEL_WIDTH, 280)
	panel:SetFrameStrata("DIALOG")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:EnableKeyboard(true)
	if panel.SetPropagateKeyboardInput then
		panel:SetPropagateKeyboardInput(true)
	end
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", function(self)
		if ns.db and ns.db.panel and ns.db.panel.locked then
			return
		end
		self:StartMoving()
	end)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if ns.db and ns.db.panel then
			local point, _, relativePoint, x, y = self:GetPoint(1)
			ns.db.panel.point = point
			ns.db.panel.relativePoint = relativePoint or point
			ns.db.panel.x = x
			ns.db.panel.y = y
		end
	end)
	panel:Hide()

	-- ESC closes us the Blizzard way (needs a global name, and we have one).
	if UISpecialFrames then
		local already
		for i = 1, #UISpecialFrames do
			if UISpecialFrames[i] == "StatPriorityFirstPanel" then
				already = true
				break
			end
		end
		if not already then
			tinsert(UISpecialFrames, "StatPriorityFirstPanel")
		end
	end

	Skin.ApplyFlatBackdrop(panel, Skin.Color.bgPanel, Skin.Color.border)

	local db = ns.db and ns.db.panel
	if db and db.point then
		panel:SetPoint(db.point, UIParent, db.relativePoint or db.point, db.x or 0, db.y or 0)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end

	panel.classIcon = panel:CreateTexture(nil, "ARTWORK")
	panel.classIcon:SetSize(28, 28)
	panel.classIcon:SetPoint("TOPLEFT", 14, -12)

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("LEFT", panel.classIcon, "RIGHT", 8, 0)

	panel.close = Skin.CreateCloseButton(panel)
	panel.close:SetPoint("TOPRIGHT", -10, -10)
	panel.close:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["CLOSE"])
		GameTooltip:Show()
	end)
	panel.close:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	panel.close:SetScript("OnClick", function()
		HideDropList()
		panel:Hide()
	end)

	panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.subtitle:SetPoint("TOPLEFT", panel.classIcon, "BOTTOMLEFT", 0, -8)
	local t = Skin.Color.text
	panel.subtitle:SetTextColor(t[1], t[2], t[3])

	panel.updated = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.updated:SetPoint("TOPLEFT", panel.subtitle, "BOTTOMLEFT", 0, -2)

	panel.youBtn = Skin.CreateFlatButton(panel, { height = 24, minWidth = 84, padX = 14, text = L["YOUR_SPEC"] })
	panel.youBtn:SetPoint("TOPRIGHT", panel.close, "TOPLEFT", -6, 0)
	panel.youBtn:SetScript("OnClick", function()
		HideDropList()
		state.followPlayer = true
		state.compare = false
		EnsureStateFromPlayer()
		state.variantIndex = 1
		ns.UI.Refresh()
	end)

	panel.classBtn = Skin.CreateFlatButton(panel, { height = 26, minWidth = 110, padX = 16 })
	panel.classBtn:SetPoint("TOPLEFT", 14, -78)
	panel.classBtn:SetScript("OnClick", function(self)
		if dropList and dropList:IsShown() and dropList.owner == self then
			HideDropList()
			return
		end
		BuildClassMenu(self)
		if dropList then
			dropList.owner = self
		end
	end)

	panel.specBtn = Skin.CreateFlatButton(panel, { height = 26, minWidth = 120, padX = 16 })
	panel.specBtn:SetPoint("LEFT", panel.classBtn, "RIGHT", 6, 0)
	panel.specBtn:SetScript("OnClick", function(self)
		if dropList and dropList:IsShown() and dropList.owner == self then
			HideDropList()
			return
		end
		BuildSpecMenu(self)
		if dropList then
			dropList.owner = self
		end
	end)

	panel.compareBtn = Skin.CreateFlatButton(panel, { height = 26, minWidth = 78, padX = 14, text = L["COMPARE"] })
	panel.compareBtn:SetPoint("LEFT", panel.specBtn, "RIGHT", 6, 0)
	panel.compareBtn:Hide()
	panel.compareBtn:SetScript("OnClick", function()
		state.compare = not state.compare
		ns.UI.Refresh()
	end)

	-- Bottom tabs + page hosts (Priority / How It Works / DR).
	ns.UI.CreatePanelTabs(panel, state, function()
		ns.UI.Refresh()
	end)
	local page = panel.pagePriority

	panel.hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.hint:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -2)
	panel.hint:SetText(L["HOVER_HINT"])
	local m = Skin.Color.textMuted
	panel.hint:SetTextColor(m[1], m[2], m[3])

	panel.contextNote = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.contextNote:SetPoint("TOPLEFT", panel.hint, "BOTTOMLEFT", 0, -2)
	panel.contextNote:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	panel.contextNote:SetJustifyH("LEFT")
	panel.contextNote:Hide()

	panel.variantBar = CreateFrame("Frame", nil, page)
	panel.variantBar:SetPoint("TOPLEFT", panel.contextNote, "BOTTOMLEFT", 0, -8)
	panel.variantBar:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	panel.variantBar:SetHeight(28)

	-- Header rule like Wowhead section titles (line + title chip over it)
	panel.priorityRule = page:CreateTexture(nil, "ARTWORK")
	panel.priorityRule:SetDrawLayer("ARTWORK", 0)
	panel.priorityRule:SetColorTexture(Skin.Color.borderSoft[1], Skin.Color.borderSoft[2], Skin.Color.borderSoft[3], 1)
	panel.priorityRule:SetHeight(1)
	panel.priorityRule:SetPoint("TOPLEFT", panel.variantBar, "BOTTOMLEFT", 0, -14)
	panel.priorityRule:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, 0)

	panel.priorityHeaderBg = page:CreateTexture(nil, "ARTWORK")
	panel.priorityHeaderBg:SetDrawLayer("ARTWORK", 1)
	panel.priorityHeaderBg:SetColorTexture(Skin.Color.bgPanel[1], Skin.Color.bgPanel[2], Skin.Color.bgPanel[3], 1)

	panel.priorityHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.priorityHeader:SetPoint("CENTER", panel.priorityRule, "CENTER", 0, 0)
	panel.priorityHeader:SetText("  " .. L["PRIORITY"] .. "  ")
	panel.priorityHeader:SetTextColor(t[1], t[2], t[3])
	panel.priorityHeaderBg:SetPoint("TOPLEFT", panel.priorityHeader, "TOPLEFT", -8, 3)
	panel.priorityHeaderBg:SetPoint("BOTTOMRIGHT", panel.priorityHeader, "BOTTOMRIGHT", 8, -3)

	panel.chainBox = Skin.CreateInset(page)
	panel.chainBox:SetPoint("TOPLEFT", panel.priorityRule, "BOTTOMLEFT", 0, -12)
	panel.chainBox:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	panel.chainBox:SetHeight(CHAIN_HEIGHT + 18)

	-- BiS Gear section title (same line+chip pattern as Stat Priority)
	panel.gearRule = page:CreateTexture(nil, "ARTWORK")
	panel.gearRule:SetDrawLayer("ARTWORK", 0)
	panel.gearRule:SetColorTexture(Skin.Color.borderSoft[1], Skin.Color.borderSoft[2], Skin.Color.borderSoft[3], 1)
	panel.gearRule:SetHeight(1)
	panel.gearRule:SetPoint("TOPLEFT", panel.chainBox, "BOTTOMLEFT", 0, -14)
	panel.gearRule:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, 0)
	panel.gearRule:Hide()

	panel.gearHeaderBg = page:CreateTexture(nil, "ARTWORK")
	panel.gearHeaderBg:SetDrawLayer("ARTWORK", 1)
	panel.gearHeaderBg:SetColorTexture(Skin.Color.bgPanel[1], Skin.Color.bgPanel[2], Skin.Color.bgPanel[3], 1)
	panel.gearHeaderBg:Hide()

	panel.gearHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.gearHeader:SetPoint("CENTER", panel.gearRule, "CENTER", 0, 0)
	panel.gearHeader:SetText("  " .. L["BIS_GEAR"] .. "  ")
	panel.gearHeader:SetTextColor(t[1], t[2], t[3])
	panel.gearHeaderBg:SetPoint("TOPLEFT", panel.gearHeader, "TOPLEFT", -8, 3)
	panel.gearHeaderBg:SetPoint("BOTTOMRIGHT", panel.gearHeader, "BOTTOMRIGHT", 8, -3)
	panel.gearHeader:Hide()

	-- BiS gear cards (Weapons / Trinkets / Consumables / Tier)
	panel.gearGrid = ns.UI.CreateGearGrid(page)
	panel.gearGrid:SetPoint("TOPLEFT", panel.gearRule, "BOTTOMLEFT", 0, -12)
	panel.gearGrid:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	panel.compareFrame = CreateFrame("Frame", nil, page)
	panel.compareFrame:SetPoint("TOPLEFT", panel.priorityRule, "BOTTOMLEFT", 0, -12)
	panel.compareFrame:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	panel.compareFrame:Hide()

	panel.compareLeftTitle = panel.compareFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.compareLeftTitle:SetPoint("TOPLEFT", 2, 0)

	panel.compareRightTitle = panel.compareFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.compareRightTitle:SetPoint("TOPLEFT", 2, -52)

	panel.compareLeft = Skin.CreateInset(panel.compareFrame)
	panel.compareLeft:SetPoint("TOPLEFT", 0, -16)
	panel.compareLeft:SetPoint("RIGHT", 0, 0)
	panel.compareLeft:SetHeight(CHAIN_HEIGHT + 14)

	panel.compareRight = Skin.CreateInset(panel.compareFrame)
	panel.compareRight:SetPoint("TOPLEFT", 0, -68)
	panel.compareRight:SetPoint("RIGHT", 0, 0)
	panel.compareRight:SetHeight(CHAIN_HEIGHT + 14)

	panel.empty = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.empty:SetPoint("TOPLEFT", panel.chainBox, "TOPLEFT", 12, -10)
	panel.empty:SetPoint("RIGHT", page, "RIGHT", -12, 0)
	panel.empty:SetJustifyH("LEFT")
	panel.empty:SetWordWrap(true)
	panel.empty:Hide()

	-- Wowhead lives on the Priority page, just above the tab bar.
	panel.sourceLink = CreateFrame("Button", nil, page)
	panel.sourceLink:SetHeight(16)
	panel.sourceLink:SetFrameLevel((page:GetFrameLevel() or 1) + 5)
	panel.sourceLink:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 2, 2)
	panel.sourceLink:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 2)
	panel.sourceLink.text = panel.sourceLink:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.sourceLink.text:SetAllPoints()
	panel.sourceLink.text:SetJustifyH("LEFT")
	panel.sourceLink:SetScript("OnClick", function()
		local url = panel.sourceURL
		if not url or url == "" then
			return
		end
		ns.UI.ShowCopyURL(url)
	end)
	panel.sourceLink:SetScript("OnEnter", function(self)
		self.text:SetText(format("|cffffffff[%s]|r", L["COPY_WOWHEAD"]))
	end)
	panel.sourceLink:SetScript("OnLeave", function(self)
		self.text:SetText(format("|cff%s[%s]|r", Skin.GetAccentHex(), L["COPY_WOWHEAD"]))
	end)
	panel.sourceLink:Hide()

	panel:SetScript("OnShow", function()
		if state.followPlayer then
			EnsureStateFromPlayer()
		end
		ns.UI.Refresh()
		EnsureLiveRatingEvents(true)
		EnsureItemInfoEvents(true)
	end)
	panel:SetScript("OnHide", function()
		HideDropList()
		EnsureLiveRatingEvents(false)
		EnsureItemInfoEvents(false)
	end)

	if panel.SetPropagateKeyboardInput then
		panel:SetScript("OnKeyDown", function(self, key)
			if key == "ESCAPE" then
				self:SetPropagateKeyboardInput(false)
				HideDropList()
				self:Hide()
			else
				self:SetPropagateKeyboardInput(true)
			end
		end)
	end

	ns.UI.ApplyPanelChrome()
	return panel
end

function ns.UI.Toggle(forceShow)
	ns.UI.CreatePanel()
	if forceShow or not panel:IsShown() then
		if ns.db and ns.db.followPlayerDefault ~= false then
			state.followPlayer = true
		else
			if not RestoreLastBrowsed() then
				state.followPlayer = true
			end
		end
		panel:Show()
	else
		HideDropList()
		panel:Hide()
	end
end

function ns.UI.IsShown()
	return panel and panel:IsShown()
end

-- Character bar + other surfaces want the open panel's build selection.
function ns.UI.GetBrowseState()
	return {
		classFile = state.classFile,
		specID = state.specID,
		variantIndex = state.variantIndex,
		followPlayer = state.followPlayer,
		panelOpen = panel and panel:IsShown() or false,
	}
end

function ns.UI.ShowSpec(classFile, specID)
	ns.UI.CreatePanel()
	SelectClassSpec(classFile, specID)
	panel:Show()
end

function ns.UI.OnSpecChanged()
	-- Mid-respec can briefly report no specialization. Debounce so we don't
	-- flash NO_SPEC chrome, and only reset the build tab on a real spec ID swap.
	if ns.UI._specChangeTimer then
		ns.UI._specChangeTimer:Cancel()
	end
	ns.UI._specChangeTimer = C_Timer.NewTimer(0.2, function()
		ns.UI._specChangeTimer = nil
		local newID = ns.GetPlayerSpecID()
		local prev = ns.UI._followSpecID
		ns.UI._followSpecID = newID
		local specChanged = prev ~= newID

		if state.followPlayer and panel and panel:IsShown() then
			EnsureStateFromPlayer()
			if specChanged then
				state.compare = false
				if newID then
					ApplyVariantMemory(state.classFile, newID)
				else
					state.variantIndex = 1
				end
			end
			ns.UI.Refresh()
		end
		if ns.CharacterBar and ns.CharacterBar.Refresh then
			ns.CharacterBar.Refresh()
		end
	end)
end
