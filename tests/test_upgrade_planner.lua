TopFit = {}
tinsert = table.insert
tremove = table.remove

TopFit.GetEquippableItems = function(_, requestedSlotID)
    local data = {
        [1] = {
            { itemLink = "owned", source = "equipped", slot = 1 },
            { itemLink = "configured-virtual", source = "virtual", isVirtual = true },
        },
        [2] = {},
    }
    return requestedSlotID and data[requestedSlotID] or data
end
TopFit.EquipRecommendedItems = function()
    return "legacy-equip"
end
TopFit.AbortCalculations = function()
    return "legacy-abort"
end

TopFit.upgradeSourceInstances = {
    [20] = {
        name = "Ulduar",
        minChromiePhase = 3,
        encounters = { [1] = "Flame Leviathan" },
    },
}
TopFit.upgradeSourceData = {
    [100] = { { 20, 1, 3 } },
}

dofile("upgrade_planner.lua")

local tests = {}

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertTrue(value, message)
    assertEqual(value, true, message)
end

local function assertFalse(value, message)
    assertEqual(value, false, message)
end

function tests.sourceDecodingIncludesEncounterAndDifficulty()
    TopFit.chromiecraftPhase = 3
    local sources = TopFit:GetUpgradeSources(100)

    assertEqual(#sources, 1, "one source")
    assertEqual(sources[1].zone, "Ulduar", "zone")
    assertEqual(sources[1].encounter, "Flame Leviathan", "encounter")
    assertEqual(sources[1].difficulty, "10/25-player", "difficulty")
    assertEqual(TopFit.GetUpgradeSourceText(sources), "Ulduar - Flame Leviathan (10/25-player)", "source text")
end

function tests.futurePhaseSourceIsHidden()
    TopFit.upgradeSourceInstances[20].minChromiePhase = 4
    TopFit.chromiecraftPhase = 3
    assertEqual(#TopFit:GetUpgradeSources(100), 0, "future source hidden")
    TopFit.upgradeSourceInstances[20].minChromiePhase = 3
end

function tests.scanSuppressesConfiguredVirtualsAndInjectsOneProspectiveCopy()
    TopFit.upgradeScan = {
        activeCandidate = {
            itemID = 200,
            itemLink = "prospective",
            eligibleSlots = { 1, 2 },
            sources = {},
        },
    }

    local items = TopFit:GetEquippableItems()
    assertEqual(#items[1], 2, "owned plus prospective in slot one")
    assertEqual(items[1][1].source, "equipped", "owned item retained")
    assertEqual(items[1][2].source, "upgrade", "prospective source")
    assertEqual(items[1][2].upgradeCandidateID, 200, "candidate identity")
    assertTrue(items[1][2].isVirtual, "prospective item remains recommendation-only")
    assertEqual(#items[2], 1, "same prospective physical item can be considered in eligible slot")

    TopFit.upgradeScan = nil
end

function tests.requestedSlotInjectionKeepsRequestedShape()
    TopFit.upgradeScan = {
        activeCandidate = {
            itemID = 201,
            itemLink = "prospective",
            eligibleSlots = { 1, 2 },
            sources = {},
        },
    }

    local items = TopFit:GetEquippableItems(2)
    assertEqual(#items, 1, "single-slot list returned")
    assertEqual(items[1].upgradeCandidateID, 201, "candidate injected into requested slot")

    TopFit.upgradeScan = nil
end

function tests.combinationMustActuallyUseCandidate()
    local combo = {
        items = {
            [1] = { upgradeCandidateID = 300 },
        },
    }

    assertTrue(TopFit.CombinationUsesUpgradeCandidate(combo, 300), "selected candidate found")
    assertFalse(TopFit.CombinationUsesUpgradeCandidate(combo, 301), "unselected candidate absent")
end

function tests.resultRequiresPositiveWholeSetGain()
    TopFit.upgradeResultLimit = 20
    TopFit.upgradeResultsBySet = {}
    TopFit.setCode = "set_1"

    local candidate = { itemID = 400, itemLink = "item400", sources = {}, sourceText = "Ulduar" }
    local used = {
        totalScore = 110,
        items = { [1] = { upgradeCandidateID = 400 } },
    }
    local unused = {
        totalScore = 120,
        items = { [1] = { upgradeCandidateID = 999 } },
    }

    assertTrue(TopFit:RecordUpgradeResult(candidate, used, 100) ~= nil, "positive used candidate recorded")
    assertEqual(TopFit:GetUpgradeResults("set_1")[1].gain, 10, "whole-set gain")
    assertEqual(TopFit:RecordUpgradeResult(candidate, unused, 100), nil, "unused candidate ignored")
    assertEqual(TopFit:RecordUpgradeResult(candidate, used, 120), nil, "non-positive gain ignored")
end

function tests.queueKeepsWeightedAndCapSpecialists()
    TopFit.upgradeWeightedCandidatesPerSlot = 1
    TopFit.upgradeCapCandidatesPerSlot = 1
    TopFit.upgradeCandidateLimit = 10
    TopFit.Utopia = {
        HIT = { { active = true, value = 100 } },
    }
    TopFit.setCode = "set_1"

    local candidates = {
        {
            itemID = 1,
            eligibleSlots = { 1 },
            quickScore = 100,
            quickBySlot = { [1] = { score = 100, capValues = { HIT = 1 } } },
        },
        {
            itemID = 2,
            eligibleSlots = { 1 },
            quickScore = 90,
            quickBySlot = { [1] = { score = 90, capValues = { HIT = 50 } } },
        },
    }

    local oldScore = TopFit.ScoreUpgradeCandidate
    TopFit.ScoreUpgradeCandidate = function(_, candidate)
        return candidate
    end
    local queue = TopFit:SelectUpgradeCandidateQueue(candidates)
    TopFit.ScoreUpgradeCandidate = oldScore

    assertEqual(#queue, 2, "weighted winner and cap specialist retained")
    local ids = { [queue[1].itemID] = true, [queue[2].itemID] = true }
    assertTrue(ids[1], "weighted winner")
    assertTrue(ids[2], "cap specialist")
end

local names = {}
for name in pairs(tests) do
    table.insert(names, name)
end
table.sort(names)

for _, name in ipairs(names) do
    tests[name]()
    print("ok - " .. name)
end

print(("passed %d upgrade-planner tests"):format(#names))
