--######################################################################
-- LegionRemixLockoutFilter_UI_Raid.lua
-- Raid rows, per-difficulty checkboxes, exclusive right-click logic
--######################################################################

local ADDON_NAME, ADDON_TABLE = ...

local RAID_KIND = "raid"

--------------------------------------------------
-- Shared raid-state helpers
--------------------------------------------------

local function EnsureRaidKindState()
    LRLF_FilterState[RAID_KIND]     = LRLF_FilterState[RAID_KIND]     or {}
    LRLF_SystemSelection[RAID_KIND] = LRLF_SystemSelection[RAID_KIND] or {}
    return LRLF_FilterState[RAID_KIND], LRLF_SystemSelection[RAID_KIND]
end

local function EnsureRaidInstanceState(instName)
    local filterKind, sysKind = EnsureRaidKindState()
    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}
    return filterKind, sysKind, filterKind[instName], sysKind[instName]
end

local function LRLF_ExclusiveClearAll()
    local filterKind, sysKind = EnsureRaidKindState()

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

--------------------------------------------------
-- Name-click behaviors (instance-level)
--------------------------------------------------

-- Left-click on raid instance name: toggle ready diffs for that instance
-- If any ready diff is selected -> clear all diffs for that instance.
-- If none are selected -> select only ready (non-locked, non-unavailable) diffs.
local function LRLF_SelectRaidInstanceReadyDiffs(row)
    if not row or row.kind ~= RAID_KIND or not row.instanceName then return end

    local instName                = row.instanceName
    local _, _, instState, sysInst = EnsureRaidInstanceState(instName)

    -- First, see if any ready diff is currently selected
    local hasSelectedReady = false
    for _, diffName in ipairs(DIFF_ORDER) do
        local status  = row.diffStatus and row.diffStatus[diffName]
        local isReady = status and status.isReady
        if isReady and instState[diffName] then
            hasSelectedReady = true
            break
        end
    end

    if hasSelectedReady then
        -- Toggle OFF: clear all diffs for this instance
        for _, diffName in ipairs(DIFF_ORDER) do
            instState[diffName] = false
            sysInst[diffName]   = false
        end
    else
        -- Toggle ON: select only ready, non-locked, non-unavailable diffs
        for _, diffName in ipairs(DIFF_ORDER) do
            local status        = row.diffStatus and row.diffStatus[diffName]
            local isReady       = status and status.isReady
            local isLocked      = status and status.isLocked
            local isUnavailable = status and status.isUnavailable

            if isReady and not isLocked and not isUnavailable then
                instState[diffName] = true
            else
                instState[diffName] = false
            end

            sysInst[diffName] = false
        end
    end

    LRLF_RefreshSidePanelText(RAID_KIND)
end

-- Right-click on raid instance name: exclusive select all *ready* difficulties
-- (Clears all other raids first; avoids locked/unavailable)
function LRLF_ExclusiveRaidInstanceAllDiffs(row)
    if not row or row.kind ~= RAID_KIND or not row.instanceName then return end

    local instName                = row.instanceName
    LRLF_ExclusiveClearAll()
    local _, _, instState, sysInst = EnsureRaidInstanceState(instName)

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

    LRLF_RefreshSidePanelText(RAID_KIND)
end

function LRLF_ExclusiveRaidDifficulty(row, diffName)
    if not row or row.kind ~= RAID_KIND or not row.instanceName or not diffName then
        return
    end

    LRLF_ExclusiveClearAll()

    local instName                = row.instanceName
    local _, _, instState, sysInst = EnsureRaidInstanceState(instName)

    local status = row.diffStatus and row.diffStatus[diffName]
    if status and status.isUnavailable then
        LRLF_RefreshSidePanelText(RAID_KIND)
        return
    end

    for _, dName in ipairs(DIFF_ORDER) do
        instState[dName] = (dName == diffName)
        sysInst[dName]   = false
    end

    LRLF_RefreshSidePanelText(RAID_KIND)
end

--------------------------------------------------
-- Checkbox handlers, RAID + shared
--------------------------------------------------

local function LRLF_OnAllCheckboxClick(self)
    local row = self:GetParent()
    if not row or not row.instanceName or not row.kind then return end

    local instName                = row.instanceName
    local _, _, instState, sysInst = EnsureRaidInstanceState(instName)

    local checked = self:GetChecked() and true or false

    if row.kind == RAID_KIND and row.diffChecks then
        for _, diffName in ipairs(DIFF_ORDER) do
            local cb     = row.diffChecks[diffName]
            local status = row.diffStatus and row.diffStatus[diffName]

            if cb and cb:IsEnabled() then
                if checked then
                    -- Only auto-select ready (not locked / unavailable)
                    local isReady       = status and status.isReady
                    local isLocked      = status and status.isLocked
                    local isUnavailable = status and status.isUnavailable

                    if isReady and not isLocked and not isUnavailable then
                        cb:SetChecked(true)
                        instState[diffName] = true
                    else
                        cb:SetChecked(false)
                        instState[diffName] = false
                    end
                else
                    -- Unchecking "All" -> clear everything that's enabled
                    cb:SetChecked(false)
                    instState[diffName] = false
                end
                sysInst[diffName] = false
            end
        end
    else
        -- dungeons handled in dungeon file
    end

    LRLF_UpdateRowAllCheckbox(row, instState, DIFF_ORDER)
end

local function LRLF_OnDifficultyCheckboxClick(self)
    local row = self.row
    if not row or not row.instanceName or not row.kind or not self.diffName then return end

    local instName                = row.instanceName
    local _, _, instState, sysInst = EnsureRaidInstanceState(instName)

    local diffName = self.diffName
    local checked  = self:GetChecked() and true or false

    instState[diffName] = checked
    sysInst[diffName]   = false

    LRLF_UpdateRowAllCheckbox(row, instState, DIFF_ORDER)
end

local function LRLF_DifficultyCheckbox_OnClick(self, button)
    if button == "RightButton" and self.row and self.row.kind == RAID_KIND then
        LRLF_ExclusiveRaidDifficulty(self.row, self.diffName)
    else
        LRLF_OnDifficultyCheckboxClick(self)
    end
end

--------------------------------------------------
-- RAID row builder
--------------------------------------------------

function LRLF_RefreshRaidRows(kind, infoMap, list, textHeight)
    kind = kind or RAID_KIND
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

    local filterKind, sysKind = EnsureRaidKindState()

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
            row.kind             = RAID_KIND
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
            row.nameText.row = row
            row.nameText:EnableMouse(true)
            row.nameText:SetScript("OnMouseDown", function(self, button)
                if not self.row or self.row.kind ~= RAID_KIND then
                    return
                end
                if button == "RightButton" then
                    LRLF_ExclusiveRaidInstanceAllDiffs(self.row)
                else
                    LRLF_SelectRaidInstanceReadyDiffs(self.row)
                end
            end)

            -- Clear previous diff status
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
                            if button == "RightButton" and row.kind == RAID_KIND then
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
                    else
                        cb:SetChecked(selected and true or false)
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

    -- "Currently unavailable" section
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
                row.kind             = RAID_KIND
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

    -- Hide leftover rows
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
