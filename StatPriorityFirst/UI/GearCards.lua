--[[
	StatPriorityFirst - Gear / BiS rows
	----
	Stacked full-width sections under the priority chain: Weapons, Trinkets,
	Consumables, Tier Set. Fixed 32px icons; BiS | Alternatives when both exist;
	single-side picks (e.g. consumables) are a centered icon row with no footer.

	Data stores itemID + optional Wowhead bonus IDs. SetHyperlink with bonuses
	for Myth-track tooltips. Icons get a 1px quality border.
--]]

local _, ns = ...
local L = ns.L
local Skin = ns.Skin

ns.UI = ns.UI or {}

local CreateFrame = CreateFrame
local format = string.format
local max = math.max
local min = math.min
local floor = math.floor
local tconcat = table.concat
local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemQualityByID = C_Item and C_Item.GetItemQualityByID
local GetItemQualityColor = C_Item and C_Item.GetItemQualityColor
local ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS
local GameTooltip = GameTooltip

local ICON = 32
local ICON_GAP = 6
local ROW_PAD = 8
local HEADER_H = 22
local FOOTER_H = 16
local SECTION_GAP = 8
local SPLIT_GAP = 16

local CARD_ORDER = { "weapons", "trinkets", "consumables", "tier" }

local CARD_LOCALE = {
	weapons = "GEAR_WEAPONS",
	trinkets = "GEAR_TRINKETS",
	consumables = "GEAR_CONSUMABLES",
	tier = "GEAR_TIER",
}

-- Gear bonus handling.
-- ----
-- Through Season 1 we stamped a hardcoded Myth-track pair (bonus=12806:13335)
-- onto bare item IDs so tooltips showed Myth 6/6 ilvl instead of the base item.
-- Those IDs are season-specific and expire each patch, and Season 2's BiS slot
-- tables no longer expose a single reliable track:rank pair on the page. Rather
-- than invent a pair (and mis-stamp every tooltip on a bad guess), we trust the
-- scraped data: whatever bonuses the guide listed pass through untouched, and
-- bare items render as their real base item (correct name / icon / quality from
-- the in-game item API). No hardcoded season constant to rot.

local function ParseItemRef(ref)
	if type(ref) == "number" then
		return ref, nil
	end
	if type(ref) == "table" and ref[1] then
		local itemID = ref[1]
		local bonuses
		if #ref > 1 then
			bonuses = {}
			for i = 2, #ref do
				bonuses[#bonuses + 1] = ref[i]
			end
		end
		return itemID, bonuses
	end
	return nil, nil
end

-- Pass scraped bonuses straight through. Bare items stay bare (base tooltip).
local function NormalizeGearBonuses(bonuses)
	if not bonuses or #bonuses == 0 then
		return nil
	end
	return bonuses
end

local function ItemHyperlink(itemID, bonuses)
	if not itemID then
		return nil
	end
	if not bonuses or #bonuses == 0 then
		return format("item:%d", itemID)
	end
	-- item:ID + 11 empty fields + numBonusIDs + bonusIDs… (ItemLink layout).
	return format("item:%d::::::::::::%d:%s", itemID, #bonuses, tconcat(bonuses, ":"))
end

local function ItemIcon(itemID)
	if not itemID then
		return nil
	end
	if GetItemIcon then
		local tex = GetItemIcon(itemID)
		if tex then
			return tex
		end
	end
	if GetItemInfo then
		local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
		return texture
	end
	return nil
end

-- Bonus-aware quality only. Bare-ID fallback paints Myth epics as uncommon green
-- and, worse, a wrong non-nil quality skips RequestLoad forever.
local function ItemQuality(itemID, bonuses)
	if not itemID then
		return nil
	end
	local link = ItemHyperlink(itemID, bonuses)
	if GetItemQualityByID and link then
		local q = GetItemQualityByID(link)
		if q ~= nil then
			return q
		end
	end
	if GetItemInfo and link then
		local _, _, quality = GetItemInfo(link)
		if quality ~= nil then
			return quality
		end
	end
	-- No bonuses → base ID is the truth (consumables, crafts without upgrades).
	if not bonuses or #bonuses == 0 then
		if GetItemQualityByID then
			local q = GetItemQualityByID(itemID)
			if q ~= nil then
				return q
			end
		end
		if GetItemInfo then
			local _, _, quality = GetItemInfo(itemID)
			return quality
		end
	end
	return nil
end

local function PaintQualityBorder(btn, itemID, bonuses)
	local soft = Skin.Color.borderSoft
	local r, g, b, a = soft[1], soft[2], soft[3], soft[4] or 1
	local quality = ItemQuality(itemID, bonuses)
	if quality ~= nil then
		if GetItemQualityColor then
			local qr, qg, qb = GetItemQualityColor(quality)
			if qr then
				r, g, b, a = qr, qg, qb, 1
			end
		elseif ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
			local c = ITEM_QUALITY_COLORS[quality]
			r, g, b, a = c.r, c.g, c.b, 1
		end
	elseif itemID and C_Item and C_Item.RequestLoadItemDataByID then
		-- Soft border until GET_ITEM_INFO_RECEIVED repaints with link quality.
		C_Item.RequestLoadItemDataByID(itemID)
	end
	btn:SetBackdropBorderColor(r, g, b, a)
end

local function PaintIconFace(btn, itemID, bonuses)
	local tex = ItemIcon(itemID)
	if tex then
		btn.tex:SetTexture(tex)
		btn.tex:SetVertexColor(1, 1, 1, 1)
	else
		btn.tex:SetColorTexture(0.2, 0.2, 0.22, 1)
	end
	-- Always bounce load when quality isn't resolved yet (texture cache ≠ quality cache).
	if itemID and C_Item and C_Item.RequestLoadItemDataByID and ItemQuality(itemID, bonuses) == nil then
		C_Item.RequestLoadItemDataByID(itemID)
	end
	PaintQualityBorder(btn, itemID, bonuses)
end

local function FitCols(availW)
	return max(1, floor((availW + ICON_GAP) / (ICON + ICON_GAP)))
end

local function RowsForCount(count, cols)
	if count <= 0 then
		return 0
	end
	return math.ceil(count / max(1, cols))
end

local function BlockHeight(rows)
	if rows <= 0 then
		return 0
	end
	return rows * ICON + (rows - 1) * ICON_GAP
end

-- Always 50/50. Count-weighted splits shoved Tier Alts into a sliver (4+1).
local function SplitColumnWidths(rowW)
	local hostPad = 6
	local inner = rowW - ROW_PAD * 2 - SPLIT_GAP
	local bisW = floor(inner / 2)
	local altW = inner - bisW
	return bisW, altW, hostPad
end

local function SectionIconRows(data, rowW)
	local bis = (data and data.bis) or {}
	local alts = (data and data.alternatives) or {}
	if #bis == 0 and #alts == 0 then
		return 1
	end
	if #alts == 0 then
		return max(1, RowsForCount(#bis, FitCols(rowW - ROW_PAD * 2)))
	end
	local bisW, altW, hostPad = SplitColumnWidths(rowW)
	local bisRows = RowsForCount(#bis, FitCols(max(1, bisW - hostPad)))
	local altRows = RowsForCount(#alts, FitCols(max(1, altW - hostPad)))
	return max(1, bisRows, altRows)
end

local function SectionHeight(data, rowW)
	local rows = SectionIconRows(data, rowW)
	local hasAlts = data and data.alternatives and #data.alternatives > 0
	local hasAny = data and ((data.bis and #data.bis > 0) or hasAlts)
	-- Single-side rows skip the BiS/Alts footer (consumables-style).
	local footer = (hasAny and hasAlts) and FOOTER_H or 4
	return HEADER_H + BlockHeight(rows) + footer + 8
end

local function AcquireIcon(pool, parent, i)
	local btn = pool[i]
	if btn then
		return btn
	end
	btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
	btn:SetSize(ICON, ICON)
	btn:EnableMouse(true)
	Skin.ApplyFlatBackdrop(btn, Skin.Color.bgInset, Skin.Color.borderSoft)
	btn.tex = btn:CreateTexture(nil, "ARTWORK")
	btn.tex:SetPoint("TOPLEFT", 1, -1)
	btn.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	btn.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	btn:SetScript("OnEnter", function(self)
		if not self.itemID then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local link = ItemHyperlink(self.itemID, self.bonuses)
		if link then
			GameTooltip:SetHyperlink(link)
		else
			GameTooltip:SetItemByID(self.itemID)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	pool[i] = btn
	return btn
end

local function LayoutIconGrid(pool, parent, refs, startY, forcedW, isGear)
	local n = refs and #refs or 0
	for i = 1, #pool do
		pool[i]:Hide()
	end
	if n == 0 then
		return 0
	end

	-- Prefer the width we just SetSize'd. GetWidth() can lag a frame and under-size the row.
	local availW = max(1, forcedW or parent:GetWidth() or 200)
	local cols = FitCols(availW)
	local rows = RowsForCount(n, cols)
	local gap = ICON_GAP
	local top = startY or 0

	for i = 1, n do
		local itemID, bonuses = ParseItemRef(refs[i])
		-- Gear refs: pass scraped bonuses through, bare items stay bare.
		if isGear then
			bonuses = NormalizeGearBonuses(bonuses)
		end
		local btn = AcquireIcon(pool, parent, i)
		btn.itemID = itemID
		btn.bonuses = bonuses
		btn:SetSize(ICON, ICON)
		PaintIconFace(btn, itemID, bonuses)

		local col = (i - 1) % cols
		local row = floor((i - 1) / cols)
		local thisRowCount = min(cols, n - row * cols)
		local thisRowW = thisRowCount * ICON + (thisRowCount - 1) * gap
		local x = max(0, (availW - thisRowW) / 2) + col * (ICON + gap)
		local y = top - row * (ICON + gap)

		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		btn:Show()
	end
	return BlockHeight(rows)
end

local function EnsureSection(host, index)
	local row = host.cards[index]
	if row then
		return row
	end

	-- Flat section, no card box. Title + icons + optional BiS|Alts split.
	row = CreateFrame("Frame", nil, host)
	-- Don't clip. Under-measured hosts were chewing icon edges and looking "small".
	row:SetClipsChildren(false)

	row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.header:SetJustifyH("CENTER")

	row.link = CreateFrame("Button", nil, row)
	row.link:SetSize(16, 16)
	row.link.text = row.link:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.link.text:SetAllPoints()
	row.link.text:SetText("↗")
	-- Mockup uses class-accent-ish purple, and we keep the copy-link red cue for affordance.
	row.link.text:SetTextColor(0.95, 0.35, 0.35)
	row.link:SetScript("OnClick", function(self)
		if self.url and ns.UI.ShowCopyURL then
			ns.UI.ShowCopyURL(self.url)
		end
	end)
	row.link:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["COPY_GEAR_LINK"])
		GameTooltip:Show()
	end)
	row.link:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	row.bisHost = CreateFrame("Frame", nil, row)
	row.altHost = CreateFrame("Frame", nil, row)

	row.divider = row:CreateTexture(nil, "ARTWORK")
	row.divider:SetWidth(1)

	row.bisLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.bisLabel:SetJustifyH("CENTER")
	row.altLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.altLabel:SetJustifyH("CENTER")

	row.emptyHint = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	row.emptyHint:SetText(L["GEAR_EMPTY"] or "-")
	row.emptyHint:Hide()

	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetHeight(1)
	row.rule:SetColorTexture(Skin.Color.borderSoft[1], Skin.Color.borderSoft[2], Skin.Color.borderSoft[3], 0.7)

	row.bisIcons = {}
	row.altIcons = {}
	host.cards[index] = row
	return row
end

local function ResolveCardURL(data, gear)
	if not gear then
		return nil
	end
	if data and data.id == "consumables" then
		local cons = gear.consumablesURL
		if cons and cons ~= "" then
			return cons
		end
	end
	return gear.sourceURL
end

local function PaintSection(row, data, gear, width, height, showRule)
	row:SetSize(width, height)

	local titleKey = CARD_LOCALE[data.id]
	local title = (titleKey and L[titleKey]) or data.label or data.id
	row.header:SetText(title)
	local t = Skin.Color.text
	row.header:SetTextColor(t[1], t[2], t[3])
	row.header:ClearAllPoints()
	row.header:SetPoint("TOP", 0, -2)

	local cardURL = ResolveCardURL(data, gear)
	row.link.url = cardURL
	row.link:ClearAllPoints()
	row.link:SetPoint("LEFT", row.header, "RIGHT", 4, 0)
	if cardURL and cardURL ~= "" then
		row.link:Show()
	else
		row.link:Hide()
	end

	local bis = data.bis or {}
	local alts = data.alternatives or {}
	local hasAlts = #alts > 0
	local hasAny = #bis > 0 or hasAlts
	-- Weapons / Trinkets / Tier are Myth-track gear. Consumables are not.
	local isGear = data.id ~= "consumables"
	local contentTop = -HEADER_H
	local footer = hasAlts and FOOTER_H or 4
	local iconAreaH = max(ICON + 4, height - HEADER_H - footer - 4)

	if showRule then
		row.rule:ClearAllPoints()
		row.rule:SetPoint("BOTTOMLEFT", ROW_PAD, 0)
		row.rule:SetPoint("BOTTOMRIGHT", -ROW_PAD, 0)
		row.rule:Show()
	else
		row.rule:Hide()
	end

	if not hasAny then
		row.bisHost:Hide()
		row.altHost:Hide()
		row.divider:Hide()
		row.bisLabel:Hide()
		row.altLabel:Hide()
		for i = 1, #row.bisIcons do
			row.bisIcons[i]:Hide()
		end
		for i = 1, #row.altIcons do
			row.altIcons[i]:Hide()
		end
		row.emptyHint:ClearAllPoints()
		row.emptyHint:SetPoint("CENTER", 0, -4)
		row.emptyHint:Show()
		row:Show()
		return
	end
	row.emptyHint:Hide()
	row.bisHost:Show()

	local bisHostW, altHostW
	if hasAlts then
		local bisW, altW, hostPad = SplitColumnWidths(width)
		bisHostW = max(1, bisW - hostPad)
		altHostW = max(1, altW - hostPad)

		row.bisHost:ClearAllPoints()
		row.bisHost:SetPoint("TOPLEFT", ROW_PAD, contentTop)
		row.bisHost:SetSize(bisHostW, iconAreaH)
		row.altHost:ClearAllPoints()
		row.altHost:SetPoint("TOPRIGHT", -ROW_PAD, contentTop)
		row.altHost:SetSize(altHostW, iconAreaH)
		row.altHost:Show()

		-- Midline every split row, the same X as Weapons/Trinkets/Tier so columns line up.
		local divX = floor(width / 2)
		local soft = Skin.Color.borderSoft
		row.divider:SetColorTexture(soft[1], soft[2], soft[3], 0.45)
		row.divider:ClearAllPoints()
		row.divider:SetPoint("TOPLEFT", divX, contentTop - 2)
		row.divider:SetPoint("BOTTOMLEFT", divX, footer)
		row.divider:Show()

		row.bisLabel:SetText(L["BIS"])
		row.bisLabel:ClearAllPoints()
		row.bisLabel:SetPoint("BOTTOMLEFT", ROW_PAD, 2)
		row.bisLabel:SetWidth(bisW)
		row.bisLabel:Show()

		-- Narrow split columns can't fit "Alternatives", so use the short tag.
		row.altLabel:SetText((altW < 120 and L["ALTERNATIVES_SHORT"]) or L["ALTERNATIVES"])
		row.altLabel:ClearAllPoints()
		row.altLabel:SetPoint("BOTTOMRIGHT", -ROW_PAD, 2)
		row.altLabel:SetWidth(altW)
		row.altLabel:Show()
	else
		-- Consumables-style: icons only, no Best in Slot footer.
		bisHostW = max(1, width - ROW_PAD * 2)
		row.bisHost:ClearAllPoints()
		row.bisHost:SetPoint("TOPLEFT", ROW_PAD, contentTop)
		row.bisHost:SetSize(bisHostW, iconAreaH)
		row.divider:Hide()
		row.altHost:Hide()
		row.altLabel:Hide()
		row.bisLabel:Hide()
		for i = 1, #row.altIcons do
			row.altIcons[i]:Hide()
		end
	end

	local function CenterOffset(count, hostW)
		local rows = RowsForCount(count, FitCols(max(1, hostW)))
		return -max(0, floor((iconAreaH - BlockHeight(rows)) / 2))
	end
	LayoutIconGrid(row.bisIcons, row.bisHost, bis, CenterOffset(#bis, bisHostW), bisHostW, isGear)
	if hasAlts then
		LayoutIconGrid(row.altIcons, row.altHost, alts, CenterOffset(#alts, altHostW), altHostW, isGear)
	end

	row:Show()
end

local function OrderedCards(raw)
	local byId = {}
	for i = 1, #(raw or {}) do
		local c = raw[i]
		if c and c.id then
			byId[c.id] = c
		end
	end
	local out = {}
	for i = 1, #CARD_ORDER do
		local id = CARD_ORDER[i]
		local c = byId[id]
		out[i] = c
			or {
				id = id,
				label = (CARD_LOCALE[id] and L[CARD_LOCALE[id]]) or id,
				bis = {},
				alternatives = {},
			}
	end
	return out
end

function ns.UI.CreateGearGrid(parent)
	local host = CreateFrame("Frame", nil, parent)
	host.cards = {}
	host:Hide()
	return host
end

function ns.UI.RefreshGearGrid(host, entry, contentWidth)
	if not host then
		return 0
	end

	local gear = entry and entry.gear
	local raw = gear and gear.cards
	if not raw or #raw == 0 then
		host:Hide()
		for i = 1, #host.cards do
			host.cards[i]:Hide()
		end
		return 0
	end

	local cards = OrderedCards(raw)
	local width = max(280, (contentWidth or host:GetWidth() or 480) - 4)
	local totalH = 0
	local heights = {}

	for i = 1, 4 do
		heights[i] = SectionHeight(cards[i], width)
		totalH = totalH + heights[i]
		if i < 4 then
			totalH = totalH + SECTION_GAP
		end
	end

	local y = 0
	for i = 1, 4 do
		local row = EnsureSection(host, i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", host, "RIGHT", 0, 0)
		PaintSection(row, cards[i], gear, width, heights[i], i < 4)
		y = y + heights[i] + SECTION_GAP
	end
	for i = 5, #host.cards do
		host.cards[i]:Hide()
	end

	host:SetHeight(totalH)
	host:SetWidth(width)
	host:Show()
	return totalH + 8
end

function ns.UI.RefreshGearIcons(host)
	if not host or not host:IsShown() then
		return
	end
	for i = 1, #host.cards do
		local row = host.cards[i]
		if row and row:IsShown() then
			for _, pool in ipairs({ row.bisIcons, row.altIcons }) do
				for j = 1, #pool do
					local btn = pool[j]
					if btn:IsShown() and btn.itemID then
						PaintIconFace(btn, btn.itemID, btn.bonuses)
					end
				end
			end
		end
	end
end
