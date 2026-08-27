--[[
	StatPriorityFirst - Init
	----
	ADDON_LOADED → SavedVariables. PLAYER_LOGIN → UI + slash.
	Do not touch UnitName / spec at file load.
--]]

local addonName, ns = ...
local L = ns.L

local function CopyDefaults(src, dst)
	if type(src) ~= "table" then
		return src
	end
	dst = dst or {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local function OnLoad()
	StatPriorityFirstDB = CopyDefaults(ns.DEFAULTS, StatPriorityFirstDB)
	ns.db = StatPriorityFirstDB
end

local function CountMissingDR()
	local specs = ns.Data and ns.Data.specs
	if not specs then
		return 0, 0
	end
	local total, missing = 0, 0
	for _, entry in pairs(specs) do
		total = total + 1
		local dr = entry.dr
		local empty = true
		if dr then
			for _, vals in pairs(dr) do
				if type(vals) == "table" and #vals > 0 then
					empty = false
					break
				end
			end
		end
		if empty then
			missing = missing + 1
		end
	end
	return total, missing
end

local function PrintStatus()
	local meta = ns.Data and ns.Data.meta or {}
	local total, missing = CountMissingDR()
	if meta.specCount then
		total = meta.specCount
	end
	if meta.missingDR ~= nil then
		missing = meta.missingDR
	end
	local missingGear = meta.missingGear
	if missingGear == nil then
		missingGear = 0
		local specs = ns.Data and ns.Data.specs
		if specs then
			for _, entry in pairs(specs) do
				local cards = entry.gear and entry.gear.cards
				if not cards or #cards == 0 then
					missingGear = missingGear + 1
				end
			end
		end
	end
	local scraped = meta.scrapedAt or "unknown"
	print("|cff33ff99" .. L["ADDON_NAME"] .. "|r " .. string.format(L["STATUS_LINE"], total, scraped, missing, missingGear))
	if meta.patch then
		print("  " .. string.format(L["STATUS_PATCH"], tostring(meta.patch), tostring(ns.VERSION)))
	end
end

local function OnLogin()
	-- Panel is lazy-created on first /spf or ShowSpec — no need at login.
	if ns.CharacterBar and ns.CharacterBar.Init then
		ns.CharacterBar.Init()
	end
	if ns.Minimap and ns.Minimap.Init then
		ns.Minimap.Init()
	end
	if ns.Settings and ns.Settings.Register then
		ns.Settings.Register()
	end
	if ns.ItemTooltip and ns.ItemTooltip.Init then
		ns.ItemTooltip.Init()
	end
end

-- ---
-- Slash
-- ---

local function NormalizeToken(s)
	return (s or ""):lower():gsub("[%s%-%_]", "")
end

local function FindClassByToken(token)
	token = NormalizeToken(token)
	for i = 1, #ns.CatalogOrder do
		local file = ns.CatalogOrder[i]
		local c = ns.Catalog[file]
		if NormalizeToken(file) == token or NormalizeToken(c.name) == token or NormalizeToken(c.slug) == token then
			return file, c
		end
	end
	return nil
end

local function FindSpecByToken(classInfo, token)
	token = NormalizeToken(token)
	for i = 1, #classInfo.specs do
		local s = classInfo.specs[i]
		if NormalizeToken(s.name) == token or NormalizeToken(s.slug) == token or tostring(s.specID) == token then
			return s
		end
	end
	return nil
end

SLASH_STATPRIORITYFIRST1 = "/spf"
SLASH_STATPRIORITYFIRST2 = "/statpriority"
SlashCmdList.STATPRIORITYFIRST = function(msg)
	msg = (msg or ""):match("^%s*(.-)%s*$") or ""
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and cmd:lower() or ""

	if cmd == "" or cmd == "toggle" then
		ns.UI.Toggle()
		return
	end

	if cmd == "help" or cmd == "?" then
		print(L["SLASH_HELP"])
		return
	end

	if cmd == "refresh" or cmd == "me" or cmd == "self" then
		local classFile, specID = ns.GetPlayerClassFile(), ns.GetPlayerSpecID()
		if classFile and specID then
			ns.UI.ShowSpec(classFile, specID)
		else
			ns.UI.Toggle(true)
		end
		return
	end

	if cmd == "status" or cmd == "qa" then
		PrintStatus()
		return
	end

	-- /spf <class> <spec>
	local classFile, classInfo = FindClassByToken(cmd)
	if classFile then
		local spec = FindSpecByToken(classInfo, rest)
		if not spec and rest == "" and #classInfo.specs > 0 then
			spec = classInfo.specs[1]
		end
		if spec then
			ns.UI.ShowSpec(classFile, spec.specID)
			return
		end
	end

	print(L["SLASH_HELP"])
end

-- ---
-- Events
-- ---

local eventFrame = CreateFrame("Frame")

local handlers = {}

handlers.ADDON_LOADED = function(loaded)
	if loaded == addonName then
		OnLoad()
		return
	end
	-- Settings may LOD in after us — finish registration if we bailed at login.
	if loaded == "Blizzard_Settings" and ns.Settings and not ns.Settings.registered then
		ns.Settings.Register()
	end
end

handlers.PLAYER_LOGIN = function()
	OnLogin()
end

-- ACTIVE_* is the modern player-spec signal; skip PLAYER_SPECIALIZATION_CHANGED
-- so we don't double-refresh on every talent swap.
handlers.ACTIVE_PLAYER_SPECIALIZATION_CHANGED = function()
	if ns.UI and ns.UI.OnSpecChanged then
		ns.UI.OnSpecChanged()
	end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler then
		handler(...)
	end
end)
