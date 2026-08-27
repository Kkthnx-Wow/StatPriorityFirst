--[[
	StatPriorityFirst - Player
	----
	Resolve current class/spec → data key. Spec IDs from C_SpecializationInfo
	(old GetSpecialization globals are deprecated shims, don't rely on them).
--]]

local _, ns = ...

local UnitClass = UnitClass
local C_SpecializationInfo = C_SpecializationInfo
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local GetSpecializationNameForSpecID = GetSpecializationNameForSpecID

function ns.GetPlayerClassFile()
	local _, classFile = UnitClass("player")
	return classFile
end

function ns.GetPlayerSpecID()
	if not C_SpecializationInfo or not C_SpecializationInfo.GetSpecialization then
		return nil
	end
	local index = C_SpecializationInfo.GetSpecialization()
	-- Unspecced / talents not loaded: index or docs default specId can be 0.
	-- In Lua 0 is truthy, don't treat it as a real specialization.
	if not index or index == 0 then
		return nil
	end
	local specID = C_SpecializationInfo.GetSpecializationInfo(index)
	if not specID or specID == 0 then
		return nil
	end
	return specID
end

function ns.GetPlayerDataKey()
	local classFile = ns.GetPlayerClassFile()
	local specID = ns.GetPlayerSpecID()
	if not classFile or not specID then
		return nil
	end
	return ns.DataKey(classFile, specID), classFile, specID
end

function ns.GetPlayerSpecEntry()
	local classFile, specID = ns.GetPlayerClassFile(), ns.GetPlayerSpecID()
	if not classFile or not specID then
		return nil, nil, nil
	end
	local class, spec = ns.GetCatalogSpec(classFile, specID)
	return class, spec, ns.GetSpecData(classFile, specID)
end

-- Display names for UI. Blizzard locale first, Catalog English as fallback.
-- Catalog `name` / `slug` stay English for scraper URLs and /spf warrior arms.
function ns.GetLocalizedClassName(classFile)
	if not classFile then
		return "?"
	end
	local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	if names and names[classFile] and names[classFile] ~= "" then
		return names[classFile]
	end
	local c = ns.Catalog and ns.Catalog[classFile]
	return (c and c.name) or classFile
end

function ns.GetLocalizedSpecName(specID, fallback)
	specID = tonumber(specID)
	if not specID then
		return fallback or "?"
	end
	if GetSpecializationNameForSpecID then
		local name = GetSpecializationNameForSpecID(specID)
		if name and name ~= "" and ns.NotSecret(name) then
			return name
		end
	end
	if GetSpecializationInfoForSpecID then
		local _, name = GetSpecializationInfoForSpecID(specID)
		if name and name ~= "" and ns.NotSecret(name) then
			return name
		end
	end
	return fallback or tostring(specID)
end
