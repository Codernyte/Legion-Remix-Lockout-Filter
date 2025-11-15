-- LegionRemixLockoutFilter_UI.lua
-- UI: side panel, rows, filter controls, toggle tab

local ADDON_NAME, ADDON_TABLE = ...

-- Uses global state defined in main:
--   LRLFFrame, LRLF_FilterState, LRLF_SystemSelection, LRLF_Rows,
--   LRLF_FilterButtons, LRLF_FilterEnabled, LRLF_SearchButton,
--   LRLF_ToggleButton, LRLF_UserCollapsed, LRLF_WTSFilterEnabled

--------------------------------------------------
-- Internal helpers for rows
--------------------------------------------------

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
        for _, diffName in ipairs({ "Normal", "Heroic", "Mythic" }) do
            if instState[diffName] then
                anyTrue = true
                break
            end
        end
    end

    row.allCheck:SetChecked(anyTrue)
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

    for _, diffName in ipairs({ "Normal", "Heroic", "Mythic" }) do
        local cb = row.diffChecks[diffName]
        if cb and cb:IsShown() then
            local isLocked      = (cb.diffStatus == "locked")
            local isUnavailable = (cb.diffStatus == "unavailable")

            local shouldCheck
            if checked then
                -- Batch operations should not select locked or unavailable entries
                shouldCheck = (not isLocked and not isUnavailable and cb:IsEnabled())
            else
                -- When unchecking "All", clear everything including locked ones
                shouldCheck = false
            end

            cb:SetChecked(shouldCheck)
            instState[diffName] = shouldCheck
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
-- Difficulty checkbox tooltips
--------------------------------------------------

local function LRLF_DifficultyCheckbox_OnEnter(self)
    if not GameTooltip then return end

    -- Allow label frames to proxy to the actual checkbox
    local src = self.tooltipSource or self

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

    local status = src.diffStatus
    if status == "ready" then
        GameTooltip:SetText("Ready to join", 1, 1, 1)
    elseif status == "locked" then
        local line = "Locked"
        if src.lockoutReset and src.lockoutReset > 0 and type(LRLF_FormatTimeRemaining) == "function" then
            line = line .. ": " .. LRLF_FormatTimeRemaining(src.lockoutReset)
        end
        GameTooltip:SetText(line, 1, 1, 1)
    elseif status == "unavailable" then
        GameTooltip:SetText("Currently unavailable", 1, 1, 1)
    else
        GameTooltip:SetText("Status unknown", 1, 1, 1)
    end

    GameTooltip:Show()
end

local function LRLF_DifficultyCheckbox_OnLeave(self)
    if GameTooltip then
        GameTooltip:Hide()
    end
end

--------------------------------------------------
-- Batch preset: "just Normal/Heroic/Mythic available"
--------------------------------------------------

local function LRLF_ApplyDifficultyPreset(diffName)
    if not LFGListFrame or not LFGListFrame.SearchPanel then
        return
    end

    local searchPanel = LFGListFrame.SearchPanel
    local categoryID  = searchPanel.categoryID
    local kind = (categoryID == 2 and "dungeon")
              or (categoryID == 3 and "raid")
              or nil
    if not kind then
        return
    end

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]
    local rows       = LRLF_Rows and LRLF_Rows[kind]

    if not rows then return end

    for _, row in ipairs(rows) do
        if row:IsShown() and row.instanceName and row.kind == kind and row.diffChecks then
            local instName = row.instanceName
            filterKind[instName] = filterKind[instName] or {}
            sysKind[instName]    = sysKind[instName]    or {}

            local instState = filterKind[instName]
            local sysInst   = sysKind[instName]

            for _, dn in ipairs({ "Normal", "Heroic", "Mythic" }) do
                local cb = row.diffChecks[dn]
                if cb then
                    local isTarget      = (dn == diffName)
                    local isLocked      = (cb.diffStatus == "locked")
                    local isUnavailable = (cb.diffStatus == "unavailable")

                    -- Only select ready entries for the target difficulty
                    local shouldSelect = false
                    if isTarget and not isLocked and not isUnavailable and cb:IsEnabled() then
                        shouldSelect = true
                    end

                    cb:SetChecked(shouldSelect)
                    instState[dn] = shouldSelect
                    sysInst[dn]   = false -- user-managed via batch
                end
            end

            LRLF_UpdateRowAllCheckbox(row, instState)
        end
    end
end

--------------------------------------------------
-- Panel interactivity when filter is enabled/disabled
--------------------------------------------------

local function LRLF_SetPanelInteractive(enabled)
    if not LRLFFrame then return end

    local alpha = enabled and 1.0 or 0.4

    -- Top buttons (All / Normal / Heroic / Mythic)
    if LRLFFrame.topButtons then
        for _, btn in pairs(LRLFFrame.topButtons) do
            if btn then
                if not enabled then
                    btn._wasEnabled = btn:IsEnabled()
                    btn:Disable()
                else
                    if btn._wasEnabled ~= nil then
                        if btn._wasEnabled then
                            btn:Enable()
                        else
                            btn:Disable()
                        end
                        btn._wasEnabled = nil
                    else
                        btn:Enable()
                    end
                end
                btn:SetAlpha(alpha)
            end
        end
    end

    -- Search button
    if LRLF_SearchButton then
        if not enabled then
            LRLF_SearchButton._wasEnabled = LRLF_SearchButton:IsEnabled()
            LRLF_SearchButton:Disable()
        else
            if LRLF_SearchButton._wasEnabled ~= nil then
                if LRLF_SearchButton._wasEnabled then
                    LRLF_SearchButton:Enable()
                else
                    LRLF_SearchButton:Disable()
                end
                LRLF_SearchButton._wasEnabled = nil
            else
                LRLF_SearchButton:Enable()
            end
        end
        LRLF_SearchButton:SetAlpha(alpha)
    end

    -- Rows and their controls
    if LRLF_Rows then
        for _, kind in ipairs({ "raid", "dungeon" }) do
            local rows = LRLF_Rows[kind]
            if rows then
                for _, row in ipairs(rows) do
                    if row:IsShown() then
                        -- "All" checkbox
                        if row.allCheck then
                            if not enabled then
                                row.allCheck._wasEnabled = row.allCheck:IsEnabled()
                                row.allCheck:Disable()
                            else
                                if row.allCheck._wasEnabled ~= nil then
                                    if row.allCheck._wasEnabled then
                                        row.allCheck:Enable()
                                    else
                                        row.allCheck:Disable()
                                    end
                                    row.allCheck._wasEnabled = nil
                                end
                            end
                            row.allCheck:SetAlpha(alpha)
                        end

                        -- Difficulty checkboxes
                        if row.diffChecks then
                            for _, cb in pairs(row.diffChecks) do
                                if cb then
                                    if not enabled then
                                        cb._wasEnabled = cb:IsEnabled()
                                        cb:Disable()
                                    else
                                        if cb._wasEnabled ~= nil then
                                            if cb._wasEnabled then
                                                cb:Enable()
                                            else
                                                cb:Disable()
                                            end
                                            cb._wasEnabled = nil
                                        end
                                    end
                                    cb:SetAlpha(alpha)
                                end
                            end
                        end

                        -- Label hover frames (click + tooltip area)
                        if row.diffLabelFrames then
                            for _, lf in pairs(row.diffLabelFrames) do
                                if lf then
                                    if not enabled then
                                        lf._wasMouseEnabled = lf:IsMouseEnabled()
                                        lf:EnableMouse(false)
                                    else
                                        if lf._wasMouseEnabled ~= nil then
                                            lf:EnableMouse(lf._wasMouseEnabled)
                                            lf._wasMouseEnabled = nil
                                        end
                                    end
                                    lf:SetAlpha(alpha)
                                end
                            end
                        end

                        -- Difficulty text labels (Normal / Heroic / Mythic)
                        if row.diffLabels then
                            for _, label in pairs(row.diffLabels) do
                                if label then
                                    label:SetAlpha(alpha)
                                end
                            end
                        end

                        if row.nameText then
                            row.nameText:SetAlpha(enabled and 1.0 or 0.7)
                        end

                        -- Divider text for "Currently unavailable"
                        if row.dividerText then
                            row.dividerText:SetAlpha(alpha)
                        end
                    end
                end
            end
        end
    end

    -- Optional: dim the header text at the very top slightly
    if LRLFFrame.text then
        LRLFFrame.text:SetAlpha(enabled and 1.0 or 0.7)
    end
end

--------------------------------------------------
-- Filter enabled/disabled visual + auto-search
--------------------------------------------------

local function LRLF_UpdateFilterEnabledVisualState(suppressSearch)
    local enabled = (LRLF_FilterEnabled ~= false)
    LRLF_FilterEnabled = enabled

    if LRLF_FilterButtons and LRLF_FilterButtons.apply then
        LRLF_FilterButtons.apply:SetAlpha(enabled and 1.0 or 0.4)
    end

    -- WTS coin button should be inactive when the whole filter is disabled
    if LRLF_FilterButtons and LRLF_FilterButtons.wts then
        if enabled then
            LRLF_FilterButtons.wts:Enable()
            LRLF_FilterButtons.wts:SetAlpha(1.0)
        else
            LRLF_FilterButtons.wts:Disable()
            LRLF_FilterButtons.wts:SetAlpha(0.4)
        end
    end

    -- Grey out / disable panel controls instead of making the whole frame transparent
    LRLF_SetPanelInteractive(enabled)

    -- Auto-run a search when toggling, unless suppressed
    if not suppressSearch then
        if LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel:IsShown()
            and type(LFGListSearchPanel_DoSearch) == "function"
        then
            local searchPanel = LFGListFrame.SearchPanel
            local categoryID  = searchPanel.categoryID
            if categoryID == 2 or categoryID == 3 then
                if enabled then
                    -- Treat this context as filtered
                    LRLF_LastSearchWasFiltered = true
                end
                LFGListSearchPanel_DoSearch(searchPanel)
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

function LRLF_CreateSideWindow()
    if LRLFFrame then return end

    local f = CreateFrame("Frame", "LRLFFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetWidth(300) -- slightly wider to accommodate full difficulty labels and top buttons
    f:EnableMouse(true)
    f:SetFrameStrata("HIGH")
    f:SetPoint("CENTER")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
    f.title:SetText("Lockout Filter")

    -- Top preset buttons: All / Normal / Heroic / Mythic
    f.topButtons = f.topButtons or {}

    -- Slightly larger + wider, and a bit less spacing
    local btnWidth, btnHeight = 65, 24
    local spacingX = 3
    local startX   = 10

    local allBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    allBtn:SetSize(btnWidth, btnHeight)
    allBtn:SetPoint("TOPLEFT", f, "TOPLEFT", startX, -30)
    allBtn:SetText("All")
    allBtn:SetScript("OnClick", function()
        -- "All" behaves like reset-to-ready-only defaults across current kind
        LRLF_ResetAllFilters()
    end)
    f.topButtons.all = allBtn

    local normalBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    normalBtn:SetSize(btnWidth, btnHeight)
    normalBtn:SetPoint("LEFT", allBtn, "RIGHT", spacingX, 0)
    normalBtn:SetText("Normal")
    normalBtn:SetScript("OnClick", function()
        LRLF_ApplyDifficultyPreset("Normal")
    end)
    f.topButtons.normal = normalBtn

    local heroicBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    heroicBtn:SetSize(btnWidth, btnHeight)
    heroicBtn:SetPoint("LEFT", normalBtn, "RIGHT", spacingX, 0)
    heroicBtn:SetText("Heroic")
    heroicBtn:SetScript("OnClick", function()
        LRLF_ApplyDifficultyPreset("Heroic")
    end)
    f.topButtons.heroic = heroicBtn

    local mythicBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    mythicBtn:SetSize(btnWidth, btnHeight)
    mythicBtn:SetPoint("LEFT", heroicBtn, "RIGHT", spacingX, 0)
    mythicBtn:SetText("Mythic")
    mythicBtn:SetScript("OnClick", function()
        LRLF_ApplyDifficultyPreset("Mythic")
    end)
    f.topButtons.mythic = mythicBtn

    local scrollFrame = CreateFrame("ScrollFrame", "LRLF_ScrollFrame", f, "UIPanelScrollFrameTemplate")
    -- Move down a bit to make room for buttons
    scrollFrame:SetPoint("TOPLEFT", 10, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    scrollFrame:EnableMouse(true)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local step = 20
        local maxScroll = self:GetVerticalScrollRange() or 0
        local new = current - (delta * step)
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
    text:SetText("LegionRemixLockoutFilter\n\nText will appear here…")

    f.text        = text
    f.scrollFrame = scrollFrame

    local searchButton = CreateFrame("Button", "LRLF_SearchButton", f, "UIPanelButtonTemplate")
    searchButton:SetHeight(32)
    searchButton:ClearAllPoints()
    searchButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    searchButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    searchButton:SetText("Search with Lockout Filters")

    searchButton:SetScript("OnClick", function(self)
        if not LRLF_IsTimerunner() then
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
end

--------------------------------------------------
-- Filter control icons to the right of the panel
--------------------------------------------------

function LRLF_CreateFilterButtons()
    if LRLF_FilterButtons and LRLF_FilterButtons.apply or not LRLFFrame then
        return
    end

    LRLF_FilterButtons = LRLF_FilterButtons or {}

    local ICON_SIZE = 24

    local bg = CreateFrame("Frame", "LRLF_FilterIconBackground", LRLFFrame, "BackdropTemplate")
    bg:SetFrameStrata("HIGH")
    bg:SetSize(32, 64)
    bg:ClearAllPoints()
    -- Align more with the top of the scrollable body, still outside the window
    bg:SetPoint("TOPLEFT", LRLFFrame, "TOPRIGHT", 0, -60)

    bg:SetBackdrop({
        bgFile   = "Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16,
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bg:SetBackdropColor(0, 0, 0, 0.85)
    bg:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)

    -- Master apply/enable icon
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
    end)

    -- WTS filter (gold coin with a strike)
    local wts = CreateFrame("Button", "LRLF_WTSFilterIcon", bg)
    wts:SetSize(ICON_SIZE, ICON_SIZE)
    wts:SetPoint("TOPLEFT", apply, "BOTTOMLEFT", 0, -4)

    local wtsCoin = wts:CreateTexture(nil, "ARTWORK")
    wtsCoin:SetAllPoints()
    wtsCoin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    wts.coin = wtsCoin

    -- Simple strike-through: a red line across the coin
    local strike = wts:CreateTexture(nil, "OVERLAY")
    strike:SetColorTexture(1, 0, 0, 0.9)
    strike:SetSize(ICON_SIZE + 4, 3)
    strike:SetPoint("CENTER", wts, "CENTER", 0, 0)
    wts.strike = strike

    local function UpdateWTSVisual()
        local active = (LRLF_WTSFilterEnabled ~= false)
        if active then
            wts:SetAlpha(1.0)
            wtsCoin:SetDesaturated(false)
            strike:Show()
        else
            wts:SetAlpha(0.6)
            wtsCoin:SetDesaturated(true)
            strike:Hide()
        end
    end

    wts:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if LRLF_WTSFilterEnabled ~= false then
            GameTooltip:SetText("WTS Filter Enabled", 1, 1, 1)
            GameTooltip:AddLine("Hiding listings whose title contains 'wts', 'buy', or 'sell'.", nil, nil, nil, true)
        else
            GameTooltip:SetText("WTS Filter Disabled", 1, 1, 1)
            GameTooltip:AddLine("Showing all listings, including potential WTS/boost groups.", nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    wts:SetScript("OnLeave", function() GameTooltip:Hide() end)

    wts:SetScript("OnClick", function(self)
        -- Only meaningful when the main filter is enabled; button is disabled otherwise
        LRLF_WTSFilterEnabled = not (LRLF_WTSFilterEnabled ~= false)
        UpdateWTSVisual()

        -- If the filter is active and we're in a valid search panel, re-run search
        if LRLF_FilterEnabled and LFGListFrame and LFGListFrame.SearchPanel
            and LFGListFrame.SearchPanel:IsShown()
            and type(LFGListSearchPanel_DoSearch) == "function"
        then
            local searchPanel = LFGListFrame.SearchPanel
            local categoryID  = searchPanel.categoryID
            if categoryID == 2 or categoryID == 3 then
                LRLF_LastSearchWasFiltered = true
                LFGListSearchPanel_DoSearch(searchPanel)
            end
        end
    end)

    LRLF_FilterButtons.apply = apply
    LRLF_FilterButtons.wts   = wts
    LRLF_FilterButtons.bg    = bg

    apply:Hide()
    wts:Hide()
    bg:Hide()

    -- Initialize visual state (including WTS) without triggering a search
    UpdateWTSVisual()
    LRLF_UpdateFilterEnabledVisualState(true)
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

    if not list or #list == 0 then
        table.insert(lines, "No Legion " .. labelPlural .. " found.")
        LRLFFrame.text:SetText(table.concat(lines, "\n"))

        LRLF_ClearRowsForKind("raid")
        LRLF_ClearRowsForKind("dungeon")

        local text = LRLFFrame.text
        local content = LRLFFrame.scrollFrame:GetScrollChild()
        local height = (text:GetStringHeight() or 0) + 20
        if height < 1 then height = 1 end
        content:SetHeight(height)
        content:SetWidth(LRLFFrame.scrollFrame:GetWidth())
        LRLFFrame.scrollFrame:UpdateScrollChildRect()
        return
    end

    LRLFFrame.text:SetText(table.concat(lines, "\n"))

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    -- Sync filter state with readiness/unavailable based on infoMap
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
            for _, diffName in ipairs({ "Normal", "Heroic", "Mythic" }) do
                local d = diffs[diffName]
                if d then
                    local isReady       = (d.available and not d.hasLockout)
                    local isUnavailable = (not d.available and not d.hasLockout)

                    if instState[diffName] == nil then
                        instState[diffName] = isReady
                        sysInst[diffName]   = true
                    else
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

    LRLF_ClearRowsForKind("raid")
    LRLF_ClearRowsForKind("dungeon")

    LRLF_Rows[kind] = LRLF_Rows[kind] or {}
    local rowsByKind = LRLF_Rows[kind]

    local textFS     = LRLFFrame.text
    local textHeight = textFS:GetStringHeight() or 0
    local content    = LRLFFrame.scrollFrame:GetScrollChild()

    -- Make sure the content width is set before we size/center rows,
    -- so the "Currently unavailable" divider centers correctly on first load.
    if content then
        content:SetWidth(LRLFFrame.scrollFrame:GetWidth())
    end

    local y          = -textHeight - 8

    local rowHeight  = 34
    local spacing    = 4

    -- Partition entries into available/locked vs fully-unavailable (all diffs unavailable)
    local availableEntries   = {}
    local unavailableEntries = {}

    for _, entry in ipairs(list) do
        local info = infoMap[entry.name]
        if info then
            local diffs = info.difficulties or {}
            local hasAnyDiff           = false
            local anyAvailableOrLocked = false

            for _, diffName in ipairs({ "Normal", "Heroic", "Mythic" }) do
                local d = diffs[diffName]
                if d then
                    hasAnyDiff = true
                    local isUnavailable = (not d.available and not d.hasLockout)
                    if not isUnavailable then
                        anyAvailableOrLocked = true
                        break
                    end
                end
            end

            if hasAnyDiff and not anyAvailableOrLocked then
                table.insert(unavailableEntries, entry) -- fully unavailable
            else
                table.insert(availableEntries, entry)
            end
        end
    end

    -- Helper to get or create a row frame
    local function AcquireRow(index)
        local row = rowsByKind[index]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row.diffChecks      = {}
            row.diffLabels      = {}
            row.diffLabelFrames = {}
            row.activeDiffs     = {}
            rowsByKind[index]   = row
        end
        row:Show()
        return row
    end

    local rowIndex = 0

    -- First: entries with at least one available/locked difficulty (normal section)
    for _, entry in ipairs(availableEntries) do
        local info = infoMap[entry.name]
        if info then
            local instName  = info.name or entry.name
            local diffs     = info.difficulties
            local instState = filterKind[instName]

            rowIndex = rowIndex + 1
            local row = AcquireRow(rowIndex)

            row.kind         = kind
            row.instanceName = instName
            row:SetSize(content:GetWidth(), rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)

            -- Hide divider text if this row was previously used as divider
            if row.dividerText then
                row.dividerText:Hide()
            end

            -- All-checkbox
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

            -- Instance name text
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

            -- Clear previous activeDiffs
            for k in pairs(row.activeDiffs) do
                row.activeDiffs[k] = nil
            end

            local diffXBase   = 22
            local diffSpacing = 80 -- more spacing to fit full difficulty names
            local diffY       = -18

            local order = { "Normal", "Heroic", "Mythic" }

            local slotIndex = 0
            local anyAvailableOrLocked = false

            for _, diffName in ipairs(order) do
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
                        cb:SetScript("OnEnter", LRLF_DifficultyCheckbox_OnEnter)
                        cb:SetScript("OnLeave", LRLF_DifficultyCheckbox_OnLeave)
                        row.diffChecks[diffName] = cb
                    else
                        cb.row      = row
                        cb.diffName = diffName
                        cb:SetScript("OnClick", LRLF_OnDifficultyCheckboxClick)
                        cb:SetScript("OnEnter", LRLF_DifficultyCheckbox_OnEnter)
                        cb:SetScript("OnLeave", LRLF_DifficultyCheckbox_OnLeave)
                    end

                    if not label then
                        label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        row.diffLabels[diffName] = label
                    end

                    cb:Show()
                    label:Show()

                    local x = diffXBase + (slotIndex - 1) * diffSpacing
                    cb:ClearAllPoints()
                    cb:SetPoint("TOPLEFT", row, "TOPLEFT", x, diffY)
                    label:ClearAllPoints()
                    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)

                    -- Full difficulty name on label
                    label:SetText(diffName)

                    -- Shared status calculations
                    local isReady       = (d.available and not d.hasLockout)
                    local isLocked      = d.hasLockout
                    local isUnavailable = (not d.available and not d.hasLockout)

                    if not isUnavailable then
                        anyAvailableOrLocked = true
                    end

                    local selected = instState and instState[diffName]

                    if isUnavailable then
                        cb:SetChecked(false)
                        cb:Disable()
                        cb:SetAlpha(0.4)
                        label:SetFontObject("GameFontDisable")
                        label:SetTextColor(0.5, 0.5, 0.5)
                        row.activeDiffs[diffName] = { enabled = false }

                        cb.diffStatus   = "unavailable"
                        cb.lockoutReset = nil
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

                        if isLocked then
                            cb.diffStatus   = "locked"
                            cb.lockoutReset = d.lockoutReset
                        elseif isReady then
                            cb.diffStatus   = "ready"
                            cb.lockoutReset = nil
                        else
                            cb.diffStatus   = "unknown"
                            cb.lockoutReset = nil
                        end
                    end

                    -- Create/position label hover frame that shares tooltip + click with checkbox
                    row.diffLabelFrames = row.diffLabelFrames or {}
                    local labelFrame = row.diffLabelFrames[diffName]
                    if not labelFrame then
                        labelFrame = CreateFrame("Button", nil, row)
                        labelFrame.checkbox      = cb
                        labelFrame.tooltipSource = cb
                        labelFrame:SetScript("OnEnter", LRLF_DifficultyCheckbox_OnEnter)
                        labelFrame:SetScript("OnLeave", LRLF_DifficultyCheckbox_OnLeave)
                        labelFrame:SetScript("OnClick", function(self)
                            if self.checkbox and self.checkbox:IsEnabled() then
                                self.checkbox:Click()
                            end
                        end)
                        row.diffLabelFrames[diffName] = labelFrame
                    else
                        labelFrame.checkbox      = cb
                        labelFrame.tooltipSource = cb
                        labelFrame:SetScript("OnEnter", LRLF_DifficultyCheckbox_OnEnter)
                        labelFrame:SetScript("OnLeave", LRLF_DifficultyCheckbox_OnLeave)
                    end

                    labelFrame:Show()
                    labelFrame:ClearAllPoints()
                    labelFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -2, 2)
                    labelFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 2, -2)
                else
                    if cb then cb:Hide() end
                    if label then label:Hide() end
                    if row.diffLabelFrames and row.diffLabelFrames[diffName] then
                        row.diffLabelFrames[diffName]:Hide()
                    end
                    row.activeDiffs[diffName] = nil
                end
            end

            -- Row enable/disable based on any available/locked difficulty
            if not anyAvailableOrLocked then
                row.allCheck:SetChecked(false)
                row.allCheck:Disable()
                row.allCheck:SetAlpha(0.4)
                row.nameText:SetFontObject("GameFontDisable")
                row.nameText:SetTextColor(0.5, 0.5, 0.5)
            else
                row.allCheck:Enable()
                row.allCheck:SetAlpha(1.0)
                row.nameText:SetFontObject("GameFontNormal")
                row.nameText:SetTextColor(1, 0.82, 0)
            end

            LRLF_UpdateRowAllCheckbox(row, instState)

            y = y - (rowHeight + spacing)
        end
    end

    -- Divider + entries that are fully unavailable
    if #unavailableEntries > 0 then
        -- Add a bit more space before the "Currently unavailable" section
        y = y - 10

        -- Divider row
        rowIndex = rowIndex + 1
        local dividerRow = AcquireRow(rowIndex)
        dividerRow.kind         = kind
        dividerRow.instanceName = nil
        dividerRow:SetSize(content:GetWidth(), rowHeight)
        dividerRow:ClearAllPoints()
        dividerRow:SetPoint("TOPLEFT", 0, y)

        -- Hide checkbox/diff stuff on divider row
        if dividerRow.allCheck then
            dividerRow.allCheck:Hide()
        end
        if dividerRow.nameText then
            dividerRow.nameText:Hide()
        end
        if dividerRow.diffChecks then
            for _, cb in pairs(dividerRow.diffChecks) do
                cb:Hide()
            end
        end
        if dividerRow.diffLabels then
            for _, label in pairs(dividerRow.diffLabels) do
                label:Hide()
            end
        end
        if dividerRow.diffLabelFrames then
            for _, lf in pairs(dividerRow.diffLabelFrames) do
                lf:Hide()
            end
        end

        if not dividerRow.dividerText then
            local dt = dividerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            dividerRow.dividerText = dt
        end

        dividerRow.dividerText:ClearAllPoints()
        dividerRow.dividerText:SetPoint("CENTER", dividerRow, "CENTER", 0, 0)
        dividerRow.dividerText:SetJustifyH("CENTER")
        dividerRow.dividerText:SetText("Currently unavailable")
        dividerRow.dividerText:SetFontObject("GameFontHighlightLarge")
        dividerRow.dividerText:SetTextColor(0.75, 0.75, 0.75)
        dividerRow.dividerText:Show()

        -- Slightly larger gap between the title and the first unavailable instance
        y = y - 30

        -- Now list fully-unavailable instances (no difficulties shown)
        for _, entry in ipairs(unavailableEntries) do
            local info = infoMap[entry.name]
            if info then
                local instName = info.name or entry.name

                rowIndex = rowIndex + 1
                local row = AcquireRow(rowIndex)

                row.kind         = kind
                row.instanceName = instName
                row:SetSize(content:GetWidth(), rowHeight)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, y)

                -- Hide dividerText if present
                if row.dividerText then
                    row.dividerText:Hide()
                end

                -- Hide allCheck and all difficulty controls for fully-unavailable entries
                if row.allCheck then
                    row.allCheck:Hide()
                end

                if row.diffChecks then
                    for _, cb in pairs(row.diffChecks) do
                        cb:Hide()
                    end
                end
                if row.diffLabels then
                    for _, label in pairs(row.diffLabels) do
                        label:Hide()
                    end
                end
                if row.diffLabelFrames then
                    for _, lf in pairs(row.diffLabelFrames) do
                        lf:Hide()
                    end
                end

                -- Instance name only, greyed out
                if not row.nameText then
                    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                    nameFS:SetJustifyH("LEFT")
                    row.nameText = nameFS
                end
                row.nameText:Show()
                row.nameText:ClearAllPoints()
                row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
                row.nameText:SetText(instName)
                row.nameText:SetFontObject("GameFontDisable")
                row.nameText:SetTextColor(0.5, 0.5, 0.5)

                y = y - (rowHeight + spacing)
            end
        end
    end

    -- Hide any leftover rows from previous refreshes
    for idx = rowIndex + 1, #rowsByKind do
        if rowsByKind[idx] then
            rowsByKind[idx]:Hide()
        end
    end

    local totalHeight = (textHeight + 8) + (rowIndex * (rowHeight + spacing)) + 10
    if totalHeight < 1 then totalHeight = 1 end
    content:SetHeight(totalHeight)
    content:SetWidth(LRLFFrame.scrollFrame:GetWidth())
    LRLFFrame.scrollFrame:UpdateScrollChildRect()

    -- Re-apply interactive state in case the filter is currently disabled
    LRLF_SetPanelInteractive(LRLF_FilterEnabled ~= false)
end
