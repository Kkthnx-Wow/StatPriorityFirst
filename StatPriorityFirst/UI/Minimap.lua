--[[
	StatPriorityFirst - Minimap button
	----
	No LibDBIcon dependency, but we steal its edge math: radius tracks
	Minimap:GetWidth()/2 so square ElvUI/Ellesmere maps don't park the button
	inside the terrain. Flat SPF chrome by default, kill the gold
	MiniMap-TrackingBorder forever.
--]]

local _, ns = ...
local L = ns.L
local Skin = ns.Skin

ns.Minimap = {}

local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
local cos, sin, rad, deg, atan2, sqrt, max, min = math.cos, math.sin, math.rad, math.deg, math.atan2, math.sqrt, math.max, math.min

local BUTTON_SIZE = 24
local EDGE = 5 -- LibDBIcon default: sit just outside the map rim
local dragging = false

-- Quadrant round/square rules, the same table LibDBIcon ships.
local MINIMAP_SHAPES = {
	["ROUND"] = { true, true, true, true },
	["SQUARE"] = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local button
local sizeHooked

local function GetAngle()
	return (ns.db and ns.db.minimap and ns.db.minimap.angle) or 220
end

local function UpdatePosition()
	if not button or not Minimap then
		return
	end
	local angle = rad(GetAngle())
	local x, y, q = cos(angle), sin(angle), 1
	if x < 0 then
		q = q + 1
	end
	if y > 0 then
		q = q + 2
	end

	local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
	local quad = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES.ROUND
	local w = (Minimap:GetWidth() / 2) + EDGE
	local h = (Minimap:GetHeight() / 2) + EDGE

	if quad[q] then
		x, y = x * w, y * h
	else
		-- Square / corner maps: clamp to the box edge instead of a circle.
		local diagW = sqrt(2 * (w ^ 2)) - 10
		local diagH = sqrt(2 * (h ^ 2)) - 10
		x = max(-w, min(x * diagW, w))
		y = max(-h, min(y * diagH, h))
	end

	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function ApplyElvUIButtonSkin()
	if not (ElvUI and C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI")) then
		return false
	end
	local ok, E = pcall(unpack, ElvUI)
	if not ok or not E or not E.initialized then
		return false
	end
	local S = E:GetModule("Skins", true)
	if not (S and S.HandleButton) then
		return false
	end
	S:HandleButton(button)
	if button.icon then
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button.icon:ClearAllPoints()
		button.icon:SetPoint("TOPLEFT", 2, -2)
		button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	end
	return true
end

local function ApplyEllesmereButtonSkin()
	local EUI = _G.EllesmereUI
	if not EUI then
		return false
	end
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("EllesmereUI") then
		return false
	end
	local PP = EUI.PanelPP or EUI.PP
	if not (PP and PP.CreateBorder) then
		return false
	end
	if not button._spfEUIBg then
		button._spfEUIBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
		button._spfEUIBg:SetAllPoints()
	end
	button._spfEUIBg:SetColorTexture(0.08, 0.08, 0.08, 0.92)
	if not button._spfEUIBorder then
		button._spfEUIBorder = PP.CreateBorder(button, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 7)
	end
	if button.icon then
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	return true
end

local function TrySkinButton()
	if not button or button._spfSkinned then
		return
	end
	-- Prefer ElvUI button skin, else Ellesmere border, else keep SPF flat backdrop.
	if ApplyElvUIButtonSkin() or ApplyEllesmereButtonSkin() then
		button._spfSkinned = true
	end
end

function ns.Minimap.Init()
	if button then
		TrySkinButton()
		UpdatePosition()
		return
	end
	if not Minimap then
		return
	end

	button = CreateFrame("Button", "StatPriorityFirstMinimapButton", Minimap, "BackdropTemplate")
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetMovable(true)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	if Skin and Skin.ApplyFlatBackdrop then
		Skin.ApplyFlatBackdrop(button, Skin.Color.bgRaised, Skin.Color.border)
	end

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", -3, 3)
	icon:SetTexture(ns.STAT_ICONS and ns.STAT_ICONS.CRIT)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.icon = icon

	button:SetScript("OnClick", function(_, mouse)
		if dragging then
			return
		end
		if mouse == "LeftButton" then
			ns.UI.Toggle()
		elseif mouse == "RightButton" then
			local classFile, specID = ns.GetPlayerClassFile(), ns.GetPlayerSpecID()
			if classFile and specID then
				ns.UI.ShowSpec(classFile, specID)
			else
				ns.UI.Toggle(true)
			end
		end
	end)

	button:SetScript("OnDragStart", function(self)
		dragging = true
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			cx, cy = cx / scale, cy / scale
			local angle = deg(atan2(cy - my, cx - mx))
			if ns.db and ns.db.minimap then
				ns.db.minimap.angle = angle
			end
			UpdatePosition()
		end)
	end)

	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		-- Release after click dispatch so the end-of-drag click is ignored.
		C_Timer.After(0, function()
			dragging = false
		end)
	end)

	button:SetScript("OnHide", function(self)
		-- Reload mid-drag left OnUpdate spinning. Kill it.
		self:SetScript("OnUpdate", nil)
		dragging = false
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["ADDON_NAME"])
		GameTooltip:AddLine(L["OPEN_PANEL"], 0.8, 0.8, 0.8)
		GameTooltip:AddLine(string.format(L["MINIMAP_RIGHT"], L["YOUR_SPEC"]), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	if not sizeHooked then
		sizeHooked = true
		Minimap:HookScript("OnSizeChanged", UpdatePosition)
	end

	TrySkinButton()

	if ns.db and ns.db.minimap and ns.db.minimap.hide then
		button:Hide()
	else
		button:Show()
	end
	UpdatePosition()
end

function ns.Minimap.SetShown(shown)
	if ns.db and ns.db.minimap then
		ns.db.minimap.hide = not shown
	end
	if button then
		if shown then
			button:Show()
			UpdatePosition()
		else
			button:Hide()
		end
	end
end
