--[[
	StatPriorityFirst - Namespace
	----
	Private ns table, secret helpers, stat keys, icon paths.
	Icons are PNGs under assets/ — retail loads them fine from Interface\AddOns.
--]]

local addonName, ns = ...
ns.addonName = addonName
ns.VERSION = "2.0.0"

local L = ns.L
local issecretvalue = rawget(_G, "issecretvalue")
local canaccessvalue = rawget(_G, "canaccessvalue")

function ns.IsSecret(v)
	return issecretvalue and issecretvalue(v)
end

function ns.NotSecret(v)
	return v == nil or not ns.IsSecret(v)
end

function ns.CanAccess(v)
	return not canaccessvalue or canaccessvalue(v)
end

-- ---
-- Stat keys (match scraper + assets)
-- Labels live in Locales — resolve at call time so overlays can translate.
-- ---

ns.STAT_KEYS = { "STR", "AGI", "INT", "CRIT", "HASTE", "MASTERY", "VERS" }

function ns.StatLabel(key)
	if not key then
		return "?"
	end
	return (L and L["STAT_" .. key]) or key
end

function ns.StatShort(key)
	if not key then
		return "?"
	end
	return (L and L["STAT_" .. key .. "_SHORT"]) or ns.StatLabel(key)
end

-- Back-compat tables so chip/tooltip call sites keep working.
ns.STAT_LABELS = setmetatable({}, {
	__index = function(_, key)
		return ns.StatLabel(key)
	end,
})
ns.STAT_SHORT = setmetatable({}, {
	__index = function(_, key)
		return ns.StatShort(key)
	end,
})

-- Classic Wowhead secondary colors (chain text + icon tint feel).
ns.STAT_COLORS = {
	STR = { 0.78, 0.61, 0.43 },
	AGI = { 1.00, 0.82, 0.00 },
	INT = { 0.25, 0.78, 0.92 },
	CRIT = { 0.90, 0.22, 0.22 },
	HASTE = { 0.00, 1.00, 0.50 },
	MASTERY = { 0.69, 0.26, 0.85 },
	VERS = { 0.78, 0.78, 0.78 },
}

local MEDIA = "Interface\\AddOns\\StatPriorityFirst\\assets\\"

ns.STAT_ICONS = {
	STR = MEDIA .. "strength",
	AGI = MEDIA .. "agility",
	INT = MEDIA .. "intellect",
	CRIT = MEDIA .. "critical-strike",
	HASTE = MEDIA .. "haste",
	MASTERY = MEDIA .. "mastery",
	VERS = MEDIA .. "versatility",
}

local PRIMARY = { STR = true, AGI = true, INT = true }

-- Separator after index i (between priority[i] and priority[i+1]).
-- Prefer scraped gaps from overview builds (agi>>crit>mastery); else » after primary.
function ns.PrioritySeparator(priority, index, gaps)
	if gaps and gaps[index] then
		return gaps[index]
	end
	local cur = priority and priority[index]
	if cur and PRIMARY[cur] then
		return ">>"
	end
	return ">"
end

ns.DEFAULTS = {
	minimap = { hide = false, angle = 220 },
	panel = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0, scale = 1, locked = false },
	characterBar = { hide = false }, -- SettingsFrameTemplate strip above CharacterFrame
	drTooltips = { showOnItems = false }, -- append (true N) on item secondary lines
	followPlayerDefault = true, -- open to Your Spec; false = last browsed
	lastKey = nil,
	lastVariant = nil, -- legacy; prefer lastVariantByKey
	lastVariantByKey = {}, -- [CLASS-specID] = variant id — stops Blood→Unholy pill bleed
}

-- Per-spec build memory (shared by panel + Character bar).
function ns.GetRememberedVariant(classFile, specID)
	if not classFile or not specID or not ns.db then
		return nil
	end
	local key = ns.DataKey(classFile, specID)
	local byKey = ns.db.lastVariantByKey
	if byKey and byKey[key] then
		return byKey[key]
	end
	-- One-shot migrate of the old global lastVariant when lastKey matches.
	if ns.db.lastKey == key and ns.db.lastVariant then
		return ns.db.lastVariant
	end
	return nil
end

function ns.RememberVariant(classFile, specID, variantID)
	if not classFile or not specID or not ns.db then
		return
	end
	local key = ns.DataKey(classFile, specID)
	ns.db.lastKey = key
	ns.db.lastVariant = variantID
	ns.db.lastVariantByKey = ns.db.lastVariantByKey or {}
	if variantID then
		ns.db.lastVariantByKey[key] = variantID
	end
end

-- Filled by Data/*.lua
ns.Catalog = ns.Catalog or {}
ns.Data = ns.Data or { meta = {}, specs = {} }

_G.StatPriorityFirst = ns
