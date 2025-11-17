-- LegionRemixLockoutFilter_UI_Dungeon.lua
-- Dungeon-specific UI logic for Legion Remix Lockout Filter

local ADDON_NAME, ADDON_TABLE = ...

local LRLF_LFG = ADDON_TABLE.LFG or {}

-- UI selection mode for dungeons:
--   "MYTHIC"   = base Mythic (M0, with lockouts)
--   "KEYSTONE" = Mythic+ / MythicKeystone (no lockouts)
LRLF_DungeonMode = LRLF_DungeonMode or "MYTHIC"

----------------------------------------------------------------------
-- Local helpers
-- Core UI provides:
--   LRLF_SetDiffStatus(row, diffName, isReady, isLocked, isUnavailable, lockoutReset)
--   LRLF_SetRowInteractive(row, enabled)
--   LRLF_UpdateFilterEnabledVisualState()
--   LRLF_RefreshSidePanelText(kind)
--   LRLF_Diff_OnEnter / LRLF_Diff_OnLeave
----------------------------------------------------------------------

local function EnsureDungeonRow(rowsByKind, content, index)
    local row = rowsByKind[index]
    if not row then
        row = CreateFrame("Frame", nil, content)
        row.diffChecks  = row.diffChecks  or {}
        row.diffLabels  = row.diffLabels  or {}
        row.activeDiffs = row.activeDiffs or {}
        row.diffStatus  = row.diffStatus  or {}
        rowsByKind[index] = row
    end
    row:Show()
    row.diffStatus  = row.diffStatus  or {}
    row.activeDiffs = row.activeDiffs or {}
    return row
end

-- Normalize current dungeon mode into a diffKey we use in FilterState
local function LRLF_GetCurrentDungeonDiffKey()
    local modeVal     = LRLF_DungeonMode
    local dungeonMode = (modeVal == "KEYSTONE") and "KEYSTONE" or "MYTHIC"
    local diffKey     = (dungeonMode == "KEYSTONE") and "MythicKeystone" or "Mythic"
    return dungeonMode, diffKey
end

----------------------------------------------------------------------
-- "All" checkbox handler for dungeon rows
-- (kept separate from raid logic; only touches the active diffKey)
----------------------------------------------------------------------

function LRLF_DungeonAllCheckbox_OnClick(self)
    local row = self.row or self:GetParent()
    if not row or row.kind ~= "dungeon" or not row.instanceName then
        return
    end

    local kind     = "dungeon"
    local instName = row.instanceName

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local instState = filterKind[instName]
    local sysInst   = sysKind[instName]

    local _, diffKey = LRLF_GetCurrentDungeonDiffKey()

    local checked = self:GetChecked() and true or false

    -- If the row is flagged as fully unavailable, force it off.
    if row.isAllUnavailable then
        checked = false
        self:SetChecked(false)
    end

    instState[diffKey] = checked
    sysInst[diffKey]   = false -- user-managed for this diffKey

    -- For dungeons, the "All" box == this one diffKey
    row.allCheck:SetChecked(checked)
end

----------------------------------------------------------------------
-- Select all "ready" dungeons for the current dungeon mode
----------------------------------------------------------------------

function LRLF_DungeonSelectAllReady()
    local kind = "dungeon"

    local infoMap, dungeons = LRLF_LFG.BuildDungeonDifficultyInfo()
    if not infoMap or not dungeons then
        return
    end

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    local _, diffKey = LRLF_GetCurrentDungeonDiffKey()

    for _, dungeon in ipairs(dungeons) do
        local info = infoMap[dungeon.name]
        if info and info.difficulties then
            local instName = info.name or dungeon.name
            local diffs    = info.difficulties
            local d        = diffs[diffKey]

            if d then
                local isLocked = d.hasLockout and (diffKey == "Mythic")
                local isReady  = (d.available and not isLocked)

                filterKind[instName] = filterKind[instName] or {}
                sysKind[instName]    = sysKind[instName]    or {}

                local instState = filterKind[instName]
                local sysInst   = sysKind[instName]

                instState[diffKey] = isReady
                sysInst[diffKey]   = true
            end
        end
    end

    LRLF_RefreshSidePanelText("dungeon")
end

-- Update top buttons (All / Mythic / Mythic+) text color
function LRLF_UpdateDungeonModeButtons()
    if not LRLFFrame or not LRLFFrame.dungeonTopButtons then
        return
    end

    local btnAll      = LRLFFrame.dungeonTopButtons.All
    local btnMythic   = LRLFFrame.dungeonTopButtons.MYTHIC
    local btnKeystone = LRLFFrame.dungeonTopButtons.KEYSTONE

    if btnMythic then
        if LRLF_DungeonMode == "MYTHIC" then
            btnMythic:GetFontString():SetTextColor(1, 0.82, 0)
        else
            btnMythic:GetFontString():SetTextColor(0.9, 0.9, 0.9)
        end
    end

    if btnKeystone then
        if LRLF_DungeonMode == "KEYSTONE" then
            btnKeystone:GetFontString():SetTextColor(0.4, 0.6, 1.0)
        else
            btnKeystone:GetFontString():SetTextColor(0.9, 0.9, 0.9)
        end
    end

    if btnAll then
        btnAll:GetFontString():SetTextColor(1, 1, 1)
    end
end

----------------------------------------------------------------------
-- Exclusive selection for dungeon instances (right-click on name)
-- IMPORTANT: only clears the active diffKey so Mythic vs Keystone are independent
----------------------------------------------------------------------

local function LRLF_ExclusiveDungeonInstance(row)
    if not row or row.kind ~= "dungeon" or not row.instanceName then
        return
    end

    local kind     = "dungeon"
    local instName = row.instanceName

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    local _, diffKey = LRLF_GetCurrentDungeonDiffKey()

    -- Clear only the active diffKey across all dungeons
    for otherName, instState in pairs(filterKind) do
        if type(instState) == "table" then
            local sysInst = sysKind[otherName]
            if not sysInst then
                sysInst = {}
                sysKind[otherName] = sysInst
            end
            instState[diffKey] = false
            sysInst[diffKey]   = false
        end
    end

    -- Now set just this instance for the active mode
    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local myState = filterKind[instName]
    local mySys   = sysKind[instName]

    myState[diffKey] = true
    mySys[diffKey]   = false

    LRLF_RefreshSidePanelText("dungeon")
end

----------------------------------------------------------------------
-- Dungeon rows
-- Called from LRLF_RefreshSidePanelText (core UI)
----------------------------------------------------------------------

function LRLF_RefreshDungeonRows(kind, infoMap, list, textHeight)
    kind = "dungeon"  -- dungeon-only function

    if not LRLFFrame or not LRLFFrame.scrollFrame or not LRLFFrame.text then
        return
    end
    if type(infoMap) ~= "table" then
        return
    end

    -- Tight layout: slightly shorter rows and reduced gap between rows
    local rowHeight = 26
    local spacing   = -5

    ------------------------------------------------------------------
    -- Build ordered list of entries
    ------------------------------------------------------------------

    local entries = {}
    if type(list) == "table" and #list > 0 and list[1] and list[1].name then
        for _, entry in ipairs(list) do
            table.insert(entries, entry)
        end
    else
        for name, entry in pairs(infoMap) do
            table.insert(entries, { id = entry.id, name = name })
        end
        table.sort(entries, function(a, b) return a.name < b.name end)
    end

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    LRLF_Rows[kind] = LRLF_Rows[kind] or {}
    local rowsByKind = LRLF_Rows[kind]

    local textFS = LRLFFrame.text
    textHeight   = textFS:GetStringHeight() or 0
    local content = LRLFFrame.scrollFrame:GetScrollChild()

    local y        = -textHeight - 8
    local rowIndex = 1

    ------------------------------------------------------------------
    -- Determine mode + difficulty key
    ------------------------------------------------------------------

    local dungeonMode, diffKey = LRLF_GetCurrentDungeonDiffKey()

    local availableEntries   = {}
    local unavailableEntries = {}

    -- For Mythic+ mode, some dungeons should never be listed at all,
    -- even if the LFG API exposes a keystone diff for them.
    local KEYSTONE_SUPPRESS = {
        ["Assault on Violet Hold"]     = true,
        ["Cathedral of Eternal Night"] = true,
        ["Return to Karazhan"]         = true,
    }

    ------------------------------------------------------------------
    -- Classify each dungeon using EJ+LFG difficulty data
    ------------------------------------------------------------------

    for _, entry in ipairs(entries) do
        local info = infoMap[entry.name]
        if info and info.difficulties then
            local instName = info.name or entry.name
            local diffs    = info.difficulties

            -- Special rule: Upper/Lower Kara should be Mythic+ only,
            -- but base "Return to Karazhan" should never appear in Keystone.
            if dungeonMode == "MYTHIC"
               and (instName == "Return to Karazhan: Lower" or instName == "Return to Karazhan: Upper")
            then
                -- skip Upper/Lower on Mythic tab
            elseif dungeonMode == "KEYSTONE"
               and KEYSTONE_SUPPRESS[instName]
            then
                -- skip these entirely on Mythic+ tab
            else
                local d = diffs[diffKey]

                if d then
                    -- Determine availability state
                    local isLocked      = d.hasLockout and (diffKey == "Mythic")
                    local isReady       = (d.available and not isLocked)
                    local isUnavailable = (not d.available and not d.hasLockout)

                    ------------------------------------------------------------------
                    -- Override for Kara Upper/Lower in Mythic+:
                    -- They ARE available keystone dungeons in Remix.
                    ------------------------------------------------------------------
                    if dungeonMode == "KEYSTONE"
                       and (instName == "Return to Karazhan: Lower" or instName == "Return to Karazhan: Upper")
                    then
                        isLocked      = false
                        isReady       = true
                        isUnavailable = false
                    end

                    filterKind[instName] = filterKind[instName] or {}
                    sysKind[instName]    = sysKind[instName]    or {}

                    local instState = filterKind[instName]
                    local sysInst   = sysKind[instName]

                    if instState[diffKey] == nil then
                        instState[diffKey] = isReady
                        sysInst[diffKey]   = true
                    elseif sysInst[diffKey] then
                        instState[diffKey] = isReady
                    end

                    if isReady or isLocked then
                        table.insert(availableEntries, {
                            info     = info,
                            instName = instName,
                            diff     = d,
                            isReady  = isReady,
                            isLocked = isLocked,
                        })
                    else
                        -- Has this difficulty in principle, but not
                        -- available yet and no lockout -> unavailable.
                        table.insert(unavailableEntries, {
                            info     = info,
                            instName = instName,
                        })
                    end
                else
                    -- No entry for this diffKey:
                    --   * Mythic tab: dungeon exists but has no Mythic diff -> unavailable.
                    --   * Mythic+ tab: dungeon has no keystone diff at all -> skip entirely.
                    if dungeonMode == "MYTHIC" then
                        table.insert(unavailableEntries, {
                            info     = info,
                            instName = instName,
                        })
                    end
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Build rows for available dungeons (with green/red squares)
    ------------------------------------------------------------------

    for _, data in ipairs(availableEntries) do
        local instName = data.instName
        local d        = data.diff
        local isReady  = data.isReady
        local isLocked = data.isLocked

        local instState = filterKind[instName]

        local row = EnsureDungeonRow(rowsByKind, content, rowIndex)
        row.kind             = "dungeon"
        row.instanceName     = instName
        row.isAllUnavailable = false

        row:SetSize(content:GetWidth(), rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)

        -- "All" checkbox
        if not row.allCheck then
            local cbAll = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cbAll:SetSize(18, 18)
            cbAll:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            cbAll.row = row
            cbAll:SetScript("OnClick", LRLF_DungeonAllCheckbox_OnClick)
            row.allCheck = cbAll
        else
            row.allCheck:Show()
            row.allCheck:ClearAllPoints()
            row.allCheck:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.allCheck.row = row
            row.allCheck:SetScript("OnClick", LRLF_DungeonAllCheckbox_OnClick)
        end

        -- Instance name
        if not row.nameText then
            local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameFS:SetJustifyH("LEFT")
            row.nameText = nameFS
        end
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("TOPLEFT", row.allCheck, "TOPRIGHT", 4, 0)
        row.nameText:SetText(instName)

        if dungeonMode == "KEYSTONE" then
            row.nameText:SetFontObject("GameFontNormal")
            row.nameText:SetTextColor(0.4, 0.6, 1.0) -- blue-ish for M+
        else
            row.nameText:SetFontObject("GameFontNormal")
            row.nameText:SetTextColor(1, 0.82, 0)   -- gold-ish for M0
        end

        -- Click name:
        --   Left-click  => toggles this instance's checkbox
        --   Right-click => exclusive selection for this instance
        row.nameText.row = row
        row.nameText:EnableMouse(true)
        row.nameText:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                LRLF_ExclusiveDungeonInstance(row)
            else
                if row.allCheck and row.allCheck:IsEnabled() then
                    row.allCheck:Click()
                end
            end
        end)

        -- Clear old diff status
        if row.diffStatus then
            for k in pairs(row.diffStatus) do
                row.diffStatus[k] = nil
            end
        end

        -- Single-diff status for this mode
        LRLF_SetDiffStatus(row, diffKey, isReady, isLocked, false, d.lockoutReset)

        local selected = instState and instState[diffKey]
        row.allCheck:SetChecked(selected and true or false)
        row.allCheck:Enable()
        row.allCheck:SetAlpha(1.0)

        -- Colored state square (green = ready, red = locked)
        if not row.stateIcon then
            local tex = row:CreateTexture(nil, "ARTWORK")
            tex:SetSize(10, 10)
            tex:SetPoint("RIGHT", row, "RIGHT", -4, -2)
            row.stateIcon = tex
            row.stateIcon.row      = row
            row.stateIcon.diffName = diffKey
            row.stateIcon:SetScript("OnEnter", LRLF_Diff_OnEnter)
            row.stateIcon:SetScript("OnLeave", LRLF_Diff_OnLeave)
        end

        local icon = row.stateIcon
        icon:Show()
        if isLocked then
            icon:SetColorTexture(1.0, 0.2, 0.2, 1.0) -- red
        else
            icon:SetColorTexture(0.2, 1.0, 0.2, 1.0) -- green
        end

        LRLF_SetRowInteractive(row, LRLF_FilterEnabled)

        y = y - (rowHeight + spacing)
        rowIndex = rowIndex + 1
    end

    ------------------------------------------------------------------
    -- "Currently unavailable" header + rows (no squares)
    ------------------------------------------------------------------

    local hasUnavailable = (#unavailableEntries > 0)

    if LRLFFrame.unavailableHeader then
        if hasUnavailable then
            local headerFS = LRLFFrame.unavailableHeader
            headerFS:Show()
            headerFS:SetText("Currently unavailable")
            headerFS:SetFontObject("GameFontHighlightSmall")
            headerFS:SetTextColor(0.7, 0.7, 0.7)
            headerFS:SetJustifyH("CENTER")

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
        for _, data in ipairs(unavailableEntries) do
            local instName = data.instName

            local row = EnsureDungeonRow(rowsByKind, content, rowIndex)
            row.kind             = "dungeon"
            row.instanceName     = instName
            row.isAllUnavailable = true

            row:SetSize(content:GetWidth(), rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)

            -- All checkbox disabled
            if not row.allCheck then
                local cbAll = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                cbAll:SetSize(18, 18)
                cbAll:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
                cbAll.row = row
                cbAll:SetScript("OnClick", LRLF_DungeonAllCheckbox_OnClick)
                row.allCheck = cbAll
            end

            row.allCheck:SetChecked(false)
            row.allCheck:Disable()
            row.allCheck:SetAlpha(0.4)

            -- Instance name greyed out
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
            row.nameText:EnableMouse(false)

            -- No colored square for unavailable rows
            if row.stateIcon then
                row.stateIcon:Hide()
            end

            if row.diffStatus then
                for k in pairs(row.diffStatus) do
                    row.diffStatus[k] = nil
                end
            end
            if row.activeDiffs then
                for k in pairs(row.activeDiffs) do
                    row.activeDiffs[k] = nil
                end
            end

            LRLF_SetRowInteractive(row, LRLF_FilterEnabled)

            y = y - (rowHeight + spacing)
            rowIndex = rowIndex + 1
        end
    end

    ------------------------------------------------------------------
    -- Hide any leftover rows and update scroll size
    ------------------------------------------------------------------

    for idx = rowIndex, #rowsByKind do
        if rowsByKind[idx] then
            rowsByKind[idx]:Hide()
        end
    end

    local totalHeight = (textHeight + 8) + ((rowIndex - 1) * (rowHeight + spacing)) + 20
    if totalHeight < 1 then
        totalHeight = 1
    end
    content:SetHeight(totalHeight)
    content:SetWidth(LRLFFrame.scrollFrame:GetWidth())
    LRLFFrame.scrollFrame:UpdateScrollChildRect()

    LRLF_UpdateFilterEnabledVisualState()
end
