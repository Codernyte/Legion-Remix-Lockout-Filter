--######################################################################
-- LegionRemixLockoutFilter_UI.lua
-- Core UI frame, shared helpers, dispatch to raid/dungeon UIs
--######################################################################

local ADDON_NAME, ADDON_TABLE = ...

local LRLF_LFG = ADDON_TABLE.LFG or {}

--------------------------------------------------
-- Shared difficulty constants
--------------------------------------------------

DIFF_ORDER     = DIFF_ORDER     or { "Normal", "Heroic", "Mythic" }
DIFF_SHORTTEXT = DIFF_SHORTTEXT or { Normal = "Normal", Heroic = "Heroic", Mythic = "Mythic" }

--------------------------------------------------
-- Shared row helpers / tooltips
--------------------------------------------------

function LRLF_ClearRowsForKind(kind)
    LRLF_Rows = LRLF_Rows or { raid = {}, dungeon = {} }
    local rows = LRLF_Rows[kind]
    if not rows then return end
    for _, row in ipairs(rows) do
        row:Hide()
    end
end

function LRLF_SetDiffStatus(row, diffName, isReady, isLocked, isUnavailable, lockoutReset)
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

function LRLF_Diff_OnEnter(self)
    if not self.row or not self.diffName then return end
    LRLF_SetDifficultyTooltip(self, self.row, self.diffName)
end

function LRLF_Diff_OnLeave(self)
    GameTooltip:Hide()
end

function LRLF_SetRowInteractive(row, enabled)
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

    -- Per-difficulty checkboxes + labels
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
                -- Keep font size consistent; only change color / disabled state
                label:SetFontObject("GameFontHighlightSmall")

                if not status then
                    if enabled then
                        label:SetTextColor(0.7, 0.7, 0.7)
                    else
                        label:SetTextColor(0.6, 0.6, 0.6)
                    end
                else
                    if not enabled then
                        label:SetTextColor(0.6, 0.6, 0.6)
                    else
                        if status.isUnavailable then
                            label:SetTextColor(0.5, 0.5, 0.5)
                        elseif status.isLocked then
                            label:SetTextColor(1.0, 0.2, 0.2)
                        elseif status.isReady then
                            label:SetTextColor(0.0, 1.0, 0.0)
                        else
                            label:SetTextColor(0.7, 0.7, 0.7)
                        end
                    end
                end
            end
        end
    end
end

function LRLF_ShowTopButtonsForKind(kind)
    if not LRLFFrame then return end

    if LRLFFrame.raidTopButtons then
        for _, btn in pairs(LRLFFrame.raidTopButtons) do
            if kind == "raid" then
                btn:Show()
            else
                btn:Hide()
            end
        end
    end

    if LRLFFrame.dungeonTopButtons then
        for _, btn in pairs(LRLFFrame.dungeonTopButtons) do
            if kind == "dungeon" then
                btn:Show()
            else
                btn:Hide()
            end
        end
    end
end

--------------------------------------------------
-- Filter enabled/disabled visual
--------------------------------------------------

function LRLF_UpdateFilterEnabledVisualState()
    local enabled = (LRLF_FilterEnabled ~= false)
    LRLF_FilterEnabled = enabled

    if LRLF_FilterButtons and LRLF_FilterButtons.apply then
        LRLF_FilterButtons.apply:SetAlpha(enabled and 1.0 or 0.4)
    end

    if LRLFFrame then
        if LRLFFrame.raidTopButtons then
            for _, btn in pairs(LRLFFrame.raidTopButtons) do
                if enabled then
                    btn:Enable()
                    btn:SetAlpha(1.0)
                else
                    btn:Disable()
                    btn:SetAlpha(0.4)
                end
            end
        end

        if LRLFFrame.dungeonTopButtons then
            for _, btn in pairs(LRLFFrame.dungeonTopButtons) do
                if enabled then
                    btn:Enable()
                    btn:SetAlpha(1.0)
                else
                    btn:Disable()
                    btn:SetAlpha(0.4)
                end
            end
        end

        if LRLF_SearchButton then
            if enabled then
                LRLF_SearchButton:Enable()
                LRLF_SearchButton:SetAlpha(1.0)
            else
                LRLF_SearchButton:Disable()
                LRLF_SearchButton:SetAlpha(0.4)
            end
        end

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
        LRLF_UpdateFilterEnabledVisualState()
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
-- Side panel window creation helpers
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
    if kind ~= "raid" then return end

    local infoMap, list = LRLF_LFG.BuildRaidDifficultyInfo()
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
                    sysInst[diffName]   = false
                end
            end
        end
    end

    LRLF_RefreshSidePanelText(kind)
end

--------------------------------------------------
-- Helper text for left/right click
--------------------------------------------------

function LRLF_GetInstructionText(kind)
    -- Keep this short so it fits in ~2 lines
    if kind == "dungeon" then
        return "Left-click: toggle this dungeon.\nRight-click: select only this dungeon."
    else
        return "Left-click: toggle ready difficulties.\nRight-click: select only this raid or difficulty."
    end
end

--------------------------------------------------
-- Side panel window creation
--------------------------------------------------

function LRLF_CreateSideWindow()
    if LRLFFrame then return end

    LRLF_Rows = LRLF_Rows or { raid = {}, dungeon = {} }

    local f = CreateFrame("Frame", "LRLFFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetWidth(280)
    f:EnableMouse(true)
    f:SetFrameStrata("HIGH")
    f:SetPoint("CENTER")

    -- Window title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
    f.title:SetText("Legion Remix Lockout Filter")

    --------------------------------------------------
    -- RAID top buttons (left-aligned row)
    --------------------------------------------------
    f.raidTopButtons = {}

    local function CreateRaidTopButton(key, label, xOffset)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(60, 24)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", xOffset, -28)
        btn:SetText(label)
        f.raidTopButtons[key] = btn
        return btn
    end

    local raidBtnAll    = CreateRaidTopButton("All",    "All",    10)
    local raidBtnNormal = CreateRaidTopButton("Normal", "Normal", 10 + 60 + 2)
    local raidBtnHeroic = CreateRaidTopButton("Heroic", "Heroic", 10 + (60 + 2) * 2)
    local raidBtnMythic = CreateRaidTopButton("Mythic", "Mythic", 10 + (60 + 2) * 3)

    raidBtnAll:SetScript("OnClick", function()
        LRLF_BatchSelectDifficulty("raid", "All")
    end)
    raidBtnNormal:SetScript("OnClick", function()
        LRLF_BatchSelectDifficulty("raid", "Normal")
    end)
    raidBtnHeroic:SetScript("OnClick", function()
        LRLF_BatchSelectDifficulty("raid", "Heroic")
    end)
    raidBtnMythic:SetScript("OnClick", function()
        LRLF_BatchSelectDifficulty("raid", "Mythic")
    end)

    --------------------------------------------------
    -- DUNGEON top buttons
    --  All = top-left
    --  Mythic / Mythic+ = right-aligned as a pair
    --------------------------------------------------
    f.dungeonTopButtons = {}

    -- "All" on the far left
    local dAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dAll:SetSize(60, 24)
    dAll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
    dAll:SetText("All")
    f.dungeonTopButtons.All = dAll

    -- Mythic+ on far right
    local dKeystone = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dKeystone:SetSize(70, 24)
    dKeystone:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -28)
    dKeystone:SetText("Mythic+")
    f.dungeonTopButtons.KEYSTONE = dKeystone

    -- Mythic just to the left of Mythic+
    local dMythic = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dMythic:SetSize(70, 24)
    dMythic:SetPoint("RIGHT", dKeystone, "LEFT", -4, 0)
    dMythic:SetText("Mythic")
    f.dungeonTopButtons.MYTHIC = dMythic

    dAll:SetScript("OnClick", function()
        if type(LRLF_DungeonSelectAllReady) == "function" then
            LRLF_DungeonSelectAllReady()
        end
    end)

    dMythic:SetScript("OnClick", function()
        LRLF_DungeonMode = "MYTHIC"
        if type(LRLF_UpdateDungeonModeButtons) == "function" then
            LRLF_UpdateDungeonModeButtons()
        end
        LRLF_RefreshSidePanelText("dungeon")

        if LRLF_IsTimerunner and LRLF_IsTimerunner()
            and LFGListFrame and LFGListFrame.SearchPanel
            and LFGListSearchPanel_DoSearch
        then
            local searchPanel = LFGListFrame.SearchPanel
            if searchPanel:IsShown() and searchPanel.categoryID == 2 then
                LRLF_LastSearchWasFiltered = true
                LFGListSearchPanel_DoSearch(searchPanel)
            end
        end
    end)

    dKeystone:SetScript("OnClick", function()
        LRLF_DungeonMode = "KEYSTONE"
        if type(LRLF_UpdateDungeonModeButtons) == "function" then
            LRLF_UpdateDungeonModeButtons()
        end
        LRLF_RefreshSidePanelText("dungeon")

        if LRLF_IsTimerunner and LRLF_IsTimerunner()
            and LFGListFrame and LFGListFrame.SearchPanel
            and LFGListSearchPanel_DoSearch
        then
            local searchPanel = LFGListFrame.SearchPanel
            if searchPanel:IsShown() and searchPanel.categoryID == 2 then
                LRLF_LastSearchWasFiltered = true
                LFGListSearchPanel_DoSearch(searchPanel)
            end
        end
    end)

    if type(LRLF_UpdateDungeonModeButtons) == "function" then
        LRLF_UpdateDungeonModeButtons()
    end

    --------------------------------------------------
    -- Scroll area + header text + helper text
    --------------------------------------------------
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

    -- Top status / error text (usually empty or very short)
    local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetText("")

    -- Short instructions between top buttons and instance list (small, centered)
    local instructionText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    instructionText:SetPoint("TOPLEFT",  text, "BOTTOMLEFT", 0, -2)
    instructionText:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 0, -2)
    instructionText:SetJustifyH("CENTER")
    instructionText:SetJustifyV("TOP")
    instructionText:SetText("")
    f.instructionText = instructionText

    local unavailableHeader = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    unavailableHeader:SetJustifyH("CENTER")
    unavailableHeader:SetText("")
    unavailableHeader:Hide()

    f.text              = text
    f.scrollFrame       = scrollFrame
    f.unavailableHeader = unavailableHeader
    f.content           = content

    --------------------------------------------------
    -- Bottom "Search" button (uses current filters)
    --------------------------------------------------
    local searchButton = CreateFrame("Button", "LRLF_SearchButton", f, "UIPanelButtonTemplate")
    searchButton:SetHeight(32)
    searchButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    searchButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    searchButton:SetText("Search")

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
            UIErrorsFrame:AddMessage("Filter: Open Legion Dungeons or Raids search first.", 1.0, 0.1, 0.1)
            return
        end

        LRLF_LastSearchWasFiltered = true

        if type(LFGListSearchPanel_DoSearch) == "function" then
            LFGListSearchPanel_DoSearch(searchPanel)
        end
    end)

    LRLF_SearchButton = searchButton

    --------------------------------------------------
    -- Close button behavior (collapse to eyeball)
    --------------------------------------------------
    local close = f.CloseButton or _G[f:GetName() .. "CloseButton"]
    if close then
        close:HookScript("OnClick", function()
            LRLF_UserCollapsed = true
            LRLF_UpdateVisibility()
        end)
    end

    -- When shown, always refresh for the current kind and update helper text
    f:SetScript("OnShow", function()
        local kind = LRLF_GetCurrentKind and LRLF_GetCurrentKind() or "raid"
        if f.instructionText and type(LRLF_GetInstructionText) == "function" then
            f.instructionText:SetText(LRLF_GetInstructionText(kind))
        end
        LRLF_RefreshSidePanelText(kind)
    end)

    f:Hide()
    LRLFFrame = f

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

    -- Main filter enable/disable eye icon
    local apply = CreateFrame("Button", "LRLF_FilterApplyIcon", bg)
    apply:SetSize(ICON_SIZE, ICON_SIZE)
    apply:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)

    local applyTex = apply:CreateTexture(nil, "ARTWORK")
    applyTex:SetAllPoints()
    applyTex:SetTexture("Interface\\Icons\\INV_Misc_Eye_01")
    apply.icon = applyTex

    apply:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local title = LRLF_FilterEnabled and "Filter Enabled" or "Filter Disabled"
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine("Click to toggle whether the filter affects the search results.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    apply:SetScript("OnLeave", function() GameTooltip:Hide() end)

    apply:SetScript("OnClick", function(self)
        LRLF_FilterEnabled = not LRLF_FilterEnabled
        LRLF_UpdateFilterEnabledVisualState()

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

    -- One-click signup settings icon
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
        GameTooltip:AddLine("• Left-click a group: open the normal role selection dialog (no auto-confirm).", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("• Shift+Left-click: auto-confirm using your current specialization's role.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("• Ctrl+Shift+Left-click: auto-confirm using all roles your class can perform.", 0.9, 0.9, 0.9, true)
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
        GameTooltip:AddLine("Show the filter panel.", nil, nil, nil, true)
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
-- Dispatch: build header + call raid/dungeon row builders
--------------------------------------------------

function LRLF_RefreshSidePanelText(kind)
    if not LRLFFrame or not LRLFFrame.text then
        return
    end

    kind = kind or "raid"

    LRLF_ShowTopButtonsForKind(kind)
    if kind == "dungeon" and type(LRLF_UpdateDungeonModeButtons) == "function" then
        LRLF_UpdateDungeonModeButtons()
    end

    if LRLFFrame.instructionText and type(LRLF_GetInstructionText) == "function" then
        LRLFFrame.instructionText:SetText(LRLF_GetInstructionText(kind))
    end

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
        LRLF_UpdateFilterEnabledVisualState()
        return
    end

    LRLFFrame.text:SetText(table.concat(lines, "\n") or "")

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local textFS     = LRLFFrame.text
    local textHeight = textFS:GetStringHeight() or 0

    LRLF_ClearRowsForKind("raid")
    LRLF_ClearRowsForKind("dungeon")

    LRLF_Rows[kind] = LRLF_Rows[kind] or {}

    if kind == "dungeon" then
        -- Dungeon rows use a more detailed signature; pass the basics and let
        -- the dungeon UI recompute layout.
        LRLF_RefreshDungeonRows(kind, infoMap, list, nil, nil, nil, nil, textHeight)
    else
        LRLF_RefreshRaidRows(kind, infoMap, list, textHeight)
    end

    LRLF_UpdateFilterEnabledVisualState()
end
