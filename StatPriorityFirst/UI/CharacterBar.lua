--[[
	StatPriorityFirst - CharacterBar
	----
	Compact current-spec priority chain above CharacterFrame, Character tab only
	(PaperDollFrame). Hidden on Reputation / Currency — same activeSubframe
	Blizzard uses in CharacterFrame.lua.

	ElvUI / EllesmereUI: soft-skin our bar only when their Character sheet skins
	are on. Never touch CharacterFrame tabs. No UI suite → keep SettingsFrame /
	flat SPF chrome. ElvUI wins if both somehow load.
--]]

local _, ns = ...
local L = ns.L

ns.CharacterBar = ns.CharacterBar or {}

local CreateFrame = CreateFrame
local format = string.format
local max = math.max

local SETTINGS_SHARED = "Blizzard_Settings_Shared"
local CHIP_ICON = 22
local CHAIN_H = 34
local BAR_H = 64
local CHIP_GAP = 6 -- space between icon plate and label
local SEP_PAD = 12

local bar
local chainPool
local hooked

local function EnsureSettingsTemplate()
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn then
		if not C_AddOns.IsAddOnLoaded(SETTINGS_SHARED) then
			pcall(C_AddOns.LoadAddOn, SETTINGS_SHARED)
		end
	elseif LoadAddOn then
		pcall(LoadAddOn, SETTINGS_SHARED)
	end
end

local function IsEnabled()
	return not (ns.db and ns.db.characterBar and ns.db.characterBar.hide)
end

-- Character / Reputation / Currency share CharacterFrame. Priority only belongs
-- on the paper-doll tab (Blizzard: activeSubframe == "PaperDollFrame").
local function IsCharacterTabActive()
	if CharacterFrame and CharacterFrame.activeSubframe then
		return CharacterFrame.activeSubframe == "PaperDollFrame"
	end
	return PaperDollFrame and PaperDollFrame:IsShown()
end

local function ShouldShowBar()
	return IsEnabled()
		and CharacterFrame
		and CharacterFrame:IsShown()
		and IsCharacterTabActive()
end

local function StatColor(key)
	local c = ns.STAT_COLORS and ns.STAT_COLORS[key]
	if c then
		return c[1], c[2], c[3]
	end
	return 1, 1, 1
end

-- ---
-- Soft skins — ElvUI (HandleFrame) or EllesmereUI (PP border + fill). Bar only.
-- ---

local function IsExternallySkinned()
	return bar and (bar._spfElvSkinned or bar._spfEUISkinned)
end

local function HideBarCloseButtons()
	if not bar then
		return
	end
	if bar.ClosePanelButton then
		bar.ClosePanelButton:Hide()
		bar.ClosePanelButton:EnableMouse(false)
	end
	if bar.CloseButton then
		bar.CloseButton:Hide()
		bar.CloseButton:EnableMouse(false)
	end
end

local function GetElvUISkins()
	if not ElvUI then
		return nil
	end
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("ElvUI") then
		return nil
	end
	local ok, E = pcall(unpack, ElvUI)
	if not ok or not E or not E.initialized then
		return nil
	end
	-- Respect the user's Blizzard character skin toggle.
	local blizzard = E.private and E.private.skins and E.private.skins.blizzard
	if not (blizzard and blizzard.enable and blizzard.character) then
		return nil
	end
	local S = E:GetModule("Skins", true)
	if not (S and S.Initialized) then
		return nil
	end
	return E, S
end

local function GetEllesmereUISkin()
	local EUI = _G.EllesmereUI
	if not EUI then
		return nil
	end
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("EllesmereUI") then
		return nil
	end
	-- Character Sheet toggle in Blizz UI Enhanced (charsheet → themedCharacterSheet).
	if EUI.GetBlizzWindowStyle then
		if EUI.GetBlizzWindowStyle("charsheet") == "off" then
			return nil
		end
	elseif EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then
		return nil
	end
	local PP = EUI.PanelPP or EUI.PP
	if not (PP and PP.CreateBorder) then
		return nil
	end
	return EUI, PP
end

local function ApplyElvUIFont(fs)
	if fs and fs.FontTemplate then
		fs:FontTemplate()
	end
end

local function ApplyEUIFont(fs)
	local EUI = _G.EllesmereUI
	if not (fs and EUI and EUI.GetFontPath) then
		return
	end
	local path = EUI.GetFontPath("blizzardSkin")
	if not path then
		return
	end
	local flag = (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("blizzardSkin")) or ""
	local _, size = fs:GetFont()
	if EUI.PrimeFontShadow then
		EUI.PrimeFontShadow(fs, flag == "")
	end
	fs:SetFont(path, size or 12, flag)
end

local function ApplyExternalFont(fs)
	if not fs or not bar then
		return
	end
	if bar._spfElvSkinned then
		ApplyElvUIFont(fs)
	elseif bar._spfEUISkinned then
		ApplyEUIFont(fs)
	end
end

local function SkinChipChrome(chip)
	if not chip or not IsExternallySkinned() then
		return
	end
	ApplyExternalFont(chip.label)
	-- Suite-style icon crop; clear the SPF solid plate so we don't double-box.
	if chip.icon then
		chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	if chip.iconBg then
		chip.iconBg:SetColorTexture(0, 0, 0, 0)
	end
end

local function SkinSepChrome(sep)
	if not sep or not IsExternallySkinned() then
		return
	end
	ApplyExternalFont(sep.text)
end

local function SkinChainFonts()
	if not chainPool then
		return
	end
	for i = 1, #chainPool.chips do
		SkinChipChrome(chainPool.chips[i])
	end
	for i = 1, #chainPool.seps do
		SkinSepChrome(chainPool.seps[i])
	end
end

local function TrySkinBarWithElvUI()
	if not bar or IsExternallySkinned() then
		return bar and bar._spfElvSkinned
	end
	local E, S = GetElvUISkins()
	if not E then
		return false
	end
	-- Toolkit APIs land on frames after ElvUI init; CharacterFrame OnShow is late enough.
	if not bar.StripTextures or not bar.SetTemplate then
		return false
	end

	bar:StripTextures(true)
	if S and S.HandleFrame then
		S:HandleFrame(bar)
	else
		bar:SetTemplate("Transparent")
	end

	HideBarCloseButtons()

	local title = (bar.NineSlice and bar.NineSlice.Text) or bar.titleFS
	ApplyElvUIFont(title)
	ApplyElvUIFont(bar.empty)
	bar._spfElvSkinned = true
	SkinChainFonts()
	return true
end

-- Fade Blizzard art without Hide() — same visual-only habit as EUI BlizzardSkin.
local function FadeFrameTextures(frame)
	if not frame or not frame.GetRegions then
		return
	end
	local regions = { frame:GetRegions() }
	for i = 1, #regions do
		local r = regions[i]
		if r and r.GetObjectType and r:GetObjectType() == "Texture" then
			r:SetAlpha(0)
		end
	end
end

local function TrySkinBarWithEllesmereUI()
	if not bar or IsExternallySkinned() then
		return bar and bar._spfEUISkinned
	end
	local EUI, PP = GetEllesmereUISkin()
	if not EUI then
		return false
	end

	-- SettingsFrameTemplate NineSlice lives as a child — fade both layers.
	FadeFrameTextures(bar)
	if bar.NineSlice then
		FadeFrameTextures(bar.NineSlice)
	end
	HideBarCloseButtons()

	-- Flat panel fill matching EllesmereUIBlizzardSkin WSkin.Panel Theme.bg.
	if not bar._spfEUIBg then
		bar._spfEUIBg = bar:CreateTexture(nil, "BACKGROUND", nil, -6)
		bar._spfEUIBg:SetAllPoints()
	end
	bar._spfEUIBg:SetColorTexture(0.08, 0.08, 0.08, 0.92)
	bar._spfEUIBg:Show()

	if not bar._spfEUIBorder then
		bar._spfEUIBorder = PP.CreateBorder(bar, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 7)
	end

	local title = (bar.NineSlice and bar.NineSlice.Text) or bar.titleFS
	ApplyEUIFont(title)
	ApplyEUIFont(bar.empty)
	bar._spfEUISkinned = true
	SkinChainFonts()
	return true
end

local function TrySkinBar()
	if not bar or IsExternallySkinned() then
		return IsExternallySkinned()
	end
	if TrySkinBarWithElvUI() then
		return true
	end
	return TrySkinBarWithEllesmereUI()
end

local function HideChain()
	if not chainPool then
		return
	end
	for i = 1, #chainPool.chips do
		chainPool.chips[i]:Hide()
	end
	for i = 1, #chainPool.seps do
		chainPool.seps[i]:Hide()
	end
end

local function AcquireChip(i)
	local chip = chainPool.chips[i]
	if chip then
		chip:SetHeight(CHAIN_H)
		chip.iconBg:SetSize(CHIP_ICON + 2, CHIP_ICON + 2)
		chip.icon:SetSize(CHIP_ICON, CHIP_ICON)
		SkinChipChrome(chip)
		return chip
	end
	chip = CreateFrame("Button", nil, chainPool.parent)
	chip:SetHeight(CHAIN_H)
	chip:EnableMouse(true)

	chip.iconBg = chip:CreateTexture(nil, "BACKGROUND")
	chip.iconBg:SetSize(CHIP_ICON + 2, CHIP_ICON + 2)
	chip.iconBg:SetPoint("LEFT", 0, 0)
	chip.iconBg:SetColorTexture(0.10, 0.10, 0.11, 1)

	chip.icon = chip:CreateTexture(nil, "ARTWORK")
	chip.icon:SetSize(CHIP_ICON, CHIP_ICON)
	chip.icon:SetPoint("CENTER", chip.iconBg, "CENTER", 0, 0)

	chip.label = chip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	chip.label:SetPoint("LEFT", chip.iconBg, "RIGHT", CHIP_GAP, 0)

	chip:SetScript("OnEnter", function(self)
		if self.statKey and self.specEntry then
			ns.UI.ShowStatTooltip(self, self.specEntry, self.statKey)
		end
	end)
	chip:SetScript("OnLeave", function()
		ns.UI.HideStatTooltip()
	end)
	chip:SetScript("OnClick", function()
		-- Always open the panel — unspecced gets NO_SPEC instead of a silent no-op.
		if ns.UI.ShowSpec then
			local classFile, specID = ns.GetPlayerClassFile(), ns.GetPlayerSpecID()
			if classFile and specID then
				ns.UI.ShowSpec(classFile, specID)
			elseif ns.UI.Toggle then
				ns.UI.Toggle(true)
			end
		end
	end)

	chainPool.chips[i] = chip
	SkinChipChrome(chip)
	return chip
end

local function AcquireSep(i)
	local sep = chainPool.seps[i]
	if sep then
		sep:SetHeight(CHAIN_H)
		SkinSepChrome(sep)
		return sep
	end
	sep = CreateFrame("Frame", nil, chainPool.parent)
	sep:SetSize(22, CHAIN_H)
	sep.text = sep:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sep.text:SetPoint("CENTER")
	chainPool.seps[i] = sep
	SkinSepChrome(sep)
	return sep
end

local function LayoutChain(priority, entry, gaps)
	HideChain()
	if not priority or #priority == 0 then
		return 0
	end

	local host = chainPool.parent
	local x = 0
	local muted = ns.Skin and ns.Skin.Color and ns.Skin.Color.textMuted or { 0.55, 0.55, 0.55 }

	for i = 1, #priority do
		local key = priority[i]
		local chip = AcquireChip(i)
		chip.statKey = key
		chip.specEntry = entry

		local iconPath = ns.STAT_ICONS and ns.STAT_ICONS[key]
		if iconPath then
			chip.icon:SetTexture(iconPath)
			chip.icon:SetVertexColor(1, 1, 1)
			chip.icon:Show()
			chip.iconBg:Show()
		else
			chip.icon:Hide()
			chip.iconBg:Hide()
		end

		local r, g, b = StatColor(key)
		chip.label:SetText(ns.StatShort(key))
		chip.label:SetTextColor(r, g, b)

		local textW = chip.label:GetStringWidth() or 40
		local chipW = CHIP_ICON + 2 + CHIP_GAP + textW + 2
		chip:SetWidth(chipW)
		chip:ClearAllPoints()
		chip:SetPoint("LEFT", host, "LEFT", x, 0)
		chip:Show()
		x = x + chipW

		if i < #priority then
			local sep = AcquireSep(i)
			local glyph = ns.PrioritySeparator(priority, i, gaps)
			sep.text:SetText(glyph)
			sep.text:SetTextColor(muted[1], muted[2], muted[3])
			local sepW = max(18, (sep.text:GetStringWidth() or 12) + SEP_PAD)
			sep:SetWidth(sepW)
			sep:ClearAllPoints()
			sep:SetPoint("LEFT", host, "LEFT", x, 0)
			sep:Show()
			x = x + sepW
		end
	end

	-- Center the whole chain in the content area.
	host:SetWidth(max(x, 1))
	host:SetHeight(CHAIN_H)
	host:ClearAllPoints()
	host:SetPoint("CENTER", bar.content, "CENTER", 0, -1)

	return x
end

local function PickVariant(entry)
	if not entry or not entry.variants or #entry.variants == 0 then
		return nil
	end
	local classFile, specID = ns.GetPlayerClassFile(), ns.GetPlayerSpecID()
	-- Prefer the open panel's build when it's showing your live spec.
	if ns.UI and ns.UI.GetBrowseState then
		local s = ns.UI.GetBrowseState()
		if s and s.panelOpen and s.classFile == classFile and s.specID == specID then
			local v = entry.variants[s.variantIndex]
			if v then
				return v
			end
		end
	end
	-- Else last build tab remembered for *this* class/spec only.
	local want = ns.GetRememberedVariant and ns.GetRememberedVariant(classFile, specID)
	if want then
		for i = 1, #entry.variants do
			if entry.variants[i].id == want then
				return entry.variants[i]
			end
		end
	end
	return entry.variants[1]
end

function ns.CharacterBar.Refresh()
	if not bar then
		return
	end
	TrySkinBar()
	if not ShouldShowBar() then
		bar:Hide()
		return
	end

	local classFile, specID = ns.GetPlayerClassFile(), ns.GetPlayerSpecID()
	local entry = classFile and specID and ns.GetSpecData(classFile, specID)
	local variant = PickVariant(entry)
	local _, catalogSpec = ns.GetCatalogSpec(classFile, specID)

	local title = L["PRIORITY"]
	local specName = ns.GetLocalizedSpecName(specID, catalogSpec and catalogSpec.name)
	if specName and specName ~= "?" then
		title = format("%s — %s", specName, L["PRIORITY"])
	end
	if bar.NineSlice and bar.NineSlice.Text then
		bar.NineSlice.Text:SetText(title)
	elseif bar.titleFS then
		bar.titleFS:SetText(title)
	end

	if ns.Skin and ns.Skin.SetAccentClass and classFile then
		-- Don't stomp the floating panel's browsed-class accent while it's open.
		local panelOpen = ns.UI and ns.UI.IsShown and ns.UI.IsShown()
		if not panelOpen then
			ns.Skin.SetAccentClass(classFile)
		end
	end

	if not specID then
		-- Unspecced / talents not loaded — not a data-scrape problem.
		HideChain()
		bar.empty:SetText(L["NO_SPEC_SHORT"] or L["NO_SPEC"])
		bar.empty:SetWidth(max(40, (bar.content:GetWidth() or 200) - 16))
		bar.empty:SetWordWrap(true)
		bar.empty:Show()
		bar:Show()
		return
	end

	if not variant or not variant.priority then
		HideChain()
		bar.empty:SetText(L["NO_DATA"])
		bar.empty:SetWidth(max(40, (bar.content:GetWidth() or 200) - 16))
		bar.empty:SetWordWrap(true)
		bar.empty:Show()
		bar:Show()
		return
	end

	bar.empty:Hide()
	local gaps = variant.gaps or (entry and entry.chainGaps)
	LayoutChain(variant.priority, entry, gaps)
	bar:Show()
end

local function CreateBar()
	if bar then
		TrySkinBar()
		return bar
	end
	if not CharacterFrame then
		return nil
	end

	EnsureSettingsTemplate()
	-- Prefer Blizzard settings chrome; fall back to a plain frame if the template
	-- isn't available (LOD failed / OptionalDeps skipped).
	local ok, created = pcall(CreateFrame, "Frame", "StatPriorityFirstCharacterBar", CharacterFrame, "SettingsFrameTemplate")
	if ok and created then
		bar = created
	else
		bar = CreateFrame("Frame", "StatPriorityFirstCharacterBar", CharacterFrame, "BackdropTemplate")
		if ns.Skin and ns.Skin.ApplyFlatBackdrop then
			ns.Skin.ApplyFlatBackdrop(bar, ns.Skin.Color.bgPanel, ns.Skin.Color.border)
		end
		bar.titleFS = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		bar.titleFS:SetPoint("TOP", 0, -6)
		bar.titleFS:SetJustifyH("CENTER")
	end
	bar:SetHeight(BAR_H)
	bar:SetPoint("BOTTOMLEFT", CharacterFrame, "TOPLEFT", 0, 2)
	bar:SetPoint("BOTTOMRIGHT", CharacterFrame, "TOPRIGHT", 0, 2)
	bar:EnableMouse(true)
	bar:Hide()

	-- Title sits in the NineSlice; pull in the portrait-era side padding.
	if bar.NineSlice and bar.NineSlice.Text then
		bar.NineSlice.Text:ClearAllPoints()
		bar.NineSlice.Text:SetPoint("TOP", 0, -5)
		bar.NineSlice.Text:SetPoint("LEFT", 16, 0)
		bar.NineSlice.Text:SetPoint("RIGHT", -16, 0)
		bar.NineSlice.Text:SetJustifyH("CENTER")
	end

	-- Display chrome — close would only confuse next to CharacterFrame's X.
	if bar.ClosePanelButton then
		bar.ClosePanelButton:Hide()
		bar.ClosePanelButton:EnableMouse(false)
	end

	bar.content = CreateFrame("Frame", nil, bar)
	bar.content:SetPoint("TOPLEFT", 10, -24)
	bar.content:SetPoint("BOTTOMRIGHT", -10, 8)

	-- Chain host is width-fitted then centered inside content.
	bar.chainHost = CreateFrame("Frame", nil, bar.content)
	bar.chainHost:SetHeight(CHAIN_H)
	bar.chainHost:SetPoint("CENTER", bar.content, "CENTER", 0, -1)

	chainPool = { chips = {}, seps = {}, parent = bar.chainHost }

	bar.empty = bar.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	bar.empty:SetPoint("CENTER", bar.content, "CENTER", 0, -1)
	bar.empty:SetJustifyH("CENTER")
	bar.empty:Hide()

	-- Click empty chrome → open full panel (or follow-you empty when unspecced).
	bar:SetScript("OnMouseUp", function()
		local classFile, specID = ns.GetPlayerClassFile(), ns.GetPlayerSpecID()
		if classFile and specID and ns.UI.ShowSpec then
			ns.UI.ShowSpec(classFile, specID)
		elseif ns.UI.Toggle then
			ns.UI.Toggle(true)
		end
	end)

	TrySkinBar()
	return bar
end

local function HookCharacterFrame()
	if hooked or not CharacterFrame then
		return
	end
	hooked = true

	CharacterFrame:HookScript("OnShow", function()
		if IsEnabled() then
			CreateBar()
			ns.CharacterBar.Refresh()
		end
	end)
	CharacterFrame:HookScript("OnHide", function()
		if bar then
			bar:Hide()
		end
	end)

	-- Tab swaps call ShowSubFrame("PaperDollFrame"|"ReputationFrame"|"TokenFrame").
	if CharacterFrame.ShowSubFrame then
		hooksecurefunc(CharacterFrame, "ShowSubFrame", function()
			ns.CharacterBar.Refresh()
		end)
	end

	-- Belt-and-suspenders: PaperDoll show/hide tracks the Character tab directly.
	if PaperDollFrame then
		PaperDollFrame:HookScript("OnShow", function()
			if IsEnabled() then
				CreateBar()
				ns.CharacterBar.Refresh()
			end
		end)
		PaperDollFrame:HookScript("OnHide", function()
			if bar then
				bar:Hide()
			end
		end)
	end
end

function ns.CharacterBar.SetShown(show)
	if ns.db then
		ns.db.characterBar = ns.db.characterBar or {}
		ns.db.characterBar.hide = not show
	end
	if show then
		CreateBar()
		ns.CharacterBar.Refresh()
	elseif bar then
		bar:Hide()
	end
end

function ns.CharacterBar.Init()
	HookCharacterFrame()
	if ShouldShowBar() then
		CreateBar()
		ns.CharacterBar.Refresh()
	end
end
