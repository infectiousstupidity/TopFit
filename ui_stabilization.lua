-- Stabilization adapter for the legacy TopFit frame/plugin UI.
--
-- Keep fixes here instead of rewriting the large legacy frame/stats files. This module loads after
-- all plugin definitions but before AceAddon calls OnInitialize, so it can wrap their constructors.

local LegacyCreateStatsPlugin = TopFit.CreateStatsPlugin
local LegacyCreateProgressFrame = TopFit.CreateProgressFrame
local LegacyStartUpgradeScan = TopFit.StartUpgradeScan
local LegacyRefreshUpgradePlannerPlugin = TopFit.RefreshUpgradePlannerPlugin

function TopFit.HasMeaningfulWeights(weights)
    for _, value in pairs(weights or {}) do
        local numeric = tonumber(value)
        if numeric and numeric ~= 0 then
            return true
        end
    end
    return false
end

function TopFit.HasConfiguredWeights(weights)
    return next(weights or {}) ~= nil
end

function TopFit:IsSetReadyForCalculation(setCode)
    local set = self.db and self.db.profile and self.db.profile.sets and self.db.profile.sets[setCode]
    if not set then
        return false
    end
    return self.HasMeaningfulWeights(set.weights)
end

function TopFit:GetSetReadinessReason(setCode)
    local set = self.db and self.db.profile and self.db.profile.sets and self.db.profile.sets[setCode]
    if not set then
        return "Select a set before calculating."
    end
    if not self.HasMeaningfulWeights(set.weights) then
        return "No usable stat weights. Add at least one non-zero weight or import a Pawn/TopFit set."
    end
    return nil
end

local function GetCheckboxLabel(checkButton)
    if not checkButton or not checkButton.GetRegions then
        return nil
    end

    local regions = { checkButton:GetRegions() }
    for _, region in ipairs(regions) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            return region
        end
    end
    return nil
end

function TopFit:RefreshWeightsPluginState(statsFrame)
    if not statsFrame or not statsFrame.uiStabilized then
        return
    end

    local setCode = self.ProgressFrame and self.ProgressFrame.selectedSet
    local set = setCode and self.db.profile.sets[setCode]
    local hasConfigured = set and self.HasConfiguredWeights(set.weights)

    if hasConfigured then
        statsFrame.emptyWeightsText:Hide()
    else
        statsFrame.emptyWeightsText:SetText(
            "No stat weights configured.\nAdd a stat or import a Pawn/TopFit set."
        )
        statsFrame.emptyWeightsText:Show()
    end
end

function TopFit:InstallStatsStabilization(statsFrame)
    if not statsFrame or statsFrame.uiStabilized then
        return
    end
    statsFrame.uiStabilized = true

    local armorLabel = GetCheckboxLabel(self.ProgressFrame and self.ProgressFrame.forceArmorTypeCheckbox)
    if armorLabel then
        armorLabel:SetText("Class armor only")
    end

    statsFrame.importWeightsButton =
        CreateFrame("Button", "TopFit_ProgressFrame_importWeightsButton", statsFrame, "UIPanelButtonTemplate")
    statsFrame.importWeightsButton:SetWidth(86)
    statsFrame.importWeightsButton:SetHeight(22)
    statsFrame.importWeightsButton:SetPoint("LEFT", statsFrame.addStatButton, "RIGHT", 6, 0)
    statsFrame.importWeightsButton:SetText("Import...")
    statsFrame.importWeightsButton:SetScript("OnClick", function()
        TopFit:ShowImportDialog()
    end)

    statsFrame.emptyWeightsText = statsFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    statsFrame.emptyWeightsText:SetPoint("TOPLEFT", statsFrame.editStatScrollFrame, "TOPLEFT", 8, -12)
    statsFrame.emptyWeightsText:SetPoint("RIGHT", statsFrame.editStatScrollFrame, "RIGHT", -26, 0)
    statsFrame.emptyWeightsText:SetHeight(40)
    statsFrame.emptyWeightsText:SetJustifyH("LEFT")
    statsFrame.emptyWeightsText:SetWordWrap(true)

    local LegacyUpdateSetStats = statsFrame.UpdateSetStats
    statsFrame.UpdateSetStats = function(frameSelf, ...)
        local result = LegacyUpdateSetStats(frameSelf, ...)
        TopFit:RefreshWeightsPluginState(frameSelf)
        TopFit:RefreshSetReadiness()
        return result
    end

    self:RefreshWeightsPluginState(statsFrame)
end

function TopFit:CreateStatsPlugin(...)
    -- plugins/stats.lua historically re-used the global frame name of the main expand/collapse
    -- button for "Add stat...". Frame names are immutable, so intercept that one construction and
    -- give it its own name before the real progress frame is ever created.
    local OriginalCreateFrame = CreateFrame
    CreateFrame = function(frameType, name, parent, template)
        if name == "TopFit_ProgressFrame_expandButton" then
            name = "TopFit_ProgressFrame_addStatButton"
        end
        return OriginalCreateFrame(frameType, name, parent, template)
    end

    local ok, errorText = pcall(LegacyCreateStatsPlugin, self, ...)
    CreateFrame = OriginalCreateFrame

    if not ok then
        error(errorText)
    end

    local pluginInfo = self.plugins and self.plugins[#self.plugins]
    if pluginInfo and pluginInfo.name == "Weights & Caps" then
        self:InstallStatsStabilization(pluginInfo.frame)
    end
end

function TopFit:RefreshSetReadiness()
    local frame = self.ProgressFrame
    if not frame or not frame.startButton then
        return
    end

    local setCode = frame.selectedSet
    local ready = setCode and self:IsSetReadyForCalculation(setCode)

    if ready and not self.isBlocked then
        frame.startButton:Enable()
    else
        frame.startButton:Disable()
    end

    if frame.setScoreFontString then
        if not ready then
            frame.setScoreFontString:SetText("|cffffcc00No weights configured|r")
            frame.readinessOverrodeScore = true
        elseif frame.readinessOverrodeScore then
            local currentText = frame.setScoreFontString.GetText and frame.setScoreFontString:GetText()
            if not currentText or string.find(currentText, "No weights configured", 1, true) then
                frame.setScoreFontString:SetText("Total Score: -")
            end
            frame.readinessOverrodeScore = nil
        end
    end

    local statsPlugin = self:GetPluginByName("Weights & Caps")
    if statsPlugin then
        self:RefreshWeightsPluginState(statsPlugin.frame)
    end

    if LegacyRefreshUpgradePlannerPlugin then
        self:RefreshUpgradePlannerPlugin()
    end
end

function TopFit:InstallProgressFrameStabilization()
    local frame = self.ProgressFrame
    if not frame or frame.uiStabilized then
        return
    end
    frame.uiStabilized = true

    local armorLabel = GetCheckboxLabel(frame.forceArmorTypeCheckbox)
    if armorLabel then
        armorLabel:SetText("Class armor only")
    end

    local LegacyStartClick = frame.startButton:GetScript("OnClick")
    frame.startButton:SetScript("OnClick", function(button, ...)
        local reason = TopFit:GetSetReadinessReason(frame.selectedSet)
        if reason then
            TopFit:Print(reason)
            return
        end
        return LegacyStartClick(button, ...)
    end)

    frame.startButton:SetScript("OnEnter", function(button)
        local reason = TopFit:GetSetReadinessReason(frame.selectedSet)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(
            reason or "Calculate the best complete configuration for this set.",
            nil,
            nil,
            nil,
            nil,
            true
        )
        GameTooltip:Show()
    end)
    frame.startButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local LegacySetSelectedSet = frame.SetSelectedSet
    frame.SetSelectedSet = function(frameSelf, ...)
        local result = LegacySetSelectedSet(frameSelf, ...)
        TopFit:RefreshSetReadiness()
        return result
    end

    local LegacySetCurrentCombination = frame.SetCurrentCombination
    frame.SetCurrentCombination = function(frameSelf, ...)
        local result = LegacySetCurrentCombination(frameSelf, ...)
        TopFit:RefreshSetReadiness()
        return result
    end

    local LegacyStoppedCalculation = frame.StoppedCalculation
    frame.StoppedCalculation = function(frameSelf, ...)
        local result = LegacyStoppedCalculation(frameSelf, ...)
        TopFit:RefreshSetReadiness()
        return result
    end
end

function TopFit:CreateProgressFrame(...)
    local result = LegacyCreateProgressFrame(self, ...)
    self:InstallProgressFrameStabilization()
    self:RefreshSetReadiness()
    return result
end

function TopFit:StartUpgradeScan(setCode, ...)
    if not self:IsSetReadyForCalculation(setCode) then
        return false, "no-weights"
    end
    return LegacyStartUpgradeScan(self, setCode, ...)
end

function TopFit:RefreshUpgradePlannerPlugin(...)
    local result
    if LegacyRefreshUpgradePlannerPlugin then
        result = LegacyRefreshUpgradePlannerPlugin(self, ...)
    end

    local pluginInfo = self:GetPluginByName("Upgrades")
    local frame = pluginInfo and pluginInfo.frame
    if not frame or not frame.initialized or self.upgradeScan then
        return result
    end

    local setCode = self.ProgressFrame and self.ProgressFrame.selectedSet
    local reason = self:GetSetReadinessReason(setCode)
    if reason then
        frame.scanButton:Disable()
        frame.statusText:SetText(reason)
    end
    return result
end
