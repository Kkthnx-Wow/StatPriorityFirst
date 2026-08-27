-- Luacheck config for StatPriorityFirst (WoW Retail, Midnight 12.1.0 / Lua 5.1).
-- Run:  luacheck Core UI Locales   (Data/Priorities.lua is generated, skip it)
--
-- WoW ships a modified Lua 5.1. We declare the Blizzard globals we touch as
-- read-only so luacheck stops flagging every C_* call, and mark our own
-- SavedVariables / slash globals as writable. Declaring a namespace table
-- (e.g. C_Item) whitelists field access on it. Every entry is verified against
-- Resources 12.1.0.

std = "lua51"
max_line_length = 200

-- 212 unused self/event on handlers, 431/432/412 shadowing, 631/621 formatting.
ignore = { "212", "431", "432", "412", "631", "621" }

-- Generated data and third-party dumps are not ours to lint.
exclude_files = { "Data/Priorities.lua", "tools/**", ".git/**/*.lua" }

-- Globals we create (SavedVariables, slash handlers, XML-referenced mixin).
globals = {
	"StatPriorityFirstDB",
	"SLASH_STATPRIORITYFIRST1",
	"SLASH_STATPRIORITYFIRST2",
	"SlashCmdList",
	"StatPriorityFirstSettingsDescriptionMixin",
}

-- Blizzard API surface we read. Namespace tables cover their methods.
read_globals = {
	-- Lua/WoW helpers Blizzard adds to the global env
	"format", "gsub", "ipairs", "next", "pairs", "pcall", "print",
	"tinsert", "tonumber", "tostring", "unpack", "wipe", "select",
	"hooksecurefunc", "GetLocale",

	-- Frames / UI
	"CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip",
	"Minimap", "CharacterFrame", "PaperDollFrame", "GetCursorPosition",
	"GetMinimapShape", "BreakUpLargeNumbers",

	-- Settings API
	"Settings", "CreateSettingsListSectionHeaderInitializer",
	"MinimalSliderWithSteppersMixin",

	-- Tooltip data API
	"TooltipDataProcessor", "TooltipUtil",

	-- Player / stat info
	"UnitClass", "UnitLevel", "GetCombatRating", "GetCritChance",
	"GetRangedCritChance", "GetSpellCritChance",
	"GetSpecializationInfoForSpecID", "GetSpecializationNameForSpecID",

	-- Constants
	"ITEM_QUALITY_COLORS", "RAID_CLASS_COLORS", "MAX_SPELL_SCHOOLS",
	"STAT_CRITICAL_STRIKE", "STAT_HASTE", "STAT_MASTERY", "STAT_VERSATILITY",

	-- Deprecated globals kept for pre-12.x fallback paths
	"GetItemIcon", "GetItemInfo", "LoadAddOn",

	-- C_* namespaces (fields whitelisted automatically)
	"C_AddOns", "C_Item", "C_Secrets", "C_SpecializationInfo",
	"C_Spell", "C_Timer", "Enum",

	-- Optional companion suites (soft-skin hooks)
	"ElvUI", "EllesmereUIDB",
}
