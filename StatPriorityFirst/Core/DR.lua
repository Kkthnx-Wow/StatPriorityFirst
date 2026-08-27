--[[
	StatPriorityFirst - DR helpers
	----
	Shared Midnight secondary-stat diminishing-return math.
	Breakpoints match Maxroll / Icy Veins / Wowhead guide tables (level 90):
	  Crit/Mastery 1380 / 1840 / 2300
	  Haste         1320 / 1760 / 2200
	  Vers          1620 / 2160 / 2700
	True/lost rating uses SimC rating→% conversion + % brackets
	(sc_scale_data.inc / item_scaling.inc 21024) — same model TrueStatValues uses.
	Penalty applies only to rating above each threshold (not the whole pool).
--]]

local _, ns = ...
local L = ns.L

local floor = math.floor
local min = math.min
local max = math.max
local format = string.format
local GetCombatRating = GetCombatRating
local GetCritChance = GetCritChance
local GetRangedCritChance = GetRangedCritChance
local GetSpellCritChance = GetSpellCritChance
local UnitLevel = UnitLevel

local CR_CRIT_MELEE = rawget(_G, "CR_CRIT_MELEE") or 9
local CR_CRIT_RANGED = rawget(_G, "CR_CRIT_RANGED") or 10
local CR_CRIT_SPELL = rawget(_G, "CR_CRIT_SPELL") or 11
local CR_HASTE_MELEE = rawget(_G, "CR_HASTE_MELEE") or 18
local CR_MASTERY = rawget(_G, "CR_MASTERY") or 26
local CR_VERSATILITY_DAMAGE_DONE = rawget(_G, "CR_VERSATILITY_DAMAGE_DONE") or 29

ns.DR = ns.DR or {}

ns.DR.SECONDARY = {
	CRIT = true,
	HASTE = true,
	MASTERY = true,
	VERS = true,
}

-- Game-wide Midnight defaults (same for every class/spec).
ns.DR.DEFAULTS = {
	CRIT = { 1380, 1840, 2300 },
	HASTE = { 1320, 1760, 2200 },
	MASTERY = { 1380, 1840, 2300 },
	VERS = { 1620, 2160, 2700 },
}

ns.DR.BAND_COLORS = {
	[0] = { 0.40, 0.90, 0.40 },
	[1] = { 0.95, 0.85, 0.25 },
	[2] = { 1.00, 0.60, 0.20 },
	[3] = { 1.00, 0.35, 0.35 },
}

ns.DR.STAT_ORDER = { "CRIT", "HASTE", "MASTERY", "VERS" }

-- SimC secondary brackets (id 21024): size in % of pre-DR conversion, penalty on that band.
ns.DR.BRACKETS = {
	{ size = 30, penalty = 0 },
	{ size = 10, penalty = 0.1 },
	{ size = 10, penalty = 0.2 },
	{ size = 10, penalty = 0.3 },
	{ size = 20, penalty = 0.4 },
	{ size = 120, penalty = 0.5 },
	{ size = 100000, penalty = 1.0 },
}

-- Rating per 1% by player level (SimC sc_scale_data.inc — midnight). Index = level.
-- Level 90: Crit/Mastery 46, Haste 44, Vers 54 → first breakpoint = 30 * factor.
local CONV = {
	CRIT = {
		3.056530805, 3.056530805, 3.056530805, 3.056530805, 3.056530805,
		3.056530805, 3.056530805, 3.056530805, 3.056530805, 3.056530805,
		3.056530805, 3.209357346, 3.362183886, 3.515010426, 3.667836966,
		3.820663507, 3.973490047, 4.126316587, 4.279143127, 4.431969668,
		4.477766688, 4.525529532, 4.575310357, 4.627163874, 4.681147453,
		4.737321222, 4.795748184, 4.856494328, 4.919628754, 4.985223804,
		5.053355196, 5.124102169, 5.197547633, 5.273778332, 5.352885007,
		5.434962577, 5.520110324, 5.608432089, 5.70003648, 5.795037088,
		5.893552718, 5.995707632, 6.1016318, 6.211461173, 6.325337961,
		6.443410936, 6.565835744, 6.692775235, 6.824399815, 6.960887811,
		7.102425863, 7.249209331, 7.401442727, 7.559340172, 7.723125876,
		7.893034645, 8.069312419, 8.252216833, 8.442017821, 8.638998236,
		8.843454528, 9.055697437, 9.276052741, 9.504862042, 9.742483593,
		9.989293177, 10.24568504, 10.51207285, 10.78889076, 11.07659452,
		11.18028258, 11.28494127, 11.39057967, 11.49720694, 11.60483236,
		11.71346526, 11.82311507, 11.93379132, 12.04550361, 12.15826163,
		13.58403151, 15.17699796, 16.95676773, 18.94524679, 21.16690997,
		23.6491022, 26.42237511, 29.520863, 32.98270306, 46,
	},
	HASTE = {
		2.923638162, 2.923638162, 2.923638162, 2.923638162, 2.923638162,
		2.923638162, 2.923638162, 2.923638162, 2.923638162, 2.923638162,
		2.923638162, 3.06982007, 3.216001978, 3.362183886, 3.508365794,
		3.654547702, 3.80072961, 3.946911518, 4.093093426, 4.239275334,
		4.283081179, 4.328767379, 4.37638382, 4.425982836, 4.477619303,
		4.531350734, 4.587237394, 4.6453424, 4.705731852, 4.768474943,
		4.833644101, 4.901315118, 4.971567301, 5.044483622, 5.120150876,
		5.198659856, 5.280105527, 5.364587216, 5.452208807, 5.543078954,
		5.637311296, 5.735024692, 5.836343461, 5.941397644, 6.050323267,
		6.163262635, 6.280364625, 6.401785008, 6.527686779, 6.658240515,
		6.793624739, 6.934026317, 7.079640869, 7.230673208, 7.387337794,
		7.549859225, 7.718472748, 7.893424797, 8.074973567, 8.263389617,
		8.458956505, 8.661971461, 8.8727461, 9.09160717, 9.31889735,
		9.554976083, 9.800220469, 10.0550262, 10.31980856, 10.59500345,
		10.69418334, 10.79429165, 10.89533707, 10.99732838, 11.10027443,
		11.20418416, 11.30906659, 11.41493083, 11.52178606, 11.62964156,
		12.99342144, 14.51712849, 16.21951696, 18.12154041, 20.24660954,
		22.62088037, 25.27357619, 28.23734722, 31.5486725, 44,
	},
	MASTERY = nil, -- same curve as Crit
	VERS = {
		3.58810138, 3.58810138, 3.58810138, 3.58810138, 3.58810138,
		3.58810138, 3.58810138, 3.58810138, 3.58810138, 3.58810138,
		3.58810138, 3.767506449, 3.946911518, 4.126316587, 4.305721656,
		4.485126725, 4.664531794, 4.843936863, 5.023341932, 5.202747001,
		5.25650872, 5.312578146, 5.371016506, 5.431888026, 5.495260053,
		5.561203174, 5.629791347, 5.701102037, 5.775216363, 5.852219248,
		5.932199578, 6.015250372, 6.101468961, 6.190957172, 6.28382153,
		6.38017346, 6.480129511, 6.583811583, 6.691347172, 6.802869625,
		6.918518409, 7.038439394, 7.162785157, 7.29171529, 7.425396737,
		7.564004143, 7.707720221, 7.856736146, 8.011251956, 8.171476996,
		8.337630361, 8.509941389, 8.688650158, 8.874008028, 9.066278202,
		9.265736322, 9.4726711, 9.687384978, 9.910194833, 10.14143271,
		10.38144662, 10.63060134, 10.8892793, 11.15788153, 11.43682857,
		11.72656156, 12.0275433, 12.34025943, 12.66521959, 13.00295878,
		13.12467955, 13.24753975, 13.37155004, 13.4967212, 13.62306408,
		13.75058965, 13.879309, 14.00923329, 14.1403738, 14.27274192,
		15.94647177, 17.81647587, 19.90577082, 22.24007232, 24.8481117,
		27.76198954, 31.01757078, 34.65492613, 38.71882534, 54,
	},
}
CONV.MASTERY = CONV.CRIT

local function Round2(n)
	return floor(0.005 + 100 * n) / 100
end

function ns.DR.FormatRating(n)
	n = floor((n or 0) + 0.5)
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(n)
	end
	return tostring(n)
end

function ns.DR.FormatTrueRating(n)
	if n == nil then
		return "?"
	end
	-- Keep one decimal when SimC math isn't a whole number.
	if floor(n + 0.0001) == n then
		return ns.DR.FormatRating(n)
	end
	return format("%.2f", n)
end

function ns.DR.GetConversionFactor(statKey)
	local table = CONV[statKey]
	if not table then
		return nil
	end
	local level = UnitLevel("player") or 90
	level = max(1, min(#table, floor(level)))
	return table[level]
end

local function PlainNumber(v)
	if v == nil or not ns.NotSecret(v) or not ns.CanAccess(v) then
		return nil
	end
	return v
end

local function GetCritRatingIndex()
	local holySchool = 2
	local spellCrit = PlainNumber(GetSpellCritChance and GetSpellCritChance(holySchool))
	if spellCrit and GetSpellCritChance and MAX_SPELL_SCHOOLS then
		for i = holySchool + 1, MAX_SPELL_SCHOOLS do
			local c = PlainNumber(GetSpellCritChance(i))
			if c and c < spellCrit then
				spellCrit = c
			end
		end
	end
	local rangedCrit = PlainNumber(GetRangedCritChance and GetRangedCritChance())
	local meleeCrit = PlainNumber(GetCritChance and GetCritChance())
	if not spellCrit or not rangedCrit or not meleeCrit then
		return CR_CRIT_MELEE
	end
	if spellCrit >= rangedCrit and spellCrit >= meleeCrit then
		return CR_CRIT_SPELL
	elseif rangedCrit >= meleeCrit then
		return CR_CRIT_RANGED
	end
	return CR_CRIT_MELEE
end

function ns.DR.GetRatingIndex(statKey)
	if statKey == "CRIT" then
		return GetCritRatingIndex()
	elseif statKey == "HASTE" then
		return CR_HASTE_MELEE
	elseif statKey == "MASTERY" then
		return CR_MASTERY
	elseif statKey == "VERS" then
		return CR_VERSATILITY_DAMAGE_DONE
	end
	return nil
end

-- Returns rating number, or nil + "secret" when restricted.
function ns.DR.GetPlayerRating(statKey)
	if not ns.DR.SECONDARY[statKey] or not GetCombatRating then
		return nil
	end
	if C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret() then
		return nil, "secret"
	end
	local index = ns.DR.GetRatingIndex(statKey)
	if not index then
		return nil
	end
	local rating = GetCombatRating(index)
	if rating == nil then
		return nil
	end
	if not ns.NotSecret(rating) or not ns.CanAccess(rating) then
		return nil, "secret"
	end
	return rating
end

-- Walk SimC % brackets for (rating + amount). Returns nil if inputs are unusable.
function ns.DR.ComputeTrueRating(statKey, rating, amount)
	if not ns.DR.SECONDARY[statKey] then
		return nil
	end
	amount = amount or 0
	if type(rating) ~= "number" or type(amount) ~= "number" then
		return nil
	end
	if not ns.NotSecret(rating) or not ns.NotSecret(amount) then
		return nil
	end
	local conversion = ns.DR.GetConversionFactor(statKey)
	if not conversion or conversion == 0 then
		return nil
	end

	local percent = (rating + amount) / conversion
	local trueRating = 0
	local bracketRating, bracketMaxRating, bracketPenalty, bracketNextPenalty = 0, 0, 0, 0.1
	local brackets = ns.DR.BRACKETS

	for i = 1, #brackets do
		local bracket = brackets[i]
		if percent < bracket.size then
			bracketRating = floor(0.5 + percent * conversion)
			bracketMaxRating = floor(0.5 + bracket.size * conversion)
			bracketPenalty = bracket.penalty
			local nextB = brackets[i + 1]
			bracketNextPenalty = nextB and nextB.penalty or 1
			trueRating = trueRating + (percent * conversion * (1 - bracket.penalty))
			break
		else
			trueRating = trueRating + (bracket.size * conversion * (1 - bracket.penalty))
			percent = percent - bracket.size
		end
	end

	trueRating = Round2(trueRating)
	local base = rating + amount
	local lostRating = Round2(base - trueRating)
	return {
		trueRating = trueRating,
		lostRating = lostRating,
		baseRating = base,
		bracketRating = bracketRating,
		bracketMaxRating = bracketMaxRating,
		bracketPenalty = bracketPenalty,
		bracketNextPenalty = bracketNextPenalty,
		conversion = conversion,
	}
end

-- Marginal true rating of adding `amount` on top of current player rating.
function ns.DR.GetTrueRatingAdded(statKey, amount)
	amount = tonumber(amount)
	if not amount then
		return nil
	end
	local rating, reason = ns.DR.GetPlayerRating(statKey)
	if not rating then
		return nil, reason
	end
	local baseInfo = ns.DR.ComputeTrueRating(statKey, rating, 0)
	local withInfo = ns.DR.ComputeTrueRating(statKey, rating, amount)
	if not baseInfo or not withInfo then
		return nil
	end
	return Round2(withInfo.trueRating - baseInfo.trueRating)
end

-- band 0 = under 10%, 1 = in 10%, 2 = in 20%, 3 = in/past 30%.
function ns.DR.GetBand(rating, drVals)
	local band = 0
	if not drVals then
		return band
	end
	local n = min(3, #drVals)
	for i = 1, n do
		if rating >= drVals[i] then
			band = i
		else
			break
		end
	end
	return band
end

function ns.DR.GetBreakpoints(statKey, specEntry)
	if specEntry and specEntry.dr and specEntry.dr[statKey] and #specEntry.dr[statKey] > 0 then
		return specEntry.dr[statKey]
	end
	return ns.DR.DEFAULTS[statKey]
end

function ns.DR.BandStatusKey(band)
	return ({
		[0] = "DR_BAND_NONE",
		[1] = "DR_BAND_10",
		[2] = "DR_BAND_20",
		[3] = "DR_BAND_30",
	})[band]
end

function ns.DR.DescribeLive(statKey, specEntry)
	local drVals = ns.DR.GetBreakpoints(statKey, specEntry)
	if not drVals then
		return nil
	end
	local rating, reason = ns.DR.GetPlayerRating(statKey)
	if not rating then
		return { secret = reason == "secret", drVals = drVals }
	end
	local band = ns.DR.GetBand(rating, drVals)
	local labels = { L["DR_10"], L["DR_20"], L["DR_30"] }
	local nextNeed, nextLabel
	if band < 3 and drVals[band + 1] then
		nextNeed = drVals[band + 1] - rating
		if nextNeed < 0 then
			nextNeed = 0
		end
		nextLabel = labels[band + 1]
	end
	local trueInfo = ns.DR.ComputeTrueRating(statKey, rating, 0)
	return {
		rating = rating,
		band = band,
		drVals = drVals,
		statusKey = ns.DR.BandStatusKey(band),
		nextNeed = nextNeed,
		nextLabel = nextLabel,
		color = ns.DR.BAND_COLORS[band] or ns.DR.BAND_COLORS[0],
		trueRating = trueInfo and trueInfo.trueRating,
		lostRating = trueInfo and trueInfo.lostRating,
		bracketRating = trueInfo and trueInfo.bracketRating,
		bracketMaxRating = trueInfo and trueInfo.bracketMaxRating,
		bracketPenalty = trueInfo and trueInfo.bracketPenalty,
	}
end
