--[[
	StatPriorityFirst - Stat tooltips
	----
	Hover a ranked row → summary, notes, DR breakpoints + live rating compare.
	True/lost rating + a thin bracket meter (no text painted on the fill —
	neon-on-white was a crime). Avoid GameTooltip_InsertFrame; taint city.
	{{spell:ID}} expands via C_Spell at display time.
--]]

local _, ns = ...
local L = ns.L
local Skin = ns.Skin

ns.UI = ns.UI or {}

local GameTooltip = GameTooltip
local format = string.format
local min = math.min
local floor = math.floor
local max = math.max

function ns.ExpandSpellTokens(text, rich)
	if not text or text == "" then
		return text
	end
	return (text:gsub("%{%{spell:(%d+)%}%}", function(id)
		local spellID = tonumber(id)
		local name = L["UNKNOWN_SPELL"]
		if spellID and C_Spell and C_Spell.GetSpellInfo then
			local info = C_Spell.GetSpellInfo(spellID)
			if info and info.name and info.name ~= "" then
				name = info.name
			end
		end
		if rich == "link" then
			local icon
			if C_Spell and C_Spell.GetSpellTexture then
				icon = C_Spell.GetSpellTexture(spellID)
			end
			if icon then
				return format("|Hspell:%s|h|T%s:14:14:0:0:64:64:5:59:5:59|t |cffffd100%s|r|h", id, icon, name)
			end
			return format("|Hspell:%s|h|cffffd100%s|r|h", id, name)
		end
		if rich then
			return format("|cffffd100%s|r", name)
		end
		return name
	end))
end

function ns.UI.ShowSpellTooltip(owner, spellID)
	spellID = tonumber(spellID)
	if not owner or not spellID then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(spellID)
	GameTooltip:Show()
end

function ns.UI.HideSpellTooltip()
	GameTooltip:Hide()
end

-- ---
-- Bracket meter — fill is visual only; numbers live in a normal tooltip line.
-- ---

local BAR_H = 6
local meter

-- Crush band greens/ambers so the fill never screams over the tooltip chrome.
local function MeterFillColor(bandColor)
	local r = (bandColor and bandColor[1]) or 0.4
	local g = (bandColor and bandColor[2]) or 0.7
	local b = (bandColor and bandColor[3]) or 0.4
	return r * 0.42 + 0.10, g * 0.42 + 0.10, b * 0.42 + 0.10, 1
end

local function HideBracketMeter()
	if meter then
		meter:Hide()
	end
end

local function EnsureBracketMeter()
	if meter then
		return meter
	end
	meter = CreateFrame("Frame", nil, GameTooltip)
	meter:SetHeight(BAR_H)
	meter:Hide()

	local track = meter:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0.12, 0.12, 0.14, 1)
	meter.Track = track

	local fill = meter:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT")
	fill:SetPoint("BOTTOMLEFT")
	fill:SetWidth(1)
	meter.Fill = fill

	return meter
end

local function LayoutBracketMeter(tooltip, info)
	if not info.bracketMaxRating or info.bracketMaxRating <= 0 then
		return
	end

	local m = EnsureBracketMeter()
	local maxR = info.bracketMaxRating
	local cur = max(0, min(maxR, info.bracketRating or 0))
	local frac = maxR > 0 and (cur / maxR) or 0
	local fr, fg, fb, fa = MeterFillColor(info.color)
	m.Fill:SetColorTexture(fr, fg, fb, fa)

	-- Numbers as a real tooltip line — always readable, never fighting the fill.
	local penaltyPct = floor((info.bracketPenalty or 0) * 100 + 0.5)
	local muted = Skin.Color.textMuted
	tooltip:AddDoubleLine(
		L["DR_BRACKET"],
		format(
			L["DR_BRACKET_PROGRESS"],
			ns.DR.FormatRating(cur),
			ns.DR.FormatRating(maxR),
			penaltyPct
		),
		muted[1],
		muted[2],
		muted[3],
		0.85,
		0.85,
		0.88
	)

	-- Spacer line the meter sits on (visual only).
	tooltip:AddLine(" ")
	tooltip:Show()

	local numLines = tooltip:NumLines()
	local spacer = _G["GameTooltipTextLeft" .. numLines]
	if not spacer then
		return
	end

	m:SetParent(tooltip)
	m:SetFrameStrata("TOOLTIP")
	m:SetFrameLevel(tooltip:GetFrameLevel() + 1)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", spacer, "TOPLEFT", 0, -2)
	m:SetPoint("RIGHT", tooltip, "RIGHT", -12, 0)
	m:Show()

	-- Width after parent points resolve.
	local w = m:GetWidth() or 0
	if w < 1 then
		w = max(40, (tooltip:GetWidth() or 200) - 24)
	end
	m.Fill:SetWidth(max(1, floor(w * frac + 0.5)))
end

GameTooltip:HookScript("OnHide", HideBracketMeter)

local function AddLiveDRCompare(tooltip, info)
	local br, bg, bb = info.color[1], info.color[2], info.color[3]
	tooltip:AddDoubleLine(
		L["DR_YOU"],
		format(L["DR_RATING"], ns.DR.FormatRating(info.rating)),
		0.75,
		0.85,
		1,
		br,
		bg,
		bb
	)
	if info.trueRating ~= nil then
		tooltip:AddDoubleLine(
			L["DR_TRUE"],
			ns.DR.FormatTrueRating(info.trueRating),
			0.75,
			0.85,
			1,
			br,
			bg,
			bb
		)
		tooltip:AddDoubleLine(
			L["DR_LOST"],
			ns.DR.FormatTrueRating(info.lostRating or 0),
			0.75,
			0.85,
			1,
			0.85,
			0.55,
			0.55
		)
	end
	tooltip:AddLine(L[info.statusKey], br, bg, bb)
	-- Next-breakpoint lines BEFORE the meter — LayoutBracketMeter pins to the
	-- last spacer line; adding text afterward leaves the fill stuck mid-tooltip.
	if info.nextNeed and info.nextLabel then
		tooltip:AddDoubleLine(
			L["DR_NEXT"],
			format(L["DR_NEXT_FMT"], ns.DR.FormatRating(info.nextNeed), info.nextLabel),
			0.7,
			0.7,
			0.7,
			1,
			1,
			1
		)
	else
		tooltip:AddLine(L["DR_NEXT_DONE"], 0.55, 0.55, 0.55)
	end
	LayoutBracketMeter(tooltip, info)
end

local function AddDRLines(tooltip, drVals, statKey, specEntry)
	if not drVals or #drVals == 0 then
		return
	end

	tooltip:AddLine(" ")
	tooltip:AddLine(L["DR_HEADER"], 1, 0.82, 0)

	local live
	if ns.DR.SECONDARY[statKey] then
		live = ns.DR.DescribeLive(statKey, specEntry)
	end

	if live and live.rating then
		AddLiveDRCompare(tooltip, live)
		tooltip:AddLine(" ")
	elseif live and live.secret then
		tooltip:AddLine(L["DR_SECRET"], 0.55, 0.55, 0.55, true)
		tooltip:AddLine(" ")
	end

	local band = (live and live.rating and live.band) or -1
	local labels = { L["DR_10"], L["DR_20"], L["DR_30"] }
	for i = 1, min(3, #drVals) do
		local lr, lg, lb = 0.9, 0.9, 0.9
		local rr, rg, rb = 1, 1, 1
		if band >= 0 then
			if i <= band then
				lr, lg, lb = 0.45, 0.45, 0.45
				rr, rg, rb = 0.45, 0.45, 0.45
			elseif i == band + 1 then
				lr, lg, lb = 0.95, 0.85, 0.25
				rr, rg, rb = 0.95, 0.85, 0.25
			end
		end
		tooltip:AddDoubleLine(
			labels[i],
			format(L["DR_RATING"], ns.DR.FormatRating(drVals[i])),
			lr,
			lg,
			lb,
			rr,
			rg,
			rb
		)
	end

	if not (live and live.rating) then
		tooltip:AddLine(L["DR_TIP"], 0.55, 0.55, 0.55, true)
	end
end

function ns.UI.ShowStatTooltip(owner, specEntry, statKey)
	if not owner or not specEntry or not statKey then
		return
	end

	HideBracketMeter()

	local label = ns.StatLabel(statKey) or statKey
	local info = specEntry.stats and specEntry.stats[statKey]

	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(label, 1, 1, 1)

	if info and info.summary and info.summary ~= "" then
		GameTooltip:AddLine(ns.ExpandSpellTokens(info.summary, true), 0.85, 0.85, 0.85, true)
	end

	if info and info.notes then
		for i = 1, #info.notes do
			local note = info.notes[i]
			if note and note ~= "" then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(ns.ExpandSpellTokens(note, true), 0.7, 0.85, 1, true)
			end
		end
	end

	-- Fall back to Midnight defaults when the scrape left this secondary blank.
	local drVals = ns.DR.GetBreakpoints(statKey, specEntry)
	AddDRLines(GameTooltip, drVals, statKey, specEntry)
	GameTooltip:Show()
end

function ns.UI.HideStatTooltip()
	HideBracketMeter()
	GameTooltip:Hide()
end
