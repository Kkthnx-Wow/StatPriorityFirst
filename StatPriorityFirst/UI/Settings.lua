--[[
	StatPriorityFirst - Settings
	----
	Blizzard Settings panel only — hide minimap, scale, lock, open-to-Your-Spec,
	character-frame priority bar, optional item true-rating tooltips,
	plus a DR explainer at the bottom.
--]]

local addonName, ns = ...
local L = ns.L

ns.Settings = ns.Settings or {}

-- XML mixin= needs a global. Keep the name long so we don't collide with other addons.
StatPriorityFirstSettingsDescriptionMixin = {}

function StatPriorityFirstSettingsDescriptionMixin:Init(initializer)
	local data = initializer:GetData()
	self.Text:SetWordWrap(true)
	self.Text:SetText(data and data.text or "")
	self.Text:SetTextColor(0.85, 0.85, 0.85)
end

function StatPriorityFirstSettingsDescriptionMixin:Release()
end

-- Measure wrapped height off-screen so GetExtent never clips the paragraph.
local descMeasure
local DESC_MEASURE_WIDTH = 500
local DESC_PADDING = 14

local function MeasureDescriptionHeight(text)
	if not descMeasure then
		descMeasure = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		descMeasure:Hide()
		descMeasure:SetWidth(DESC_MEASURE_WIDTH)
		descMeasure:SetJustifyH("LEFT")
		descMeasure:SetWordWrap(true)
	end
	descMeasure:SetText(text or "")
	return (descMeasure:GetStringHeight() or 12) + DESC_PADDING
end

local function AddDRHelp(layout)
	if not layout then
		return
	end

	if CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["DR_HELP_HEADER"], L["DR_HELP_TIP"]))
	end

	if not (Settings and Settings.CreateElementInitializer) then
		return
	end

	local body = L["DR_HELP_BODY"]
	local initializer = Settings.CreateElementInitializer("StatPriorityFirstSettingsDescriptionTemplate", { text = body })
	local height = MeasureDescriptionHeight(body)
	initializer.GetExtent = function()
		return height
	end
	if initializer.AddSearchTags then
		initializer:AddSearchTags(L["DR_HELP_HEADER"], L["DR_HEADER"], "DR")
	end
	layout:AddInitializer(initializer)
end

local function ApplyScale()
	if ns.UI and ns.UI.ApplyPanelChrome then
		ns.UI.ApplyPanelChrome()
	end
end

local function ApplyLock()
	if ns.UI and ns.UI.ApplyPanelChrome then
		ns.UI.ApplyPanelChrome()
	end
end

local function ApplyMinimap()
	if ns.Minimap and ns.Minimap.SetShown then
		local hide = ns.db and ns.db.minimap and ns.db.minimap.hide
		ns.Minimap.SetShown(not hide)
	end
end

local function ApplyCharacterBar()
	if not ns.CharacterBar then
		return
	end
	local hide = ns.db and ns.db.characterBar and ns.db.characterBar.hide
	if hide then
		ns.CharacterBar.SetShown(false)
	else
		ns.CharacterBar.SetShown(true)
	end
end

function ns.Settings.Register()
	if ns.Settings.registered then
		return
	end

	-- Settings is a LOD addon — try once, then allow a later retry if still missing.
	if not Settings and C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_Settings")
	end

	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		return
	end

	ns.Settings.registered = true

	local category, layout = Settings.RegisterVerticalLayoutCategory(L["ADDON_NAME"])
	ns.Settings.category = category

	-- variableId must be unique across the whole Settings registry.
	-- variableKey is the field name inside variableTbl (can repeat across tables).
	local function Register(variableId, tbl, key, varType, name, default, callback)
		local setting = Settings.RegisterAddOnSetting(
			category,
			variableId,
			key,
			tbl,
			varType,
			name,
			default
		)
		if callback and setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function(_, value)
				callback(value)
			end)
		end
		return setting
	end

	ns.db.minimap = ns.db.minimap or { hide = false, angle = 220 }
	ns.db.panel = ns.db.panel or { point = "CENTER", x = 0, y = 0, scale = 1, locked = false }
	ns.db.characterBar = ns.db.characterBar or { hide = false }
	ns.db.drTooltips = ns.db.drTooltips or { showOnItems = false }

	local hideSetting = Register(
		addonName .. "_minimapHide",
		ns.db.minimap,
		"hide",
		Settings.VarType.Boolean,
		L["OPT_HIDE_MINIMAP"],
		false,
		ApplyMinimap
	)
	Settings.CreateCheckbox(category, hideSetting, L["OPT_HIDE_MINIMAP_TIP"])

	local lockSetting = Register(
		addonName .. "_panelLocked",
		ns.db.panel,
		"locked",
		Settings.VarType.Boolean,
		L["OPT_LOCK_PANEL"],
		false,
		ApplyLock
	)
	Settings.CreateCheckbox(category, lockSetting, L["OPT_LOCK_PANEL_TIP"])

	local followSetting = Register(
		addonName .. "_followPlayerDefault",
		ns.db,
		"followPlayerDefault",
		Settings.VarType.Boolean,
		L["OPT_FOLLOW_PLAYER"],
		true,
		nil
	)
	Settings.CreateCheckbox(category, followSetting, L["OPT_FOLLOW_PLAYER_TIP"])

	local charBarSetting = Register(
		addonName .. "_characterBarHide",
		ns.db.characterBar,
		"hide",
		Settings.VarType.Boolean,
		L["OPT_HIDE_CHAR_BAR"],
		false,
		ApplyCharacterBar
	)
	Settings.CreateCheckbox(category, charBarSetting, L["OPT_HIDE_CHAR_BAR_TIP"])

	local itemTrueSetting = Register(
		addonName .. "_drItemTrue",
		ns.db.drTooltips,
		"showOnItems",
		Settings.VarType.Boolean,
		L["OPT_DR_ITEM_TRUE"],
		false,
		nil
	)
	Settings.CreateCheckbox(category, itemTrueSetting, L["OPT_DR_ITEM_TRUE_TIP"])

	local scaleSetting = Register(
		addonName .. "_panelScale",
		ns.db.panel,
		"scale",
		Settings.VarType.Number,
		L["OPT_PANEL_SCALE"],
		1,
		ApplyScale
	)
	local options = Settings.CreateSliderOptions(0.75, 1.5, 0.05)
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return string.format("%.0f%%", value * 100)
		end)
	end
	Settings.CreateSlider(category, scaleSetting, options, L["OPT_PANEL_SCALE_TIP"])

	AddDRHelp(layout)

	Settings.RegisterAddOnCategory(category)
end
