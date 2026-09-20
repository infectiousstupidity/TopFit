TopFit = {
    plugins = {},
}
tinsert = table.insert

local function frame()
    return {
        shown = true,
        SetParent = function(self, parent)
            self.parent = parent
        end,
        SetAllPoints = function(self)
            self.allPoints = true
        end,
        Hide = function(self)
            self.shown = false
        end,
        Show = function(self)
            self.shown = true
        end,
    }
end

CreateFrame = function()
    return frame()
end

local function tabButton()
    local button = {
        text = "",
        locked = false,
    }
    button.SetPoint = function() end
    button.SetScript = function(self, event, handler)
        self[event] = handler
    end
    button.SetText = function(self, value)
        self.text = value
    end
    button.SetWidth = function() end
    button.GetFontString = function(self)
        return {
            GetStringWidth = function()
                return #self.text
            end,
        }
    end
    button.LockHighlight = function(self)
        self.locked = true
    end
    button.UnlockHighlight = function(self)
        self.locked = false
    end
    button.SetNormalFontObject = function(self, value)
        self.font = value
    end
    return button
end

GameFontHighlightSmall = "highlight"
GameFontNormalSmall = "normal"

local fired = {}
TopFit.eventHandler = {
    Fire = function(_, event, id)
        fired[#fired + 1] = event .. ":" .. tostring(id)
    end,
}

dofile("plugin.lua")

local one = TopFit:RegisterPlugin("Weights & Caps", "weights")
local two = TopFit:RegisterPlugin("Virtual Items", "virtual")
local three = TopFit:RegisterPlugin("Upgrades", "upgrades")

TopFit.ProgressFrame = {
    pluginContainer = {},
    CreateHeaderButton = function()
        return tabButton()
    end,
}

TopFit:UpdatePlugins()

assert(#fired == 3, "all plugin OnShow initializers should run eagerly")
assert(one.shown == true, "first plugin selected")
assert(two.shown == false, "second plugin hidden")
assert(three.shown == false, "third plugin hidden")
assert(TopFit.plugins[1].tabButton.locked == true, "selected tab highlight locked")
assert(TopFit.plugins[2].tabButton.locked == false, "unselected tab highlight unlocked")

assert(TopFit:SelectPluginTab(3) == true, "third tab selectable")
assert(one.shown == false, "first plugin hidden after selection")
assert(three.shown == true, "third plugin visible after selection")
assert(TopFit.plugins[3].tabButton.locked == true, "third tab remains visibly selected")
assert(fired[#fired] == "OnShow:3", "selected plugin refreshed")

print("passed plugin-manager tests")
