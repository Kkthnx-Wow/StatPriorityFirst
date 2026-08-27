--[[
	StatPriorityFirst - Catalog
	----
	Static class/spec index for the UI browser + scraper URL map.
	specID values match GetSpecializationInfo / wowhead guide slugs.
--]]

local _, ns = ...

-- role: DAMAGER | HEALER | TANK  → Wowhead URL suffix
local function Spec(specID, name, slug, role)
	return { specID = specID, name = name, slug = slug, role = role }
end

ns.Catalog = {
	WARRIOR = {
		classID = 1,
		file = "WARRIOR",
		name = "Warrior",
		slug = "warrior",
		specs = {
			Spec(71, "Arms", "arms", "DAMAGER"),
			Spec(72, "Fury", "fury", "DAMAGER"),
			Spec(73, "Protection", "protection", "TANK"),
		},
	},
	PALADIN = {
		classID = 2,
		file = "PALADIN",
		name = "Paladin",
		slug = "paladin",
		specs = {
			Spec(65, "Holy", "holy", "HEALER"),
			Spec(66, "Protection", "protection", "TANK"),
			Spec(70, "Retribution", "retribution", "DAMAGER"),
		},
	},
	HUNTER = {
		classID = 3,
		file = "HUNTER",
		name = "Hunter",
		slug = "hunter",
		specs = {
			Spec(253, "Beast Mastery", "beast-mastery", "DAMAGER"),
			Spec(254, "Marksmanship", "marksmanship", "DAMAGER"),
			Spec(255, "Survival", "survival", "DAMAGER"),
		},
	},
	ROGUE = {
		classID = 4,
		file = "ROGUE",
		name = "Rogue",
		slug = "rogue",
		specs = {
			Spec(259, "Assassination", "assassination", "DAMAGER"),
			Spec(260, "Outlaw", "outlaw", "DAMAGER"),
			Spec(261, "Subtlety", "subtlety", "DAMAGER"),
		},
	},
	PRIEST = {
		classID = 5,
		file = "PRIEST",
		name = "Priest",
		slug = "priest",
		specs = {
			Spec(256, "Discipline", "discipline", "HEALER"),
			Spec(257, "Holy", "holy", "HEALER"),
			Spec(258, "Shadow", "shadow", "DAMAGER"),
		},
	},
	DEATHKNIGHT = {
		classID = 6,
		file = "DEATHKNIGHT",
		name = "Death Knight",
		slug = "death-knight",
		specs = {
			Spec(250, "Blood", "blood", "TANK"),
			Spec(251, "Frost", "frost", "DAMAGER"),
			Spec(252, "Unholy", "unholy", "DAMAGER"),
		},
	},
	SHAMAN = {
		classID = 7,
		file = "SHAMAN",
		name = "Shaman",
		slug = "shaman",
		specs = {
			Spec(262, "Elemental", "elemental", "DAMAGER"),
			Spec(263, "Enhancement", "enhancement", "DAMAGER"),
			Spec(264, "Restoration", "restoration", "HEALER"),
		},
	},
	MAGE = {
		classID = 8,
		file = "MAGE",
		name = "Mage",
		slug = "mage",
		specs = {
			Spec(62, "Arcane", "arcane", "DAMAGER"),
			Spec(63, "Fire", "fire", "DAMAGER"),
			Spec(64, "Frost", "frost", "DAMAGER"),
		},
	},
	WARLOCK = {
		classID = 9,
		file = "WARLOCK",
		name = "Warlock",
		slug = "warlock",
		specs = {
			Spec(265, "Affliction", "affliction", "DAMAGER"),
			Spec(266, "Demonology", "demonology", "DAMAGER"),
			Spec(267, "Destruction", "destruction", "DAMAGER"),
		},
	},
	MONK = {
		classID = 10,
		file = "MONK",
		name = "Monk",
		slug = "monk",
		specs = {
			Spec(268, "Brewmaster", "brewmaster", "TANK"),
			Spec(270, "Mistweaver", "mistweaver", "HEALER"),
			Spec(269, "Windwalker", "windwalker", "DAMAGER"),
		},
	},
	DRUID = {
		classID = 11,
		file = "DRUID",
		name = "Druid",
		slug = "druid",
		specs = {
			Spec(102, "Balance", "balance", "DAMAGER"),
			Spec(103, "Feral", "feral", "DAMAGER"),
			Spec(104, "Guardian", "guardian", "TANK"),
			Spec(105, "Restoration", "restoration", "HEALER"),
		},
	},
	DEMONHUNTER = {
		classID = 12,
		file = "DEMONHUNTER",
		name = "Demon Hunter",
		slug = "demon-hunter",
		specs = {
			Spec(577, "Havoc", "havoc", "DAMAGER"),
			Spec(581, "Vengeance", "vengeance", "TANK"),
			Spec(1480, "Devourer", "devourer", "DAMAGER"),
		},
	},
	EVOKER = {
		classID = 13,
		file = "EVOKER",
		name = "Evoker",
		slug = "evoker",
		specs = {
			Spec(1467, "Devastation", "devastation", "DAMAGER"),
			Spec(1468, "Preservation", "preservation", "HEALER"),
			Spec(1473, "Augmentation", "augmentation", "DAMAGER"),
		},
	},
}

-- Display order for the class dropdown
ns.CatalogOrder = {
	"DEATHKNIGHT",
	"DEMONHUNTER",
	"DRUID",
	"EVOKER",
	"HUNTER",
	"MAGE",
	"MONK",
	"PALADIN",
	"PRIEST",
	"ROGUE",
	"SHAMAN",
	"WARLOCK",
	"WARRIOR",
}

local ROLE_SUFFIX = {
	DAMAGER = "stat-priority-pve-dps",
	HEALER = "stat-priority-pve-healer",
	TANK = "stat-priority-pve-tank",
}

function ns.DataKey(classFile, specID)
	return classFile .. "-" .. tostring(specID)
end

function ns.GetCatalogSpec(classFile, specID)
	local class = ns.Catalog[classFile]
	if not class then
		return nil
	end
	for i = 1, #class.specs do
		local s = class.specs[i]
		if s.specID == specID then
			return class, s
		end
	end
	return class, nil
end

function ns.GuideURL(classFile, specID)
	local class, spec = ns.GetCatalogSpec(classFile, specID)
	if not class or not spec then
		return nil
	end
	local suffix = ROLE_SUFFIX[spec.role] or ROLE_SUFFIX.DAMAGER
	return string.format(
		"https://www.wowhead.com/guide/classes/%s/%s/%s",
		class.slug,
		spec.slug,
		suffix
	)
end

function ns.GetSpecData(classFile, specID)
	local data = ns.Data and ns.Data.specs
	if not data then
		return nil
	end
	return data[ns.DataKey(classFile, specID)]
end
