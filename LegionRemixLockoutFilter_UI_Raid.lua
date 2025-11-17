--######################################################################
-- LegionRemixLockoutFilter_UI_Raid.lua
-- Raid rows, per-difficulty checkboxes, exclusive right-click logic
--######################################################################

local ADDON_NAME, ADDON_TABLE = ...

--------------------------------------------------
-- Exclusive selection helpers (RAID)
--------------------------------------------------

local function LRLF_ExclusiveClearAll(kind)
    if not LRLF_FilterState or not kind then return end

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    for instName, instState in pairs(filterKind) do
        if type(instState) == "table" then
            local sysInst = sysKind[instName]
            if not sysInst then
                sysInst = {}
                sysKind[instName] = sysInst
            end

            for diffName in pairs(instState) do
                instState[diffName] = false
                sysInst[diffName]   = false
            end
        end
    end
end

-- Right-click on raid instance name: exclusive select all *ready* difficulties
-- Note: locked diffs will NOT be auto-selected here.
function LRLF_ExclusiveRaidInstanceAllDiffs(row)
    if not row or row.kind ~= "raid" or not row.instanceName then return end

    local kind     = "raid"
    local instName = row.instanceName

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    LRLF_ExclusiveClearAll(kind)

    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local instState = filterKind[instName]
    local sysInst   = sysKind[instName]

    for _, diffName in ipairs(DIFF_ORDER) do
        local status  = row.diffStatus and row.diffStatus[diffName]
        local isReady = status and status.isReady
        if isReady then
            instState[diffName] = true
            sysInst[diffName]   = false
        else
            instState[diffName] = false
        end
    end

    LRLF_RefreshSidePanelText("raid")
end

function LRLF_ExclusiveRaidDifficulty(row, diffName)
    if not row or row.kind ~= "raid" or not row.instanceName or not diffName then
        return
    end

    local kind     = "raid"
    local instName = row.instanceName

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    LRLF_ExclusiveClearAll(kind)

    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local instState = filterKind[instName]
    local sysInst   = sysKind[instName]

    local status = row.diffStatus and row.diffStatus[diffName]
    if status and status.isUnavailable then
        LRLF_RefreshSidePanelText("raid")
        return
    end

    for _, dName in ipairs(DIFF_ORDER) do
        instState[dName] = (dName == diffName)
        sysInst[dName]   = false
    end

    LRLF_RefreshSidePanelText("raid")
end

--------------------------------------------------
-- Checkbox handlers, RAID + shared
--------------------------------------------------

local function LRLF_OnAllCheckboxClick(self)
    local row = self:GetParent()
    if not row or not row.instanceName or not row.kind then return end

    local instName = row.instanceName
    local kind     = row.kind

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local instState = filterKind[instName]
    local sysInst   = sysKind[instName]

    local checked = self:GetChecked() and true or false

    if row.kind == "raid" and row.diffChecks then
        for _, diffName in ipairs(DIFF_ORDER) do
            local cb = row.diffChecks[diffName]
            if cb and cb:IsEnabled() then
                cb:SetChecked(checked)
                instState[diffName] = checked
                sysInst[diffName]   = false
            end
        end
    else
        -- dungeons handled in dungeon file
    end

    local diffKeys = (row.kind == "raid") and DIFF_ORDER or nil
    LRLF_UpdateRowAllCheckbox(row, instState, diffKeys)
end

local function LRLF_OnDifficultyCheckboxClick(self)
    local row = self.row
    if not row or not row.instanceName or not row.kind or not self.diffName then return end

    local instName = row.instanceName
    local kind     = row.kind
    local diffName = self.diffName

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local instState = filterKind[instName]
    local sysInst   = sysKind[instName]

    local checked = self:GetChecked() and true or false
    instState[diffName] = checked
    sysInst[diffName]   = false

    local diffKeys = (row.kind == "raid") and DIFF_ORDER or nil
    LRLF_UpdateRowAllCheckbox(row, instState, diffKeys)
end

local function LRLF_DifficultyCheckbox_OnClick(self, button)
    if button == "RightButton" and self.row and self.row.kind == "raid" then
        LRLF_ExclusiveRaidDifficulty(self.row, self.diffName)
    else
        LRLF_OnDifficultyCheckboxClick(self)
    end
end

--------------------------------------------------
-- RAID row builder
--------------------------------------------------

function LRLF_RefreshRaidRows(kind, infoMap, list, textHeight)
    kind = kind or "raid"
    LRLF_Rows[kind] = LRLF_Rows[kind] or {}
    local rowsByKind = LRLF_Rows[kind]

    local content   = LRLFFrame.content
    local spacing   = 4
    local rowHeight = 34

    local y        = -textHeight - 8
    local rowIndex = 1

    local function EnsureRaidRow(index)
        local row = rowsByKind[index]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row.diffChecks = row.diffChecks or {}
            row.diffLabels = row.diffLabels or {}
            rowsByKind[index] = row
        end
        row:Show()
        row.diffStatus = row.diffStatus or {}
        return row
    end

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    local availableEntries   = {}
    local unavailableEntries = {}

    -- Classify raids into "has any playable diff" vs "fully unavailable"
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

    -- Keep the system's default ready/unavailable understanding in sync
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
                        instState[diffName] = isReady
                        sysInst[diffName]   = true
                    elseif sysInst[diffName] then
                        instState[diffName] = isReady
                    end

                    if isUnavailable and instState[diffName] then
                        instState[diffName] = false
                    end
                end
            end
        end
    end

    -- Render available + locked first
    for _, entry in ipairs(availableEntries) do
        local info = infoMap[entry.name]
        if info then
            local instName  = info.name or entry.name
            local diffs     = info.difficulties
            local instState = filterKind[instName]

            local row = EnsureRaidRow(rowIndex)
            row.kind             = "raid"
            row.instanceName     = instName
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

            row.nameText.row = row
            row.nameText:EnableMouse(true)
            row.nameText:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" and self.row and self.row.kind == "raid" then
                    LRLF_ExclusiveRaidInstanceAllDiffs(self.row)
                end
            end)

            if row.diffStatus then
                for k in pairs(row.diffStatus) do
                    row.diffStatus[k] = nil
                end
            end

            local diffXBase   = 10
            local diffSpacing = 73
            local diffY       = -18
            local slotIndex   = 0

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
                        cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                        cb:SetScript("OnClick", LRLF_DifficultyCheckbox_OnClick)
                        cb:SetScript("OnEnter", LRLF_Diff_OnEnter)
                        cb:SetScript("OnLeave", LRLF_Diff_OnLeave)
                        row.diffChecks[diffName] = cb
                    end
                    if not label then
                        label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        row.diffLabels[diffName] = label
                        label.row      = row
                        label.diffName = diffName
                        label:EnableMouse(true)
                        label:SetScript("OnEnter", LRLF_Diff_OnEnter)
                        label:SetScript("OnLeave", LRLF_Diff_OnLeave)
                        label:SetScript("OnMouseDown", function(self, button)
                            if not cb:IsEnabled() then return end
                            if button == "RightButton" and row.kind == "raid" then
                                LRLF_ExclusiveRaidDifficulty(row, diffName)
                            else
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
                    end
                else
                    if cb then cb:Hide() end
                    if label then label:Hide() end
                    if row.diffStatus then
                        row.diffStatus[diffName] = nil
                    end
                end
            end

            row.allCheck:Enable()
            row.allCheck:SetAlpha(1.0)

            LRLF_UpdateRowAllCheckbox(row, instState, DIFF_ORDER)
            LRLF_SetRowInteractive(row, LRLF_FilterEnabled)

            y = y - (rowHeight + spacing)
            rowIndex = rowIndex + 1
        end
    end

    local hasUnavailable = #unavailableEntries > 0
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
        for _, entry in ipairs(unavailableEntries) do
            local info = infoMap[entry.name]
            if info then
                local instName = info.name or entry.name

                local row = EnsureRaidRow(rowIndex)
                row.kind             = "raid"
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
                row.nameText:EnableMouse(false)

                for _, diffName in ipairs(DIFF_ORDER) do
                    local cb    = row.diffChecks[diffName]
                    local label = row.diffLabels[diffName]
                    if cb then cb:Hide() end
                    if label then label:Hide() end
                    if row.diffStatus then
                        row.diffStatus[diffName] = nil
                    end
                end

                LRLF_SetRowInteractive(row, LRLF_FilterEnabled)

                y = y - (rowHeight + spacing)
                rowIndex = rowIndex + 1
            end
        end
    end

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
end
