TopFit = {}
tinsert = table.insert
tremove = table.remove

TopFit.SaveCurrentCombination = function(self)
    self.bestCombination = self.nextCombination
    self.maxScore = self.nextCombination and self.nextCombination.totalScore or nil
end
TopFit.EquipRecommendedItems = function()
    return "legacy-equip"
end
TopFit.CalculateBestInSlot = function()
    return nil
end

dofile("data/gems.lua")
dofile("candidates.lua")
dofile("variant_optimizer.lua")

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

local function gem(itemID)
    for _, candidate in ipairs(TopFit.gemCandidates) do
        if candidate.itemID == itemID then
            return candidate
        end
    end
    error("missing gem " .. tostring(itemID))
end

function tests.duplicateDetectionUsesPhysicalItemNotVariantLink()
    TopFit.itemListBySlot = {
        [11] = { { itemLink = "variant-a", physicalKey = "bags:0:1" } },
        [12] = { { itemLink = "variant-b", physicalKey = "bags:0:1" } },
    }
    TopFit.slotCounters = { [11] = 1, [12] = 1 }

    assertTrue(TopFit:IsDuplicateItem(12), "same ring copy cannot be used twice")
end

function tests.twoPhysicalCopiesRemainDistinct()
    TopFit.itemListBySlot = {
        [11] = { { itemLink = "variant-a", physicalKey = "bags:0:1" } },
        [12] = { { itemLink = "variant-b", physicalKey = "bags:0:2" } },
    }
    TopFit.slotCounters = { [11] = 1, [12] = 1 }

    assertFalse(TopFit:IsDuplicateItem(12), "separate physical copies are usable")
end

function tests.globalMetaActivationIsCheckedAcrossItems()
    local chaotic = gem(41285)
    local combination = {
        items = {
            [1] = {
                variant = {
                    gemColorCounts = { RED = 0, YELLOW = 0, BLUE = 0 },
                    uniqueGemCounts = {},
                    metaGems = { chaotic },
                },
            },
        },
    }

    local valid, reason = TopFit:IsVariantCombinationValid(combination)
    assertFalse(valid, "inactive meta rejected")
    assertEqual(reason, "meta-inactive", "meta failure reason")

    combination.items[2] = {
        variant = {
            gemColorCounts = { RED = 0, YELLOW = 0, BLUE = 2 },
            uniqueGemCounts = {},
            metaGems = {},
        },
    }
    assertTrue(TopFit:IsVariantCombinationValid(combination), "two blue contributions activate Chaotic")
end

function tests.jewelcrafterLimitIsGlobal()
    local combination = {
        items = {
            [1] = { variant = { gemColorCounts = {}, uniqueGemCounts = { JEWELERS_GEMS = 2 }, metaGems = {} } },
            [2] = { variant = { gemColorCounts = {}, uniqueGemCounts = { JEWELERS_GEMS = 2 }, metaGems = {} } },
        },
    }

    local valid, reason = TopFit:IsVariantCombinationValid(combination)
    assertFalse(valid, "four Jeweler's Gems rejected")
    assertEqual(reason, "unique-limit", "unique failure reason")
end

function tests.invalidNewBestIsRolledBack()
    local chaotic = gem(41285)
    local previous = { items = {}, totalScore = 10 }
    TopFit.bestCombination = previous
    TopFit.maxScore = 10
    TopFit.nextCombination = {
        totalScore = 20,
        items = {
            [1] = {
                variant = {
                    gemColorCounts = { RED = 0, YELLOW = 0, BLUE = 0 },
                    uniqueGemCounts = {},
                    metaGems = { chaotic },
                },
            },
        },
    }

    TopFit:SaveCurrentCombination()

    assertEqual(TopFit.bestCombination, previous, "invalid best combination rolled back")
    assertEqual(TopFit.maxScore, 10, "previous score restored")
end

function tests.bestInSlotDoesNotReuseChosenPhysicalCopy()
    local itemTables = {
        a = { itemMinLevel = 80 },
        b = { itemMinLevel = 80 },
    }
    TopFit.characterLevel = 80
    TopFit.ignoreCapsForCalculation = false
    TopFit.itemListBySlot = {
        [11] = {
            { itemLink = "a", physicalKey = "bags:0:1" },
            { itemLink = "b", physicalKey = "bags:0:2" },
        },
    }
    TopFit.GetCachedItem = function(_, link)
        return itemTables[link]
    end
    TopFit.GetItemScore = function(_, link)
        return link == "a" and 20 or 10
    end

    local chosen = { { itemLink = "other-variant", physicalKey = "bags:0:1" } }
    local best = TopFit:CalculateBestInSlot(chosen, false, 11, "test")

    assertEqual(best.itemLink, "b", "next physical copy chosen")
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

print(("passed %d variant-optimizer tests"):format(#names))
