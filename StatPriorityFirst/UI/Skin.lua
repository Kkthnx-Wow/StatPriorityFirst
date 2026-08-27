--[[
	StatPriorityFirst - Skin
	----
	Flat Wowhead-inspired chrome: dark panels, thin gray borders.
	Accent = current class color (Raid/M+ pills on Wowhead are class-tinted,
	not a fixed purple, DH just happens to be purple).
--]]

local _, ns = ...

local CreateFrame = CreateFrame
local format = string.format
local min = math.min
local max = math.max
local floor = math.floor

local C = {
	bg = { 0.07, 0.07, 0.08, 0.97 },
	bgPanel = { 0.09, 0.09, 0.10, 0.98 },
	bgRaised = { 0.14, 0.14, 0.16, 1 },
	bgHover = { 0.18, 0.18, 0.20, 1 },
	bgInset = { 0.11, 0.11, 0.12, 1 },
	border = { 0.38, 0.38, 0.40, 1 },
	borderSoft = { 0.28, 0.28, 0.30, 1 },
	text = { 0.92, 0.92, 0.94, 1 },
	textMuted = { 0.58, 0.58, 0.60, 1 },
	white = { 1, 1, 1, 1 },
}

-- Live accent (mutated by SetAccent / SetAccentClass)
local accent = { 0.576, 0.200, 0.918, 1 }
local accentHot = { 0.65, 0.28, 0.96, 1 }

ns.Skin = ns.Skin or {}
ns.Skin.Color = C

local function Unpack(c)
	return c[1], c[2], c[3], c[4] or 1
end

local function Brighten(r, g, b, amount)
	amount = amount or 0.12
	return min(1, r + amount), min(1, g + amount), min(1, b + amount)
end

local FLAT_BD = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
	insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

function ns.Skin.ApplyFlatBackdrop(frame, bg, border)
	frame:SetBackdrop(FLAT_BD)
	frame:SetBackdropColor(Unpack(bg or C.bgPanel))
	frame:SetBackdropBorderColor(Unpack(border or C.border))
end

function ns.Skin.GetAccent()
	return accent[1], accent[2], accent[3]
end

function ns.Skin.GetAccentHex()
	return format(
		"%02x%02x%02x",
		floor(accent[1] * 255 + 0.5),
		floor(accent[2] * 255 + 0.5),
		floor(accent[3] * 255 + 0.5)
	)
end

function ns.Skin.SetAccent(r, g, b)
	accent[1], accent[2], accent[3] = r, g, b
	local hr, hg, hb = Brighten(r, g, b, 0.14)
	accentHot[1], accentHot[2], accentHot[3] = hr, hg, hb
end

function ns.Skin.SetAccentClass(classFile)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then
		ns.Skin.SetAccent(c.r, c.g, c.b)
	else
		ns.Skin.SetAccent(1, 0.82, 0)
	end
end

local function PaintButton(btn, mode)
	-- mode: "idle" | "hover"
	if mode == "hover" then
		if btn.isActive then
			btn:SetBackdropColor(Unpack(accentHot))
			btn:SetBackdropBorderColor(Unpack(accentHot))
			if btn.label then
				btn.label:SetTextColor(Unpack(C.white))
			end
		else
			btn:SetBackdropColor(Unpack(C.bgHover))
			btn:SetBackdropBorderColor(Unpack(C.border))
			if btn.label then
				btn.label:SetTextColor(Unpack(C.text))
			end
		end
	else
		if btn.isActive then
			btn:SetBackdropColor(Unpack(accent))
			btn:SetBackdropBorderColor(Unpack(accent))
			if btn.label then
				btn.label:SetTextColor(Unpack(C.white))
			end
		else
			btn:SetBackdropColor(Unpack(C.bgRaised))
			btn:SetBackdropBorderColor(Unpack(C.borderSoft))
			if btn.label then
				btn.label:SetTextColor(Unpack(C.textMuted))
			end
		end
	end
end

-- Flat pill / toolbar button. Active fill uses class accent.
function ns.Skin.CreateFlatButton(parent, opts)
	opts = opts or {}
	local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
	btn:SetHeight(opts.height or 24)
	btn:SetWidth(opts.width or 80)
	btn:RegisterForClicks("LeftButtonUp")
	btn:EnableMouse(true)
	ns.Skin.ApplyFlatBackdrop(btn, C.bgRaised, C.borderSoft)

	btn.label = btn:CreateFontString(nil, "OVERLAY", opts.font or "GameFontHighlight")
	btn.label:SetPoint("CENTER", 0, 0)
	btn.label:SetJustifyH("CENTER")
	if opts.text then
		btn.label:SetText(opts.text)
	end

	btn.isActive = false
	btn.SetActive = function(self, active)
		self.isActive = not not active
		PaintButton(self, "idle")
	end
	btn.SetText = function(self, text)
		self.label:SetText(text)
		local pad = opts.padX or 16
		local w = (self.label:GetStringWidth() or 40) + pad
		if opts.minWidth then
			w = max(opts.minWidth, w)
		end
		if not opts.width then
			self:SetWidth(w)
		end
	end
	btn.GetTextWidth = function(self)
		return self.label:GetStringWidth()
	end
	-- Re-paint after accent changes (Refresh calls this on visible pills).
	btn.RefreshSkin = function(self)
		PaintButton(self, "idle")
	end

	btn:SetScript("OnEnter", function(self)
		PaintButton(self, "hover")
	end)
	btn:SetScript("OnLeave", function(self)
		PaintButton(self, "idle")
	end)

	PaintButton(btn, "idle")
	return btn
end

function ns.Skin.CreateCloseButton(parent)
	local btn = ns.Skin.CreateFlatButton(parent, {
		width = 24,
		height = 24,
		text = "×",
		font = "GameFontNormalLarge",
		padX = 0,
	})
	btn.label:SetTextColor(Unpack(C.textMuted))
	btn:SetScript("OnEnter", function(self)
		self:SetBackdropColor(Unpack(accent))
		self:SetBackdropBorderColor(Unpack(accent))
		self.label:SetTextColor(Unpack(C.white))
	end)
	btn:SetScript("OnLeave", function(self)
		self:SetBackdropColor(Unpack(C.bgRaised))
		self:SetBackdropBorderColor(Unpack(C.borderSoft))
		self.label:SetTextColor(Unpack(C.textMuted))
	end)
	return btn
end

function ns.Skin.CreateInset(parent)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	ns.Skin.ApplyFlatBackdrop(f, C.bgInset, C.borderSoft)
	return f
end

-- Flat 1px-border icon chip (same chrome as buttons/panels). Hover → spell tip.
function ns.Skin.CreateIconBox(parent, size)
	size = size or 16
	local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
	f:SetSize(size, size)
	f:EnableMouse(true)
	f:RegisterForClicks("LeftButtonUp")
	ns.Skin.ApplyFlatBackdrop(f, C.bgInset, C.borderSoft)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 1, -1)
	f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	f.SetIconTexture = function(self, tex)
		if tex then
			self.icon:SetTexture(tex)
			self.icon:Show()
		else
			self.icon:Hide()
		end
	end

	f:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(Unpack(accent))
		if self.spellID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetSpellByID(self.spellID)
			GameTooltip:Show()
		end
	end)
	f:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(Unpack(C.borderSoft))
		GameTooltip:Hide()
	end)

	return f
end
