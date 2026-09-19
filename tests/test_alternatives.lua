TopFit = {}
tinsert = table.insert

TopFit.SaveCurrentCombination = function(self)
    if self.nextCandidate then
        self.bestCombination = self.nextCandidate
        self.maxScore = self.nextCandidate.totalScore
        self.debugSlotCounters = { [1] = self.nextDebugCounter or 1 }
    else
        self.bestCombination = nil
        self.maxScore = nil
    end
end

TopFit.CalculateRecommendations = function(self)
    self.calculateCalls = (self.calculateCalls or 0) + 1
end

local itemIDs = {}
TopFit.GetCachedItem = function(_, link)
    local itemID = itemIDs[link]
    return itemID and { itemID = itemID } or nil
end

dofile("alternatives.lua")

local tests = {}

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertTrue(value, message)
    assertEqual(value, true, message)
end

local function location(link, slot, extra)
    local value = {
        itemLink = link,
        physicalItemLink = link .. "-physical",
        source = "equipped",
        slot = slot,
    }
    for key, fieldValue in pairs(extra or {}) do
        value[key] = fieldValue
    end
    itemIDs[link] = itemIDs[link] or tonumber(string.match(link, "%d+")) or 1
    itemIDs[value.physicalItemLink] = itemIDs[link]
    return value
end

local function combination(score, items)
    return {
        totalScore = score,
        totalStats = {},
        items = items,
    }
end

local function reset()
    TopFit.setCode = "set_1"
    TopFit.bestCombination = nil
    TopFit.maxScore = nil
    TopFit.debugSlotCounters = {}
    TopFit.topCombinationsBySet = {}
    TopFit.selectedAlternativeBySet = {}
    TopFit.nextCandidate = nil
end

function tests.lowerCandidateIsCapturedWithoutReplacingLegacyBest()
    reset()

    local best = combination(100, { [1] = location("item100", 1) })
    TopFit.bestCombination = best
    TopFit.maxScore = 100
    TopFit.debugSlotCounters = { [1] = 7 }

    TopFit.nextCandidate = combination(90, { [1] = location("item90", 1) })
    TopFit:SaveCurrentCombination()

    assertEqual(TopFit.bestCombination, best, "legacy maximum is preserved")
    assertEqual(TopFit.maxScore, 100, "legacy maximum score is preserved")
    assertEqual(TopFit.debugSlotCounters[1], 7, "debug counters restored with old best")
    assertEqual(#TopFit:GetAlternativeEntries("set_1"), 1, "lower candidate still captured")
    assertEqual(TopFit:GetAlternativeEntries("set_1")[1].score, 90, "captured score")
end

function tests.higherCandidateBecomesLegacyBestAndRanksFirst()
    reset()

    TopFit.bestCombination = combination(80, { [1] = location("item80", 1) })
    TopFit.maxScore = 80
    TopFit.nextCandidate = combination(120, { [1] = location("item120", 1) })
    TopFit.nextDebugCounter = 9

    TopFit:SaveCurrentCombination()

    assertEqual(TopFit.maxScore, 120, "new maximum score")
    assertEqual(TopFit.bestCombination.totalScore, 120, "new maximum combination")
    assertEqual(TopFit.debugSlotCounters[1], 9, "new best debug counters retained")
    assertEqual(TopFit:GetAlternativeEntries("set_1")[1].score, 120, "top result ranks first")
end

function tests.ringAndTrinketSwapsDeduplicate()
    reset()

    local a = combination(100, {
        [11] = location("item101", 11),
        [12] = location("item102", 12),
        [13] = location("item201", 13),
        [14] = location("item202", 14),
    })
    local b = combination(100, {
        [11] = location("item102", 11),
        [12] = location("item101", 12),
        [13] = location("item202", 13),
        [14] = location("item201", 14),
    })

    TopFit:ConsiderAlternativeCombination(a)
    TopFit:ConsiderAlternativeCombination(b)

    assertEqual(#TopFit:GetAlternativeEntries("set_1"), 1, "symmetric slot swaps are one outcome")
end

function tests.frontierKeepsAtMostTwoVariantsOfSamePhysicalGear()
    reset()

    itemIDs["gear-physical"] = 500
    for index, score in ipairs({ 100, 99, 98 }) do
        local loc = location("variant" .. index, 1)
        loc.physicalItemLink = "gear-physical"
        TopFit:ConsiderAlternativeCombination(combination(score, { [1] = loc }))
    end

    local different = location("item600", 2)
    TopFit:ConsiderAlternativeCombination(combination(97, { [2] = different }))

    local entries = TopFit:GetAlternativeEntries("set_1")
    assertEqual(#entries, 3, "two variants plus one different gear set remain")
    assertEqual(entries[1].score, 100, "best variant kept")
    assertEqual(entries[2].score, 99, "second useful variant kept")
    assertEqual(entries[3].score, 97, "different physical gear survives")
end

function tests.frontierIsBoundedAndScoreSorted()
    reset()

    for score = 1, 8 do
        local link = "item" .. tostring(700 + score)
        TopFit:ConsiderAlternativeCombination(combination(score, { [score] = location(link, score) }))
    end

    local entries = TopFit:GetAlternativeEntries("set_1")
    assertEqual(#entries, TopFit.alternativeResultLimit, "frontier limit")
    assertEqual(entries[1].score, 8, "highest score first")
    assertEqual(entries[#entries].score, 4, "lowest retained score")
end

function tests.changeSummarySeparatesGearAndModificationWork()
    reset()

    local combo = combination(100, {
        [1] = location("item1", 1),
        [2] = location("item2", 4, { source = "bags", requiresModification = true }),
        [3] = location("item3", 3, { source = "bank" }),
        [4] = location("item4", 4, { isUnboundBoE = true }),
        [5] = location("item5", 5, { source = "virtual", isVirtual = true }),
    })

    local summary = TopFit.GetCombinationChangeSummary(combo)
    assertEqual(summary.gearChanges, 3, "bag, bank, and virtual items change gear")
    assertEqual(summary.modifications, 1, "one gem/enchant modification")
    assertEqual(summary.banked, 1, "one banked item")
    assertEqual(summary.unboundBoE, 1, "one BoE item")
    assertEqual(summary.virtual, 1, "one virtual item")
    assertEqual(summary.totalChanges, 4, "gear plus modification count")
end

function tests.calculateRecommendationsResetsPriorResults()
    reset()

    TopFit:ConsiderAlternativeCombination(combination(100, { [1] = location("item900", 1) }))
    assertTrue(#TopFit:GetAlternativeEntries("set_1") > 0, "precondition")

    TopFit:CalculateRecommendations()

    assertEqual(#TopFit:GetAlternativeEntries("set_1"), 0, "new calculation starts with empty frontier")
    assertEqual(TopFit.calculateCalls, 1, "legacy calculation still called")
end

function tests.recommendationsCanBeBuiltFromSelectedCombination()
    reset()

    local combo = combination(100, {
        [1] = location("item1001", 1),
        [2] = location("item1002", 2),
    })

    TopFit:SetRecommendationsFromCombination(combo)

    assertEqual(TopFit.itemRecommendations[1].locationTable.itemLink, "item1001", "slot one recommendation")
    assertEqual(TopFit.itemRecommendations[2].locationTable.itemLink, "item1002", "slot two recommendation")
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

print(("passed %d alternative-result tests"):format(#names))
