--[[
	StatPriorityFirst - Item tooltip true-delta
	----
	Optional: on item tooltips, append (true N) after +Crit/Haste/Mastery/Vers
	lines. Marginal true rating of that piece on top of your current totals.
	Off by default; Settings → "Show true rating on item tooltips".

	Equipped pieces already count toward GetCombatRating, so tagging them would
	double-count "what if I had this on top of itself". We skip those.
--]]

local _, ns = ...
local L = ns.L

ns.ItemTooltip = ns.ItemTooltip or {}

local format = string.format
local find = string.find
local match = string.match
local gsub = string.gsub
local sub = string.sub
local min = math.min

local IsEquippedItem = C_Item and C_Item.IsEquippedItem

-- Locale-facing Blizzard STAT_* names. Patterns rebuilt when locale loads.
local patterns

local function BuildPatterns()
	local function make(statName)
		-- "+123 Crit" / "Increases your Crit by 123" style lines.
		return {
			"%+([,0-9]+)%s*" .. statName,
			statName .. " by%s*([,0-9]+)",
		}
	end
	patterns = {
		CRIT = make(STAT_CRITICAL_STRIKE or "Critical Strike"),
		HASTE = make(STAT_HASTE or "Haste"),
		MASTERY = make(STAT_MASTERY or "Mastery"),
		VERS = make(STAT_VERSATILITY or "Versatility"),
	}
end

local function Enabled()
	return ns.db and ns.db.drTooltips and ns.db.drTooltips.showOnItems
end

local function TooltipItemLink(tooltip)
	if not tooltip then
		return nil
	end
	if tooltip.GetItem then
		local _, link = tooltip:GetItem()
		if link then
			return link
		end
	end
	-- TooltipUtil is more reliable on some retail paths.
	if TooltipUtil and TooltipUtil.GetDisplayedItem then
		local _, link = TooltipUtil.GetDisplayedItem(tooltip)
		return link
	end
	return nil
end

local function AppendTrueDelta(tooltip)
	if not Enabled() or not tooltip or not patterns then
		return
	end
	-- One pass per tooltip paint. Locale strings change but the marker doesn't.
	if tooltip._spfTrueTagged then
		return
	end
	if C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret() then
		return
	end

	local link = TooltipItemLink(tooltip)
	if link and IsEquippedItem and IsEquippedItem(link) then
		-- Equipped rating is already inside paperdoll totals.
		tooltip._spfTrueTagged = true
		return
	end

	local accent = "|cff7ec8e3"
	local taggedAny = false
	for i = 2, min(30, tooltip:NumLines() or 0) do
		local fs = _G[tooltip:GetName() .. "TextLeft" .. i]
		if not fs or not fs.GetText then
			break
		end
		local text = fs:GetText()
		if text and type(text) == "string" and text ~= "" and ns.NotSecret(text) then
			-- Skip % lines (already converted).
			if not find(text, "%%") and not find(text, "%(true ") then
				for statKey, list in pairs(patterns) do
					for p = 1, #list do
						local amountStr = match(text, list[p])
						if amountStr then
							amountStr = gsub(amountStr, ",", "")
							local delta = ns.DR.GetTrueRatingAdded(statKey, amountStr)
							if delta ~= nil then
								local s, e = find(text, list[p])
								if s and e then
									local tagged = sub(text, 1, e)
										.. " "
										.. accent
										.. format(L["DR_ITEM_TRUE"], ns.DR.FormatTrueRating(delta))
										.. "|r"
										.. sub(text, e + 1)
									fs:SetText(tagged)
									taggedAny = true
								end
							end
							break
						end
					end
				end
			end
		end
	end
	if taggedAny or link then
		tooltip._spfTrueTagged = true
	end
end

local hooked

function ns.ItemTooltip.Init()
	if hooked then
		return
	end
	hooked = true
	BuildPatterns()

	if TooltipDataProcessor and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			AppendTrueDelta(tooltip)
		end)
	end

	-- Clear the one-shot tag whenever Blizzard empties a tooltip frame.
	local function ClearTag(tt)
		if tt then
			tt._spfTrueTagged = nil
		end
	end
	if GameTooltip and GameTooltip.HookScript then
		GameTooltip:HookScript("OnTooltipCleared", ClearTag)
		GameTooltip:HookScript("OnHide", ClearTag)
	end
	if ItemRefTooltip and ItemRefTooltip.HookScript then
		ItemRefTooltip:HookScript("OnTooltipCleared", ClearTag)
		ItemRefTooltip:HookScript("OnHide", ClearTag)
	end
end
