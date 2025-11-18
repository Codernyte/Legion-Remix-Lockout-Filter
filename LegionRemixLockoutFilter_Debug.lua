--######################################################################
-- LegionRemixLockoutFilter_Debug.lua
-- Standalone debug window + /lrlf debug toggle + LRLF_DebugPrint()
--######################################################################

local ADDON_NAME, ADDON_TABLE = ...

----------------------------------------------------------------------
-- Internal state
----------------------------------------------------------------------

local debugFrame       = nil
local debugScrollFrame = nil
local debugEditBox     = nil
local debugLines       = {}
local internalChanging = false

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function DebugTrim(msg)
    if type(msg) ~= "string" then
        return ""
    end
    if strtrim then
        return strtrim(msg)
    end
    return msg:match("^%s*(.-)%s*$") or msg
end

local function DebugGetFullText()
    return table.concat(debugLines, "\n")
end

-- Ensure edit box text matches our buffer and is scrollable
local function DebugRefreshText()
    if not debugEditBox or not debugScrollFrame then
        return
    end

    internalChanging = true
    debugEditBox:SetText(DebugGetFullText())
    internalChanging = false

    -- Resize edit box so scrolling works properly
    local textHeight = 0
    if debugEditBox.GetTextHeight then
        textHeight = debugEditBox:GetTextHeight() or 0
    end
    if textHeight < 1 then
        textHeight = 1
    end
    debugEditBox:SetHeight(textHeight + 20)

    -- Scroll to bottom
    debugScrollFrame:UpdateScrollChildRect()
    local maxScroll = debugScrollFrame:GetVerticalScrollRange() or 0
    debugScrollFrame:SetVerticalScroll(maxScroll)
end

----------------------------------------------------------------------
-- Global debug print function
-- Adds a line of text to the debug buffer and updates the window
----------------------------------------------------------------------

function LRLF_DebugPrint(message)
    if message == nil then
        return
    end

    if type(message) ~= "string" then
        message = tostring(message)
    end

    table.insert(debugLines, message)

    -- Simple cap to avoid unbounded growth
    local maxLines = 2000
    if #debugLines > maxLines then
        local excess = #debugLines - maxLines
        for i = 1, excess do
            table.remove(debugLines, 1)
        end
    end

    if debugEditBox and debugScrollFrame then
        DebugRefreshText()
    end
end

----------------------------------------------------------------------
-- Create debug window (only once)
----------------------------------------------------------------------

local function CreateDebugWindow()
    if debugFrame then
        return
    end

    local f = CreateFrame("Frame", "LRLF_DebugFrame", UIParent, "BasicFrameTemplateWithInset")
    debugFrame = f

    -- Wider and taller debug window
    f:SetSize(750, 350)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
    f.title:SetText("LRLF Debug")

    -- Close button
    local close = f.CloseButton or _G[f:GetName() .. "CloseButton"]
    if close then
        close:SetScript("OnClick", function()
            f:Hide()
        end)
    end

    ------------------------------------------------------------------
    -- Scroll frame + read-only edit box
    ------------------------------------------------------------------

    local scroll = CreateFrame("ScrollFrame", "LRLF_DebugScrollFrame", f, "UIPanelScrollFrameTemplate")
    debugScrollFrame = scroll

    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 50)

    local editBox = CreateFrame("EditBox", "LRLF_DebugEditBox", scroll)
    debugEditBox = editBox

    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal" or "GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetWidth(scroll:GetWidth())

    -- Make it effectively read-only: cancel user edits
    editBox:SetScript("OnChar", function(self)
        self:ClearFocus()
    end)

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput or internalChanging then
            return
        end

        -- Revert any user-typed changes
        internalChanging = true
        self:SetText(DebugGetFullText())
        internalChanging = false
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    scroll:SetScrollChild(editBox)

    ------------------------------------------------------------------
    -- Buttons: Clear + Test
    ------------------------------------------------------------------

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    clearBtn:SetText("Clear")

    clearBtn:SetScript("OnClick", function()
        debugLines = {}
        DebugRefreshText()
    end)

    local testBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    testBtn:SetSize(120, 22)
    testBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    testBtn:SetText("Test Fill")

    testBtn:SetScript("OnClick", function()
        for i = 1, 100 do
            LRLF_DebugPrint(string.format("Lorem ipsum dolor sit amet %d", i))
        end
    end)

    -- Start hidden; slash command will toggle it
    f:Hide()

    -- Initial refresh
    DebugRefreshText()
end

----------------------------------------------------------------------
-- Global toggle function for the debug window
----------------------------------------------------------------------

function LRLF_ToggleDebugWindow()
    if not debugFrame then
        CreateDebugWindow()
    end

    if debugFrame:IsShown() then
        debugFrame:Hide()
    else
        debugFrame:Show()
        DebugRefreshText()
    end
end

----------------------------------------------------------------------
-- Slash command: /lrlf debug
----------------------------------------------------------------------

SLASH_LRLF1 = "/lrlf"

SlashCmdList["LRLF"] = function(msg)
    msg = DebugTrim(msg):lower()

    if msg == "debug" or msg == "dbg" then
        LRLF_ToggleDebugWindow()
    else
        print("|cff00ff00[LRLF]|r Usage: /lrlf debug")
    end
end
