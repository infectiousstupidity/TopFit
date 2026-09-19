-- Upgrade-planner plugin: run a current-phase source scan and preview whole-set gains.

local LegacyOnInitialize = TopFit.OnInitialize
local upgradeFrame

local function ShowItemTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.itemLink then
        GameTooltip:SetHyperlink(self.itemLink)
        if self.sourceText and self.sourceText ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.sourceText, 0.4, 0.8, 1, true)
        end
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

local function StatusText()
    local progress = TopFit:GetUpgradeScanProgress()
    if progress then
        if progress.stage == "loading" or progress.stage == "ready" then
            return "Loading source items: "
                .. tostring(progress.resolved or 0)
                .. " ready, "
                .. tostring(progress.unresolved or 0)
                .. " pending"
        elseif progress.stage == "baseline" then
            return "Calculating owned baseline..."
        elseif progress.stage == "evaluating" then
            local item = progress.candidate and progress.candidate.itemLink or "candidate"
            return "Evaluating " .. tostring(progress.current) .. "/" .. tostring(progress.total) .. ": " .. item
        end
    end

    local setCode = TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet
    local summary = TopFit.lastUpgradeScanBySet and TopFit.lastUpgradeScanBySet[setCode]
    if not summary then
        return "Scans Ulduar and Vault of Archavon upgrades available in ChromieCraft Phase 3."
    end
    if summary.error then
        return summary.error
    end
    if summary.cancelled then
        return "Scan cancelled after " .. tostring(summary.evaluated or 0) .. " candidate(s)."
    end
    return "Evaluated "
        .. tostring(summary.evaluated or 0)
        .. "/"
        .. tostring(summary.shortlisted or 0)
        .. " shortlisted candidates."
end

local function EnsureResultButton(frame, index)
    if frame.resultButtons[index] then
        return frame.resultButtons[index]
    end

    local button = CreateFrame("Button", "$parent_UpgradeResult" .. index, frame.resultsContent)
    button:SetHeight(34)
    button:SetPoint("LEFT", frame.resultsContent, "LEFT", 2, 0)
    button:SetPoint("RIGHT", frame.resultsContent, "RIGHT", -2, 0)
    if index == 1 then
        button:SetPoint("TOP", frame.resultsContent, "TOP", 0, 0)
    else
        button:SetPoint("TOP", frame.resultButtons[index - 1], "BOTTOM", 0, -2)
    end
    button:SetHighlightTexture("Interface\\Buttons\\UI-ListBox-Highlight")

    button.itemText = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    button.itemText:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.itemText:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    button.itemText:SetJustifyH("LEFT")

    button.sourceTextLabel = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    button.sourceTextLabel:SetPoint("TOPLEFT", button.itemText, "BOTTOMLEFT", 0, -1)
    button.sourceTextLabel:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    button.sourceTextLabel:SetJustifyH("LEFT")

    button:SetScript("OnEnter", ShowItemTooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnClick", function(self)
        if self.result and TopFit.ProgressFrame then
            TopFit.ProgressFrame:SetCurrentCombination(self.result.combination)
        end
    end)

    frame.resultButtons[index] = button
    return button
end

function TopFit:RefreshUpgradePlannerPlugin()
    local frame = upgradeFrame
    if not frame or not frame.initialized then
        return
    end

    local setCode = self.ProgressFrame and self.ProgressFrame.selectedSet
    frame.statusText:SetText(StatusText())

    if self.upgradeScan then
        frame.scanButton:SetText("Abort scan")
        frame.scanButton:Enable()
    elseif setCode then
        frame.scanButton:SetText("Scan Phase 3 upgrades")
        frame.scanButton:Enable()
    else
        frame.scanButton:SetText("Scan Phase 3 upgrades")
        frame.scanButton:Disable()
    end

    local results = setCode and self:GetUpgradeResults(setCode) or {}
    for index, result in ipairs(results) do
        local button = EnsureResultButton(frame, index)
        button.result = result
        button.itemLink = result.candidate.itemLink
        button.sourceText = result.sourceText
        button.itemText:SetText(
            result.candidate.itemLink
                .. "  |cff00ff00+"
                .. round(result.gain, 2)
                .. " ("
                .. round(result.gainPercent, 2)
                .. "%)|r"
        )
        button.sourceTextLabel:SetText(result.sourceText or "")
        button:Show()
    end
    for index = #results + 1, #frame.resultButtons do
        frame.resultButtons[index]:Hide()
    end

    frame.resultsContent:SetHeight(math.max(1, #results * 36))
end

function TopFit:CreateUpgradePlannerPlugin()
    local frame, pluginID = self:RegisterPlugin(
        "Upgrades",
        "Evaluate currently available raid drops by adding each candidate and re-running the complete optimizer."
    )
    upgradeFrame = frame
    frame.initialized = false

    self.RegisterCallback("TopFit_upgrades", "OnShow", function(_, id)
        if id ~= pluginID then
            return
        end

        if not frame.initialized then
            frame.scanButton = CreateFrame("Button", "$parent_ScanButton", frame, "UIPanelButtonTemplate")
            frame.scanButton:SetWidth(150)
            frame.scanButton:SetHeight(22)
            frame.scanButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.scanButton:SetScript("OnClick", function()
                if TopFit.upgradeScan then
                    TopFit:AbortCalculations()
                elseif TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet then
                    local ok = TopFit:StartUpgradeScan(TopFit.ProgressFrame.selectedSet)
                    if not ok then
                        TopFit:Print("Upgrade scan could not start because another calculation is active.")
                    end
                end
            end)

            frame.statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            frame.statusText:SetPoint("TOPLEFT", frame.scanButton, "BOTTOMLEFT", 0, -8)
            frame.statusText:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
            frame.statusText:SetJustifyH("LEFT")
            frame.statusText:SetWordWrap(true)
            frame.statusText:SetHeight(34)

            frame.resultsFrame = CreateFrame("ScrollFrame", "$parent_Results", frame, "UIPanelScrollFrameTemplate")
            frame.resultsFrame:SetPoint("TOPLEFT", frame.statusText, "BOTTOMLEFT", 0, -6)
            frame.resultsFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 0)

            frame.resultsContent = CreateFrame("Frame", nil, frame.resultsFrame)
            frame.resultsContent:SetWidth(100)
            frame.resultsContent:SetHeight(1)
            frame.resultsContent:SetAllPoints()
            frame.resultsFrame:SetScrollChild(frame.resultsContent)
            frame.resultButtons = {}
            frame.initialized = true
        end

        TopFit:RefreshUpgradePlannerPlugin()
    end)

    self.RegisterCallback("TopFit_upgrades_set", "OnSetChanged", function()
        TopFit:RefreshUpgradePlannerPlugin()
    end)
end

function TopFit:OnInitialize()
    LegacyOnInitialize(self)
    self:CreateUpgradePlannerPlugin()
end
