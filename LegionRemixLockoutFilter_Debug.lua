--######################################################################
-- LegionRemixLockoutFilter_Debug.lua
-- Debug log window + logging helpers
--######################################################################

local ADDON_NAME, ADDON_TABLE = ...

-- Global debug flags/state (can later be moved to SavedVariables if desired)
LRLF_DebugEnabled = (LRLF_DebugEnabled ~= false)
LRLF_DebugLines   = LRLF_DebugLines or {}

local MAX_LINES   = 2000

local debugFrame
local scrollFrame
local editBox

--------------------------------------------------
-- Internal helpers
--------------------------------------------------

local function RebuildLogText()
    if not editBox then
        return
    end

    local buf = {}
    for i, line in ipairs(LRLF_DebugLines) do
        buf[#buf + 1] = line
    end

    local text = table.concat(buf, "\n")
    editBox:SetText(text)

    -- leave cursor at top; user can scroll
    editBox:HighlightText(0, 0)
end

--------------------------------------------------
-- Global logging function
--------------------------------------------------

function LRLF_DebugLog(msg)
    if not LRLF_DebugEnabled then
        return
    end

    if type(msg) ~= "string" then
        msg = tostring(msg)
    end

    local timeStr = date("%H:%M:%S")
    local line    = string.format("[%s] %s", timeStr, msg)

    table.insert(LRLF_DebugLines, line)

    -- Trim to max size
    if #LRLF_DebugLines > MAX_LINES then
        local overflow = #LRLF_DebugLines - MAX_LINES
        for i = 1, overflow do
            table.remove(LRLF_DebugLines, 1)
        end
    end

    if scrollFrame and editBox then
        local prevScroll = scrollFrame:GetVerticalScroll() or 0
        RebuildLogText()

        -- auto-scroll to bottom if user was already near the bottom
        local max = scrollFrame:GetVerticalScrollRange() or 0
        if prevScroll >= max - 50 then
            scrollFrame:SetVerticalScroll(max)
        end
    end
end

--------------------------------------------------
-- Debug window UI
--------------------------------------------------

local function CreateDebugWindow()
    if debugFrame then
        return
    end

    debugFrame = CreateFrame("Frame", "LRLF_DebugFrame", UIParent, "BasicFrameTemplateWithInset")
    debugFrame:SetSize(700, 400)
    debugFrame:SetPoint("CENTER")
    debugFrame:Hide()

    -- Make the debug window movable
    debugFrame:SetMovable(true)
    debugFrame:EnableMouse(true)
    debugFrame:RegisterForDrag("LeftButton")
    debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
    debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)

    debugFrame.title = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugFrame.title:SetPoint("CENTER", debugFrame.TitleBg, "CENTER", 0, 0)
    debugFrame.title:SetText("Legion Remix Lockout Filter - Debug Log")

    -- "Clear" button in the title bar (not in the text body)
    local clearButton = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
    clearButton:SetSize(60, 18)
    clearButton:SetText("Clear")
    -- Anchor inside the title bar, a bit left of the close button
    clearButton:SetPoint("RIGHT", debugFrame.TitleBg, "RIGHT", -60, 0)
    clearButton:SetScript("OnClick", function()
        -- Wipe the current log buffer and refresh the view
        wipe(LRLF_DebugLines)
        RebuildLogText()
        if scrollFrame then
            scrollFrame:SetVerticalScroll(0)
        end
    end)

    -- Scrollframe + edit box for log text
    scrollFrame = CreateFrame("ScrollFrame", "LRLF_DebugScrollFrame", debugFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", debugFrame, "BOTTOMRIGHT", -30, 10)

    editBox = CreateFrame("EditBox", "LRLF_DebugEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(650)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    scrollFrame:SetScrollChild(editBox)

    -- Allow closing with Esc
    table.insert(UISpecialFrames, debugFrame:GetName())

    RebuildLogText()
end

function LRLF_ToggleDebugWindow()
    if not debugFrame then
        CreateDebugWindow()
    end

    if debugFrame:IsShown() then
        debugFrame:Hide()
    else
        debugFrame:Show()
    end
end

--------------------------------------------------
-- Error capture: only log errors from this addon
--------------------------------------------------

do
    local origHandler = geterrorhandler()

    seterrorhandler(function(msg)
        if type(msg) == "string" then
            -- Only log if it looks like it's from this addon
            if msg:find("LegionRemixLockoutFilter")
               or (ADDON_NAME and msg:find(ADDON_NAME))
            then
                LRLF_DebugLog("Lua error: " .. msg)
            end
        end

        if origHandler then
            origHandler(msg)
        end
    end)
end

--------------------------------------------------
-- Initial marker
--------------------------------------------------

LRLF_DebugLog("Debug system initialized.")
