TopFit = {
    db = {
        profile = {
            sets = {
                empty = { weights = {} },
                zeros = { weights = { HIT = 0 } },
                ready = { weights = { HIT = 1 } },
                negative = { weights = { SPEED = -0.5 } },
            },
        },
    },
    plugins = {},
}

CreateFrame = function()
    return {}
end
GameTooltip = {
    SetOwner = function() end,
    SetText = function() end,
    Show = function() end,
    Hide = function() end,
}
TopFit.CreateStatsPlugin = function() end
TopFit.CreateProgressFrame = function() end
TopFit.StartUpgradeScan = function(self, setCode)
    self.legacyUpgradeSet = setCode
    return true, "legacy"
end
TopFit.RefreshUpgradePlannerPlugin = function() end
TopFit.GetPluginByName = function()
    return nil
end
TopFit.Print = function() end

dofile("ui_stabilization.lua")

assert(TopFit.HasMeaningfulWeights({}) == false, "empty weights are not meaningful")
assert(TopFit.HasMeaningfulWeights({ HIT = 0 }) == false, "zero weights are not meaningful")
assert(TopFit.HasMeaningfulWeights({ HIT = 1 }) == true, "positive weight is meaningful")
assert(TopFit.HasMeaningfulWeights({ SPEED = -0.5 }) == true, "negative weight is meaningful")
assert(TopFit.HasConfiguredWeights({ HIT = 0 }) == true, "configured zero row is still configured")

assert(TopFit:IsSetReadyForCalculation("empty") == false, "empty set not ready")
assert(TopFit:IsSetReadyForCalculation("zeros") == false, "all-zero set not ready")
assert(TopFit:IsSetReadyForCalculation("ready") == true, "non-zero set ready")
assert(TopFit:GetSetReadinessReason("missing") ~= nil, "missing set has reason")
assert(TopFit:GetSetReadinessReason("ready") == nil, "ready set has no error")

local ok, reason = TopFit:StartUpgradeScan("empty")
assert(ok == false and reason == "no-weights", "upgrade scan blocked without weights")

ok, reason = TopFit:StartUpgradeScan("ready")
assert(ok == true and reason == "legacy", "ready upgrade scan reaches legacy planner")
assert(TopFit.legacyUpgradeSet == "ready", "legacy planner receives selected set")

local startButton = {
    enabled = nil,
    Enable = function(self)
        self.enabled = true
    end,
    Disable = function(self)
        self.enabled = false
    end,
}
local score = {
    text = nil,
    SetText = function(self, value)
        self.text = value
    end,
    GetText = function(self)
        return self.text
    end,
}
TopFit.ProgressFrame = {
    selectedSet = "empty",
    startButton = startButton,
    setScoreFontString = score,
}
TopFit:RefreshSetReadiness()
assert(startButton.enabled == false, "Start disabled for empty weights")
assert(string.find(score.text, "No weights configured", 1, true) ~= nil, "score area explains empty state")

TopFit.ProgressFrame.selectedSet = "ready"
TopFit:RefreshSetReadiness()
assert(startButton.enabled == true, "Start enabled for usable weights")
assert(score.text == "Total Score: -", "stale zero score removed after weights become usable")

print("passed UI-stabilization tests")
