-- Small selector for browsing and applying Top-N complete configurations.

local LegacyCreateProgressFrame = TopFit.CreateProgressFrame

local function SetButtonEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

function TopFit:RefreshAlternativeControls(showCombination)
    local frame = self.ProgressFrame
    if not frame or not frame.alternativeSelectorText then
        return
    end

    local setCode = frame.selectedSet
    local entries = self:GetAlternativeEntries(setCode)
    if #entries <= 1 or (frame.progressBar and frame.progressBar:IsShown()) then
        frame.alternativePrevButton:Hide()
        frame.alternativeNextButton:Hide()
        frame.alternativeSelectorText:Hide()
        frame.alternativeUseButton:Hide()
        return
    end

    self.selectedAlternativeBySet = self.selectedAlternativeBySet or {}
    local index = self.selectedAlternativeBySet[setCode] or 1
    if index < 1 then
        index = 1
    elseif index > #entries then
        index = #entries
    end
    self.selectedAlternativeBySet[setCode] = index

    local percent = self:GetAlternativePercentOfBest(setCode, index) or 0
    frame.alternativeSelectorText:SetText(index .. "/" .. #entries .. "  " .. round(percent, 1) .. "%")

    SetButtonEnabled(frame.alternativePrevButton, index > 1)
    SetButtonEnabled(frame.alternativeNextButton, index < #entries)

    frame.alternativePrevButton:Show()
    frame.alternativeNextButton:Show()
    frame.alternativeSelectorText:Show()
    frame.alternativeUseButton:Show()

    if showCombination then
        frame:SetCurrentCombination(entries[index].combination)
    end
end

function TopFit:SelectAlternative(delta)
    local frame = self.ProgressFrame
    local setCode = frame and frame.selectedSet
    local entries = self:GetAlternativeEntries(setCode)
    if #entries == 0 then
        return
    end

    local index = (self.selectedAlternativeBySet and self.selectedAlternativeBySet[setCode]) or 1
    index = math.max(1, math.min(#entries, index + delta))
    self.selectedAlternativeBySet[setCode] = index
    self:RefreshAlternativeControls(true)
end

function TopFit:UseSelectedAlternative()
    local frame = self.ProgressFrame
    local setCode = frame and frame.selectedSet
    if not setCode then
        return
    end

    local index = (self.selectedAlternativeBySet and self.selectedAlternativeBySet[setCode]) or 1
    local combination = self:GetAlternativeCombination(setCode, index)
    if not combination then
        return
    end

    self.setCode = setCode
    self:SetRecommendationsFromCombination(combination)
    self:EquipRecommendedItems()
end

function TopFit:InstallAlternativeControls()
    local frame = self.ProgressFrame
    if not frame or frame.alternativeSelectorText then
        return
    end

    frame.alternativePrevButton = CreateFrame("Button", "TopFit_AlternativePrevButton", frame, "UIPanelButtonTemplate")
    frame.alternativePrevButton:SetWidth(24)
    frame.alternativePrevButton:SetHeight(22)
    frame.alternativePrevButton:SetPoint("TOPLEFT", frame.selectSetLabel, "BOTTOMLEFT", 2, 0)
    frame.alternativePrevButton:SetText("<")
    frame.alternativePrevButton:SetScript("OnClick", function()
        TopFit:SelectAlternative(-1)
    end)

    frame.alternativeSelectorText =
        frame:CreateFontString("TopFit_AlternativeSelectorText", "ARTWORK", "GameFontHighlightSmall")
    frame.alternativeSelectorText:SetWidth(72)
    frame.alternativeSelectorText:SetHeight(22)
    frame.alternativeSelectorText:SetPoint("LEFT", frame.alternativePrevButton, "RIGHT", 2, 0)
    frame.alternativeSelectorText:SetJustifyH("CENTER")

    frame.alternativeNextButton = CreateFrame("Button", "TopFit_AlternativeNextButton", frame, "UIPanelButtonTemplate")
    frame.alternativeNextButton:SetWidth(24)
    frame.alternativeNextButton:SetHeight(22)
    frame.alternativeNextButton:SetPoint("LEFT", frame.alternativeSelectorText, "RIGHT", 2, 0)
    frame.alternativeNextButton:SetText(">")
    frame.alternativeNextButton:SetScript("OnClick", function()
        TopFit:SelectAlternative(1)
    end)

    frame.alternativeUseButton = CreateFrame("Button", "TopFit_AlternativeUseButton", frame, "UIPanelButtonTemplate")
    frame.alternativeUseButton:SetWidth(44)
    frame.alternativeUseButton:SetHeight(22)
    frame.alternativeUseButton:SetPoint("LEFT", frame.alternativeNextButton, "RIGHT", 2, 0)
    frame.alternativeUseButton:SetText("Use")
    frame.alternativeUseButton:SetScript("OnClick", function()
        TopFit:UseSelectedAlternative()
    end)

    frame.alternativeUseButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(
            "Use this complete configuration. Banked, BoE, virtual, or gem/enchant-modified items "
                .. "remain manual and will not be auto-equipped.",
            nil,
            nil,
            nil,
            nil,
            true
        )
        GameTooltip:Show()
    end)
    frame.alternativeUseButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local LegacyResetProgress = frame.ResetProgress
    frame.ResetProgress = function(frameSelf, ...)
        local result = LegacyResetProgress(frameSelf, ...)
        TopFit:RefreshAlternativeControls(false)
        return result
    end

    local LegacyStoppedCalculation = frame.StoppedCalculation
    frame.StoppedCalculation = function(frameSelf, ...)
        local result = LegacyStoppedCalculation(frameSelf, ...)
        TopFit:RefreshAlternativeControls(false)
        return result
    end

    local LegacySetSelectedSet = frame.SetSelectedSet
    frame.SetSelectedSet = function(frameSelf, setCode, ...)
        local result = LegacySetSelectedSet(frameSelf, setCode, ...)
        if frameSelf.selectedSet then
            TopFit.selectedAlternativeBySet = TopFit.selectedAlternativeBySet or {}
            TopFit.selectedAlternativeBySet[frameSelf.selectedSet] = 1
        end
        TopFit:RefreshAlternativeControls(true)
        return result
    end

    self:RefreshAlternativeControls(false)
end

function TopFit:CreateProgressFrame(...)
    local result = LegacyCreateProgressFrame(self, ...)
    self:InstallAlternativeControls()
    self:RefreshAlternativeControls(false)
    return result
end
