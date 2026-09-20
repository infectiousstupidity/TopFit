local function SetPluginSelected(pluginInfo, selected)
    if not pluginInfo.tabButton then
        return
    end

    if selected then
        pluginInfo.tabButton:LockHighlight()
        pluginInfo.tabButton:SetNormalFontObject(GameFontHighlightSmall)
    else
        pluginInfo.tabButton:UnlockHighlight()
        pluginInfo.tabButton:SetNormalFontObject(GameFontNormalSmall)
    end
end

function TopFit:RegisterPlugin(pluginName, tooltipText)
    local pluginInfo = {
        name = pluginName,
        tooltipText = tooltipText,
    }

    tinsert(self.plugins, pluginInfo)
    pluginInfo.id = #self.plugins
    pluginInfo.frame = CreateFrame("Frame", "TopFit_ProgressFrame_PluginFrame_" .. pluginInfo.id, nil)

    if pluginInfo.id > 1 then
        pluginInfo.frame:Hide()
    end

    self:UpdatePlugins()
    return pluginInfo.frame, pluginInfo.id, pluginInfo
end

function TopFit:GetPluginByName(pluginName)
    for _, pluginInfo in ipairs(self.plugins or {}) do
        if pluginInfo.name == pluginName then
            return pluginInfo
        end
    end
    return nil
end

function TopFit:UpdatePlugins()
    if not self.ProgressFrame then
        return
    end

    for index, pluginInfo in ipairs(self.plugins) do
        pluginInfo.frame:SetParent(self.ProgressFrame.pluginContainer)
        pluginInfo.frame:SetAllPoints()

        if not pluginInfo.tabButton then
            pluginInfo.tabButton = self.ProgressFrame:CreateHeaderButton(
                self.ProgressFrame.pluginContainer,
                "TopFit_ProgressFrame_PluginButton_" .. pluginInfo.id
            )
            pluginInfo.tabButton:SetPoint("BOTTOM", self.ProgressFrame, "TOP", 0, -7)
            if index == 1 then
                pluginInfo.tabButton:SetPoint("LEFT", self.ProgressFrame.pluginContainer, "LEFT")
            else
                pluginInfo.tabButton:SetPoint("LEFT", self.plugins[index - 1].tabButton, "RIGHT", 3, 0)
            end

            pluginInfo.tabButton:SetScript("OnClick", function()
                TopFit:SelectPluginTab(pluginInfo.id)
            end)
        end

        pluginInfo.tabButton:SetText(pluginInfo.name)
        pluginInfo.tabButton:SetWidth(pluginInfo.tabButton:GetFontString():GetStringWidth() + 10)
        pluginInfo.tabButton.tipText = pluginInfo.tooltipText

        -- Build/refresh every plugin once the real container exists. Legacy Virtual Items and the
        -- upgrade planner use OnShow as their initializer; eagerly firing it here prevents a tab
        -- from becoming a visible but empty frame if its first-click callback is missed or errors.
        if self.eventHandler then
            self.eventHandler:Fire("OnShow", pluginInfo.id)
        end
    end

    local selectedID = self.selectedPluginID
    if not selectedID or not self.plugins[selectedID] then
        selectedID = 1
    end
    self.selectedPluginID = selectedID

    for index, pluginInfo in ipairs(self.plugins) do
        local selected = index == selectedID
        if selected then
            pluginInfo.frame:Show()
        else
            pluginInfo.frame:Hide()
        end
        SetPluginSelected(pluginInfo, selected)
    end
end

function TopFit:SelectPluginTab(id)
    if not self.plugins or not self.plugins[id] then
        return false
    end

    self.selectedPluginID = id
    for index, pluginInfo in ipairs(self.plugins) do
        local selected = index == id
        if selected then
            pluginInfo.frame:Show()
        else
            pluginInfo.frame:Hide()
        end
        SetPluginSelected(pluginInfo, selected)
    end

    if self.eventHandler then
        self.eventHandler:Fire("OnShow", id)
    end
    return true
end
