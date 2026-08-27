--[[
	StatPriorityFirst - Copy URL helper
	----
	LaunchURL is protected (ADDON_ACTION_FORBIDDEN). We copy + show a paste popup.
--]]

local _, ns = ...
local L = ns.L

ns.UI = ns.UI or {}

local StaticPopup_Show = rawget(_G, "StaticPopup_Show")
local StaticPopupDialogs = rawget(_G, "StaticPopupDialogs")
local CopyToClipboard = rawget(_G, "CopyToClipboard")
local OKAY = rawget(_G, "OKAY")

local POPUP = "STATPRIORITYFIRST_COPY_URL"

local function EnsurePopup()
	if not StaticPopupDialogs or StaticPopupDialogs[POPUP] then
		return
	end
	StaticPopupDialogs[POPUP] = {
		text = L["COPY_URL_PROMPT"],
		button1 = OKAY or "Okay",
		hasEditBox = true,
		editBoxWidth = 360,
		hideOnEscape = true,
		timeout = 0,
		whileDead = true,
		preferredIndex = 3,
		OnShow = function(self, data)
			local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
			if eb then
				eb:SetText(data or "")
				eb:HighlightText()
				eb:SetFocus()
			end
		end,
		EditBoxOnEscapePressed = function(eb)
			eb:GetParent():Hide()
		end,
	}
end

--- Copy url to clipboard when allowed, then show an edit-box popup for Ctrl+C.
function ns.UI.ShowCopyURL(url)
	if not url or url == "" then
		return
	end
	if CopyToClipboard then
		pcall(CopyToClipboard, url)
	end
	EnsurePopup()
	if StaticPopupDialogs and StaticPopup_Show then
		StaticPopup_Show(POPUP, nil, nil, url)
	else
		print(url)
	end
end
