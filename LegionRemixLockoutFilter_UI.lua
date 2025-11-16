-- LegionRemixLockoutFilter_UI.lua
-- UI: side panel, rows, filter controls, toggle tab

local ADDON_NAME, ADDON_TABLE = ...

-- Uses global state defined in main:
--   LRLFFrame, LRLF_FilterState, LRLF_SystemSelection, LRLF_Rows,
--   LRLF_FilterButtons, LRLF_FilterEnabled, LRLF_SearchButton,
--   LRLF_ToggleButton, LRLF_UserCollapsed, LRLF_LastSearchWasFiltered
--
-- Uses LFG helper module:
--   ADDON_TABLE.LFG (as LRLF_LFG)
--   LRLF_LFG.BuildRaidDifficultyInfo()
--   LRLF_LFG.BuildDungeonDifficultyInfo()
--
-- Uses utility:
--   LRLF_FormatTimeRemaining(lockoutSeconds)  -- assumed available

local LRLF_LFG = ADDON_TABLE.LFG or {}

--------------------------------------------------
-- Internal helpers for rows / tooltips
--------------------------------------------------

local DIFF_ORDER     = { "Normal", "Heroic", "Mythic" }
local DIFF_SHORTTEXT = { Normal = "Normal", Heroic = "Heroic", Mythic = "Mythic" }

local function LRLF_ClearRowsForKind(kind)
    local rows = LRLF_Rows and LRLF_Rows[kind]
    if not rows then return end
    for _, row in ipairs(rows) do
        row:Hide()
    end
end

local function LRLF_UpdateRowAllCheckbox(row, instState)
    if not row or not row.allCheck then return end

    local anyTrue = false
    if instState then
        for _, diffName in ipairs(DIFF_ORDER) do
            if instState[diffName] then
                anyTrue = true
                break
            end
        end
    end

    row.allCheck:SetChecked(anyTrue)
end

-- Store per-difficulty status on the row so we can drive tooltips and dimming
local function LRLF_SetDiffStatus(row, diffName, isReady, isLocked, isUnavailable, lockoutReset)
    row.diffStatus = row.diffStatus or {}
    row.diffStatus[diffName] = {
        isReady       = isReady and true or false,
        isLocked      = isLocked and true or false,
        isUnavailable = isUnavailable and true or false,
        lockoutReset  = lockoutReset,
    }
end

local function LRLF_SetDifficultyTooltip(owner, row, diffName)
    if not row or not diffName then return end
    local status = row.diffStatus and row.diffStatus[diffName]

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

    if not status then
        GameTooltip:SetText("Currently unavailable", 0.8, 0.8, 0.8)
        GameTooltip:Show()
        return
    end

    if status.isUnavailable then
        GameTooltip:SetText("Currently unavailable", 0.8, 0.8, 0.8)
    elseif status.isLocked then
        local text = "Locked"
        if status.lockoutReset and status.lockoutReset > 0 and type(LRLF_FormatTimeRemaining) == "function" then
            text = "Locked: " .. LRLF_FormatTimeRemaining(status.lockoutReset) .. " remaining"
        else
            text = "Locked: time remaining"
        end
        GameTooltip:SetText(text, 1.0, 0.3, 0.3)
    elseif status.isReady then
        GameTooltip:SetText("Ready to join", 0.2, 1.0, 0.2)
    else
        GameTooltip:SetText("Currently unavailable", 0.8, 0.8, 0.8)
    end

    GameTooltip:Show()
end

local function LRLF_Diff_OnEnter(self)
    if not self.row or not self.diffName then return end
    LRLF_SetDifficultyTooltip(self, self.row, self.diffName)
end

local function LRLF_Diff_OnLeave(self)
    GameTooltip:Hide()
end

--------------------------------------------------
-- Checkbox handlers
--------------------------------------------------

local function LRLF_OnAllCheckboxClick(self)
    local row = self:GetParent()
    if not row or not row.instanceName or not row.kind then return end

    local instName = row.instanceName
    local kind     = row.kind

    LRLF_FilterState[kind]       = LRLF_FilterState[kind]       or {}
    LRLF_SystemSelection[kind]   = LRLF_SystemSelection[kind]   or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local instState = filterKind[instName]
    local sysInst   = sysKind[instName]

    local checked = self:GetChecked() and true or false

    for _, diffName in ipairs(DIFF_ORDER) do
        local cb = row.diffChecks[diffName]
        if cb and cb:IsEnabled() then
            cb:SetChecked(checked)
            instState[diffName] = checked
            sysInst[diffName]   = false -- user-managed now
        end
    end

    LRLF_UpdateRowAllCheckbox(row, instState)
end

local function LRLF_OnDifficultyCheckboxClick(self)
    local row = self.row
    if not row or not row.instanceName or not row.kind or not self.diffName then return end

    local instName = row.instanceName
    local kind     = row.kind
    local diffName = self.diffName

    LRLF_FilterState[kind]       = LRLF_FilterState[kind]       or {}
    LRLF_SystemSelection[kind]   = LRLF_SystemSelection[kind]   or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local instState = filterKind[instName]
    local sysInst   = sysKind[instName]

    local checked = self:GetChecked() and true or false
    instState[diffName] = checked
    sysInst[diffName]   = false -- user-managed

    LRLF_UpdateRowAllCheckbox(row, instState)
end

--------------------------------------------------
-- Filter enabled/disabled visual
--------------------------------------------------

local function LRLF_SetRowInteractive(row, enabled)
    if not row then return end

    -- Instance name
    if row.nameText then
        if enabled then
            if row.isAllUnavailable then
                row.nameText:SetFontObject("GameFontDisable")
                row.nameText:SetTextColor(0.5, 0.5, 0.5)
            else
                row.nameText:SetFontObject("GameFontNormal")
                row.nameText:SetTextColor(1, 0.82, 0)
            end
        else
            row.nameText:SetFontObject("GameFontDisable")
            row.nameText:SetTextColor(0.6, 0.6, 0.6)
        end
    end

    -- "All" checkbox
    if row.allCheck then
        if enabled and not row.isAllUnavailable then
            row.allCheck:Enable()
            row.allCheck:SetAlpha(1.0)
        else
            row.allCheck:Disable()
            row.allCheck:SetAlpha(0.4)
        end
    end

    -- Difficulty checkboxes + labels
    if row.diffChecks and row.diffLabels then
        for diffName, cb in pairs(row.diffChecks) do
            local label  = row.diffLabels[diffName]
            local status = row.diffStatus and row.diffStatus[diffName]

            local isUnavailable = status and status.isUnavailable
            if enabled and not isUnavailable and not row.isAllUnavailable then
                cb:Enable()
                cb:SetAlpha(1.0)
            else
                cb:Disable()
                cb:SetAlpha(0.4)
            end

            if label then
                if not status then
                    label:SetFontObject(enabled and "GameFontHighlightSmall" or "GameFontDisable")
                    label:SetTextColor(0.7, 0.7, 0.7)
                else
                    if enabled then
                        label:SetFontObject("GameFontHighlightSmall")
                        if status.isUnavailable then
                            label:SetFontObject("GameFontDisable")
                            label:SetTextColor(0.5, 0.5, 0.5)
                        elseif status.isLocked then
                            label:SetTextColor(1.0, 0.2, 0.2)
                        elseif status.isReady then
                            label:SetTextColor(0.0, 1.0, 0.0)
                        else
                            label:SetTextColor(0.7, 0.7, 0.7)
                        end
                    else
                        label:SetFontObject("GameFontDisable")
                        label:SetTextColor(0.6, 0.6, 0.6)
                    end
                end
            end
        end
    end
end

local function LRLF_UpdateFilterEnabledVisualState()
    local enabled = (LRLF_FilterEnabled ~= false)
    LRLF_FilterEnabled = enabled

    if LRLF_FilterButtons and LRLF_FilterButtons.apply then
        LRLF_FilterButtons.apply:SetAlpha(enabled and 1.0 or 0.4)
    end

    if LRLFFrame then
        -- Top difficulty buttons
        if LRLFFrame.topButtons then
            for _, btn in pairs(LRLFFrame.topButtons) do
                if enabled then
                    btn:Enable()
                    btn:SetAlpha(1.0)
                else
                    btn:Disable()
                    btn:SetAlpha(0.4)
                end
            end
        end

        -- Search button at bottom
        if LRLF_SearchButton then
            if enabled then
                LRLF_SearchButton:Enable()
                LRLF_SearchButton:SetAlpha(1.0)
            else
                LRLF_SearchButton:Disable()
                LRLF_SearchButton:SetAlpha(0.4)
            end
        end

        -- Rows
        if LRLF_Rows then
            for _, kind in ipairs({ "raid", "dungeon" }) do
                local rows = LRLF_Rows[kind]
                if rows then
                    for _, row in ipairs(rows) do
                        LRLF_SetRowInteractive(row, enabled)
                    end
                end
            end
        end
    end
end

--------------------------------------------------
-- Reset filters to defaults (ready-only) for current kind
--------------------------------------------------

function LRLF_ResetAllFilters()
    LRLF_FilterState     = { raid = {}, dungeon = {} }
    LRLF_SystemSelection = { raid = {}, dungeon = {} }

    if not LRLFFrame or not LRLFFrame:IsShown() or not LFGListFrame or not LFGListFrame.SearchPanel then
        return
    end

    local searchPanel = LFGListFrame.SearchPanel
    local categoryID  = searchPanel.categoryID
    local kind = (categoryID == 2 and "dungeon")
              or (categoryID == 3 and "raid")
              or "raid"

    LRLF_RefreshSidePanelText(kind)
end

--------------------------------------------------
-- Side panel window creation
--------------------------------------------------

local function LRLF_GetCurrentKind()
    if not LFGListFrame or not LFGListFrame.SearchPanel then
        return "raid"
    end
    local categoryID = LFGListFrame.SearchPanel.categoryID
    if categoryID == 2 then
        return "dungeon"
    elseif categoryID == 3 then
        return "raid"
    else
        return "raid"
    end
end

local function LRLF_BatchSelectDifficulty(kind, which)
    if kind ~= "raid" and kind ~= "dungeon" then return end

    local infoMap, list
    if kind == "dungeon" then
        infoMap, list = LRLF_LFG.BuildDungeonDifficultyInfo()
    else
        infoMap, list = LRLF_LFG.BuildRaidDifficultyInfo()
    end

    if not infoMap or not list then return end

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    for _, entry in ipairs(list) do
        local info = infoMap[entry.name]
        if info and info.difficulties then
            local instName  = info.name or entry.name
            local instState = filterKind[instName] or {}
            filterKind[instName] = instState

            local sysInst   = sysKind[instName] or {}
            sysKind[instName] = sysInst

            for _, diffName in ipairs(DIFF_ORDER) do
                local d = info.difficulties[diffName]
                if d then
                    local isReady  = (d.available and not d.hasLockout)
                    local selectIt = false

                    if which == "All" then
                        selectIt = isReady
                    elseif which == diffName then
                        selectIt = isReady
                    else
                        selectIt = false
                    end

                    instState[diffName] = selectIt
                    sysInst[diffName]   = false  -- user-managed
                end
            end
        end
    end

    LRLF_RefreshSidePanelText(kind)
end

function LRLF_CreateSideWindow()
    if LRLFFrame then return end

    local f = CreateFrame("Frame", "LRLFFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetWidth(260)
    f:EnableMouse(true)
    f:SetFrameStrata("HIGH")
    f:SetPoint("CENTER")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
    f.title:SetText("Lockout Filter")

    -- Top difficulty buttons (All / Normal / Heroic / Mythic)
    f.topButtons = {}

    local function CreateTopButton(key, label, xOffset)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(60, 24) -- slightly larger
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", xOffset, -28)
        btn:SetText(label)
        f.topButtons[key] = btn
        return btn
    end

    local btnAll    = CreateTopButton("All",    "All",    10)
    local btnNormal = CreateTopButton("Normal", "Normal", 10 + 60 + 2)
    local btnHeroic = CreateTopButton("Heroic", "Heroic", 10 + (60 + 2) * 2)
    local btnMythic = CreateTopButton("Mythic", "Mythic", 10 + (60 + 2) * 3)

    btnAll:SetScript("OnClick", function()
        local kind = LRLF_GetCurrentKind()
        LRLF_BatchSelectDifficulty(kind, "All")
    end)

    btnNormal:SetScript("OnClick", function()
        local kind = LRLF_GetCurrentKind()
        LRLF_BatchSelectDifficulty(kind, "Normal")
    end)

    btnHeroic:SetScript("OnClick", function()
        local kind = LRLF_GetCurrentKind()
        LRLF_BatchSelectDifficulty(kind, "Heroic")
    end)

    btnMythic:SetScript("OnClick", function()
        local kind = LRLF_GetCurrentKind()
        LRLF_BatchSelectDifficulty(kind, "Mythic")
    end)

    -- ScrollFrame below the top buttons
    local scrollFrame = CreateFrame("ScrollFrame", "LRLF_ScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    scrollFrame:EnableMouse(true)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current   = self:GetVerticalScroll()
        local step      = 20
        local maxScroll = self:GetVerticalScrollRange() or 0
        local new       = current - (delta * step)
        if new < 0 then new = 0 end
        if new > maxScroll then new = maxScroll end
        self:SetVerticalScroll(new)
    end)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollFrame:SetScrollChild(content)

    local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetText("")

    -- Header for 'Currently unavailable' section (created once, positioned in refresh)
    local unavailableHeader = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    unavailableHeader:SetText("|cffb0b0b0|cffffffff|r") -- placeholder; real text set in refresh
    unavailableHeader:SetJustifyH("CENTER")
    unavailableHeader:SetText("")
    unavailableHeader:Hide()

    f.text               = text
    f.scrollFrame        = scrollFrame
    f.unavailableHeader  = unavailableHeader
    f.content            = content

    -- Search button on bottom
    local searchButton = CreateFrame("Button", "LRLF_SearchButton", f, "UIPanelButtonTemplate")
    searchButton:SetHeight(32)
    searchButton:ClearAllPoints()
    searchButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    searchButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    searchButton:SetText("Search with Lockout Filters")

    searchButton:SetScript("OnClick", function(self)
        if not LRLF_IsTimerunner or not LRLF_IsTimerunner() then
            return
        end
        if not LFGListFrame or not LFGListFrame.SearchPanel then
            return
        end

        local searchPanel = LFGListFrame.SearchPanel
        local categoryID  = searchPanel.categoryID
        local isDungeon   = (categoryID == 2)
        local isRaid      = (categoryID == 3)

        if not searchPanel:IsShown() or (not isDungeon and not isRaid) then
            UIErrorsFrame:AddMessage("Lockout Filter: Open Legion Dungeons or Raids search first.", 1.0, 0.1, 0.1)
            return
        end

        LRLF_LastSearchWasFiltered = true

        if type(LFGListSearchPanel_DoSearch) == "function" then
            LFGListSearchPanel_DoSearch(searchPanel)
        end
    end)

    LRLF_SearchButton = searchButton

    local close = f.CloseButton or _G[f:GetName() .. "CloseButton"]
    if close then
        close:HookScript("OnClick", function()
            LRLF_UserCollapsed = true
            LRLF_UpdateVisibility()
        end)
    end

    f:Hide()
    LRLFFrame = f

    -- Initial visual state based on LRLF_FilterEnabled
    LRLF_UpdateFilterEnabledVisualState()
end

--------------------------------------------------
-- Filter control icons to the right of the panel
--------------------------------------------------

function LRLF_CreateFilterButtons()
    if (LRLF_FilterButtons and LRLF_FilterButtons.apply) or not LRLFFrame then
        return
    end

    LRLF_FilterButtons = LRLF_FilterButtons or {}

    local ICON_SIZE = 24

    local bg = CreateFrame("Frame", "LRLF_FilterIconBackground", LRLFFrame, "BackdropTemplate")
    bg:SetFrameStrata("HIGH")
    bg:SetSize(32, ICON_SIZE * 2 + 10)
    bg:ClearAllPoints()
    -- Anchor more in line with the body, not up by the close button
    bg:SetPoint("TOPLEFT", LRLFFrame, "TOPRIGHT", 0, -40)
    bg:SetPoint("BOTTOMLEFT", LRLFFrame, "TOPRIGHT", 0, -40 - (ICON_SIZE * 2 + 10))

    bg:SetBackdrop({
        bgFile   = "Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16,
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bg:SetBackdropColor(0, 0, 0, 0.85)
    bg:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)

    -- Spyglass = master filter enable/disable
    local apply = CreateFrame("Button", "LRLF_FilterApplyIcon", bg)
    apply:SetSize(ICON_SIZE, ICON_SIZE)
    apply:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)

    local applyTex = apply:CreateTexture(nil, "ARTWORK")
    applyTex:SetAllPoints()
    applyTex:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    apply.icon = applyTex

    apply:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local title = LRLF_FilterEnabled and "Lockout Filter Enabled" or "Lockout Filter Disabled"
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine("Click to toggle whether the lockout filter affects the search results.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    apply:SetScript("OnLeave", function() GameTooltip:Hide() end)

    apply:SetScript("OnClick", function(self)
        LRLF_FilterEnabled = not LRLF_FilterEnabled
        LRLF_UpdateFilterEnabledVisualState()

        -- Re-run the current search so results immediately reflect the new state
        if LRLF_IsTimerunner and LRLF_IsTimerunner()
            and LFGListFrame and LFGListFrame.SearchPanel
            and LFGListSearchPanel_DoSearch
        then
            local searchPanel = LFGListFrame.SearchPanel
            if searchPanel:IsShown() then
                if LRLF_FilterEnabled then
                    LRLF_LastSearchWasFiltered = true
                else
                    LRLF_LastSearchWasFiltered = false
                end
                LFGListSearchPanel_DoSearch(searchPanel)
            end
        end
    end)

    -- Settings icon: 1-click signup toggle
    local settings = CreateFrame("Button", "LRLF_OneClickSettingsIcon", bg)
    settings:SetSize(ICON_SIZE, ICON_SIZE)
    settings:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4 - ICON_SIZE - 4)

    local settingsTex = settings:CreateTexture(nil, "ARTWORK")
    settingsTex:SetAllPoints()
    settingsTex:SetTexture("Interface\\CURSOR\\Point")
    settings.icon = settingsTex

    local function UpdateSettingsAlpha()
        if LRLF_OneClickSignupEnabled then
            settings:SetAlpha(1.0)
        else
            settings:SetAlpha(0.4)
        end
    end
    UpdateSettingsAlpha()

    settings:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("1-Click Signup", 1, 1, 1)
        GameTooltip:AddLine("Toggle 1-click signup for Legion Remix Lockout Filter.", nil, nil, nil, true)
        GameTooltip:AddLine("• Left-click a group: instantly sign up with your currently selected roles.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("• Shift+click: sign up as all roles your character is eligible for.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("• Ctrl+Shift+click: use normal Blizzard behavior (no auto signup).", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    settings:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    settings:SetScript("OnClick", function(self)
        LRLF_OneClickSignupEnabled = not LRLF_OneClickSignupEnabled
        UpdateSettingsAlpha()
    end)

    LRLF_FilterButtons.apply    = apply
    LRLF_FilterButtons.bg       = bg
    LRLF_FilterButtons.settings = settings

    apply:Hide()
    bg:Hide()
    settings:Hide()

    LRLF_UpdateFilterEnabledVisualState()
end

--------------------------------------------------
-- Eyeball toggle button on the side of LFGListFrame
--------------------------------------------------

function LRLF_CreateToggleButton()
    if LRLF_ToggleButton or not LFGListFrame then return end

    local b = CreateFrame("Button", "LRLF_ToggleButton", LFGListFrame)
    b:SetSize(38, 38)
    b:SetPoint("TOPLEFT", LFGListFrame, "TOPRIGHT", 0, 0)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(LFGListFrame:GetFrameLevel() + 10)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Eye_01")
    b.icon = icon

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Legion Remix Lockout Filter", 1, 1, 1)
        GameTooltip:AddLine("Show the Lockout Filter panel.", nil, nil, nil, true)
        GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    b:SetScript("OnClick", function(self)
        LRLF_UserCollapsed = false
        LRLF_UpdateVisibility()
    end)

    LRLF_ToggleButton = b
end

--------------------------------------------------
-- Attach panel to LFGListFrame
--------------------------------------------------

function LRLF_AttachToPremade()
    if not LRLFFrame or not LFGListFrame then
        return
    end

    LRLFFrame:SetParent(LFGListFrame)
    LRLFFrame:ClearAllPoints()
    LRLFFrame:SetPoint("TOPLEFT", LFGListFrame, "TOPRIGHT", 5, 0)
    LRLFFrame:SetPoint("BOTTOMLEFT", LFGListFrame, "BOTTOMRIGHT", 5, 0)

    LRLF_CreateFilterButtons()

    if not LRLF_ToggleButton then
        LRLF_CreateToggleButton()
    end
end

--------------------------------------------------
-- Refresh the side panel rows for raids/dungeons
--------------------------------------------------

function LRLF_RefreshSidePanelText(kind)
    if not LRLFFrame or not LRLFFrame.text then
        return
    end

    kind = kind or "raid"

    local infoMap, list, ejErr, lfgErr
    local labelPlural

    if kind == "dungeon" then
        infoMap, list, ejErr, lfgErr = LRLF_LFG.BuildDungeonDifficultyInfo()
        labelPlural = "dungeons"
    else
        infoMap, list, ejErr, lfgErr = LRLF_LFG.BuildRaidDifficultyInfo()
        labelPlural = "raids"
    end

    local lines = {}

    if ejErr then
        table.insert(lines, "|cffffd100EJ (" .. labelPlural .. "):|r " .. ejErr)
    end
    if lfgErr then
        table.insert(lines, "|cffffd100LFG (" .. labelPlural .. "):|r " .. lfgErr)
    end
    if ejErr or lfgErr then
        table.insert(lines, "")
    end

    if (not list) or (#list == 0) then
        table.insert(lines, "No Legion " .. labelPlural .. " found.")
        LRLFFrame.text:SetText(table.concat(lines, "\n"))

        LRLF_ClearRowsForKind("raid")
        LRLF_ClearRowsForKind("dungeon")

        local textFS  = LRLFFrame.text
        local content = LRLFFrame.scrollFrame:GetScrollChild()
        local height  = (textFS:GetStringHeight() or 0) + 20
        if height < 1 then height = 1 end
        content:SetHeight(height)
        content:SetWidth(LRLFFrame.scrollFrame:GetWidth())
        LRLFFrame.scrollFrame:UpdateScrollChildRect()
        return
    end

    LRLFFrame.text:SetText(table.concat(lines, "\n") or "")

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    -- Figure out which instances are all-unavailable and which have at least one ready/locked
    local availableEntries   = {}
    local unavailableEntries = {}

    for _, entry in ipairs(list) do
        local info = infoMap[entry.name]
        if info and info.difficulties then
            local hasAnyAvailableOrLocked = false
            for _, diffName in ipairs(DIFF_ORDER) do
                local d = info.difficulties[diffName]
                if d and (d.available or d.hasLockout) then
                    hasAnyAvailableOrLocked = true
                    break
                end
            end

            if hasAnyAvailableOrLocked then
                table.insert(availableEntries, entry)
            else
                table.insert(unavailableEntries, entry)
            end
        end
    end

    -- Initialize instance states with ready-only defaults where needed
    for _, entry in ipairs(list) do
        local info = infoMap[entry.name]
        if info then
            local instName  = info.name or entry.name
            local instState = filterKind[instName]
            if not instState then
                instState = {}
                filterKind[instName] = instState
            end
            local sysInst = sysKind[instName]
            if not sysInst then
                sysInst = {}
                sysKind[instName] = sysInst
            end

            local diffs = info.difficulties
            for _, diffName in ipairs(DIFF_ORDER) do
                local d = diffs[diffName]
                if d then
                    local isReady       = (d.available and not d.hasLockout)
                    local isUnavailable = (not d.available and not d.hasLockout)

                    if instState[diffName] == nil then
                        -- Default to ready-only
                        instState[diffName] = isReady
                        sysInst[diffName]   = true
                    else
                        -- If system-managed, keep in sync with ready-only; otherwise user-managed
                        if sysInst[diffName] then
                            instState[diffName] = isReady
                        end
                    end

                    if isUnavailable and instState[diffName] then
                        instState[diffName] = false
                    end
                end
            end
        end
    end

    -- Clear existing rows for both kinds, we will rebuild for this kind
    LRLF_ClearRowsForKind("raid")
    LRLF_ClearRowsForKind("dungeon")

    LRLF_Rows[kind] = LRLF_Rows[kind] or {}
    local rowsByKind = LRLF_Rows[kind]

    local textFS     = LRLFFrame.text
    local textHeight = textFS:GetStringHeight() or 0
    local content    = LRLFFrame.scrollFrame:GetScrollChild()
    local y          = -textHeight - 8

    local rowHeight  = 34
    local spacing    = 4

    local function EnsureRow(index)
        local row = rowsByKind[index]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row.diffChecks  = {}
            row.diffLabels  = {}
            row.activeDiffs = {}
            rowsByKind[index] = row
        end
        row:Show()
        row.diffStatus = row.diffStatus or {}
        return row
    end

    local rowIndex = 1

    -- Build rows for available entries (with difficulties)
    for _, entry in ipairs(availableEntries) do
        local info = infoMap[entry.name]
        if info then
            local instName  = info.name or entry.name
            local diffs     = info.difficulties
            local instState = filterKind[instName]

            local row = EnsureRow(rowIndex)
            row.kind         = kind
            row.instanceName = instName
            row.isAllUnavailable = false

            row:SetSize(content:GetWidth(), rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)

            if not row.allCheck then
                local cbAll = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                cbAll:SetSize(18, 18)
                cbAll:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
                cbAll:SetScript("OnClick", LRLF_OnAllCheckboxClick)
                row.allCheck = cbAll
            else
                row.allCheck:Show()
                row.allCheck:ClearAllPoints()
                row.allCheck:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            end

            if not row.nameText then
                local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameFS:SetJustifyH("LEFT")
                row.nameText = nameFS
            end
            row.nameText:ClearAllPoints()
            row.nameText:SetPoint("TOPLEFT", row.allCheck, "TOPRIGHT", 4, 0)
            row.nameText:SetText(instName)
            row.nameText:SetFontObject("GameFontNormal")
            row.nameText:SetTextColor(1, 0.82, 0)

            -- Clear per-row state
            for k in pairs(row.activeDiffs) do
                row.activeDiffs[k] = nil
            end
            if row.diffStatus then
                for k in pairs(row.diffStatus) do
                    row.diffStatus[k] = nil
                end
            end

            -- Spread Normal / Heroic / Mythic more evenly across the row
            local diffXBase   = 10   -- starting X offset
            local diffSpacing = 73   -- horizontal distance between each difficulty
            local diffY       = -18

            local slotIndex = 0

            for _, diffName in ipairs(DIFF_ORDER) do
                local d     = diffs[diffName]
                local cb    = row.diffChecks[diffName]
                local label = row.diffLabels[diffName]

                if d then
                    slotIndex = slotIndex + 1

                    if not cb then
                        cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                        cb:SetSize(16, 16)
                        cb.row      = row
                        cb.diffName = diffName
                        cb:SetScript("OnClick", LRLF_OnDifficultyCheckboxClick)
                        cb:SetScript("OnEnter", LRLF_Diff_OnEnter)
                        cb:SetScript("OnLeave", LRLF_Diff_OnLeave)
                        row.diffChecks[diffName] = cb
                    end
                    if not label then
                        label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        row.diffLabels[diffName] = label
                        label.row      = row
                        label.diffName = diffName
                        label:SetScript("OnEnter", LRLF_Diff_OnEnter)
                        label:SetScript("OnLeave", LRLF_Diff_OnLeave)
                        label:SetScript("OnMouseDown", function()
                            if cb:IsEnabled() then
                                cb:Click()
                            end
                        end)
                    end

                    cb:Show()
                    label:Show()

                    local x = diffXBase + (slotIndex - 1) * diffSpacing
                    cb:ClearAllPoints()
                    cb:SetPoint("TOPLEFT", row, "TOPLEFT", x, diffY)
                    label:ClearAllPoints()
                    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)

                    label:SetText(DIFF_SHORTTEXT[diffName] or diffName)

                    local isReady       = (d.available and not d.hasLockout)
                    local isLocked      = d.hasLockout
                    local isUnavailable = (not d.available and not d.hasLockout)

                    LRLF_SetDiffStatus(row, diffName, isReady, isLocked, isUnavailable, d.lockoutReset)

                    local selected = instState and instState[diffName]

                    if isUnavailable then
                        cb:SetChecked(false)
                        cb:Disable()
                        cb:SetAlpha(0.4)
                        label:SetFontObject("GameFontDisable")
                        label:SetTextColor(0.5, 0.5, 0.5)
                        row.activeDiffs[diffName] = { enabled = false }
                    else
                        cb:Enable()
                        cb:SetAlpha(1.0)
                        cb:SetChecked(selected and true or false)

                        label:SetFontObject("GameFontHighlightSmall")
                        if isLocked then
                            label:SetTextColor(1.0, 0.2, 0.2)
                        elseif isReady then
                            label:SetTextColor(0.0, 1.0, 0.0)
                        else
                            label:SetTextColor(0.7, 0.7, 0.7)
                        end

                        row.activeDiffs[diffName] = { enabled = true }
                    end
                else
                    if cb then cb:Hide() end
                    if label then label:Hide() end
                    if row.diffStatus then
                        row.diffStatus[diffName] = nil
                    end
                    row.activeDiffs[diffName] = nil
                end
            end

            row.allCheck:Enable()
            row.allCheck:SetAlpha(1.0)
            row.nameText:SetFontObject("GameFontNormal")
            row.nameText:SetTextColor(1, 0.82, 0)

            LRLF_UpdateRowAllCheckbox(row, instState)
            LRLF_SetRowInteractive(row, LRLF_FilterEnabled)

            y = y - (rowHeight + spacing)
            rowIndex = rowIndex + 1
        end
    end

    -- Unavailable header + rows
    local hasUnavailable = #unavailableEntries > 0
    if LRLFFrame.unavailableHeader then
        if hasUnavailable then
            local headerFS = LRLFFrame.unavailableHeader
            headerFS:Show()
            headerFS:SetText("|cffb0b0b0|cffffffff|r") -- reset before formatting
            headerFS:SetText("|cffb0b0b0|cffffffff|r") -- dummy to force height
            headerFS:SetText("Currently unavailable")
            headerFS:SetFontObject("GameFontHighlightSmall")
            headerFS:SetTextColor(0.7, 0.7, 0.7)
            headerFS:SetJustifyH("CENTER")

            -- Extra space before header
            y = y - 12

            headerFS:ClearAllPoints()
            headerFS:SetPoint("TOP", content, "TOP", 0, y)

            local headerHeight = headerFS:GetStringHeight() or 0
            y = y - headerHeight - 8
        else
            LRLFFrame.unavailableHeader:Hide()
        end
    end

    if hasUnavailable then
        for _, entry in ipairs(unavailableEntries) do
            local info = infoMap[entry.name]
            if info then
                local instName  = info.name or entry.name
                local instState = filterKind[instName]

                local row = EnsureRow(rowIndex)
                row.kind             = kind
                row.instanceName     = instName
                row.isAllUnavailable = true

                row:SetSize(content:GetWidth(), rowHeight)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, y)

                if not row.allCheck then
                    local cbAll = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    cbAll:SetSize(18, 18)
                    cbAll:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
                    cbAll:SetScript("OnClick", LRLF_OnAllCheckboxClick)
                    row.allCheck = cbAll
                end

                -- For completely unavailable instances, All checkbox is disabled
                row.allCheck:SetChecked(false)
                row.allCheck:Disable()
                row.allCheck:SetAlpha(0.4)

                if not row.nameText then
                    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    nameFS:SetJustifyH("LEFT")
                    row.nameText = nameFS
                end
                row.nameText:ClearAllPoints()
                row.nameText:SetPoint("TOPLEFT", row.allCheck, "TOPRIGHT", 4, 0)
                row.nameText:SetText(instName)
                row.nameText:SetFontObject("GameFontDisable")
                row.nameText:SetTextColor(0.5, 0.5, 0.5)

                -- Hide any difficulty controls for this row
                for _, diffName in ipairs(DIFF_ORDER) do
                    local cb    = row.diffChecks[diffName]
                    local label = row.diffLabels[diffName]
                    if cb then cb:Hide() end
                    if label then label:Hide() end
                    if row.diffStatus then
                        row.diffStatus[diffName] = nil
                    end
                    row.activeDiffs[diffName] = nil
                end

                LRLF_SetRowInteractive(row, LRLF_FilterEnabled)

                y = y - (rowHeight + spacing)
                rowIndex = rowIndex + 1
            end
        end
    end

    -- Hide any leftover rows
    for idx = rowIndex, #rowsByKind do
        if rowsByKind[idx] then
            rowsByKind[idx]:Hide()
        end
    end

    local totalHeight = (textHeight + 8) + ((rowIndex - 1) * (rowHeight + spacing)) + 20
    if totalHeight < 1 then totalHeight = 1 end
    content:SetHeight(totalHeight)
    content:SetWidth(LRLFFrame.scrollFrame:GetWidth())
    LRLFFrame.scrollFrame:UpdateScrollChildRect()

    -- Apply enabled/disabled look after rebuild
    LRLF_UpdateFilterEnabledVisualState()
end
