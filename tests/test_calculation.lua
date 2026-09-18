TopFit = {}
tinsert = table.insert
tremove = table.remove

dofile("chromiecraft.lua")
dofile("calculation.lua")

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

function tests.hardCapDetection()
    assertFalse(TopFit:HasActiveHardCap(nil), "missing cap list")
    assertFalse(TopFit:HasActiveHardCap({ { active = false, soft = false } }), "inactive hard cap")
    assertFalse(TopFit:HasActiveHardCap({ { active = true, soft = true } }), "active soft cap")
    assertTrue(
        TopFit:HasActiveHardCap({
            { active = true, soft = true },
            { active = true, soft = false },
        }),
        "active hard cap"
    )
end

function tests.activeCapDetection()
    assertFalse(TopFit:IsStatCapped(nil), "missing cap list")
    assertFalse(TopFit:IsStatCapped({ { active = false, soft = false } }), "inactive cap")
    assertTrue(TopFit:IsStatCapped({ { active = true, soft = true } }), "active cap")
end

function tests.multipleCapsMustAllBeReached()
    local items = {
        first = { totalBonus = { HIT = 5 } },
        second = { totalBonus = { HIT = 3 } },
    }

    TopFit.Utopia = {
        HIT = {
            { active = true, soft = false, value = 5 },
            { active = true, soft = true, value = 8 },
        },
    }
    TopFit.talentBonusStats = {}
    TopFit.itemListBySlot = {
        [1] = { { itemLink = "first" } },
        [2] = { { itemLink = "second" } },
    }
    TopFit.slotCounters = { [1] = 1, [2] = 1 }
    TopFit.GetCachedItem = function(_, itemLink)
        return items[itemLink]
    end

    assertFalse(TopFit:IsCapsReached(1), "second active cap should still be unmet")
    assertTrue(TopFit:IsCapsReached(2), "both active caps should be met")
end

function tests.unreachableCapUsesRemainingSlotMaximums()
    local items = {
        first = { totalBonus = { HIT = 4 } },
    }

    TopFit.Utopia = {
        HIT = {
            { active = true, soft = false, value = 8 },
        },
    }
    TopFit.talentBonusStats = {}
    TopFit.itemListBySlot = {
        [1] = { { itemLink = "first" } },
    }
    TopFit.slotCounters = { [1] = 1 }
    TopFit.capHeuristics = { HIT = { [2] = 3 } }
    TopFit.GetCachedItem = function(_, itemLink)
        return items[itemLink]
    end

    assertTrue(TopFit:IsCapsUnreachable(1), "4 current + 3 remaining cannot reach 8")

    TopFit.capHeuristics.HIT[2] = 4
    assertFalse(TopFit:IsCapsUnreachable(1), "4 current + 4 remaining can reach 8")
end

function tests.duplicateDetectionTracksPhysicalLocation()
    TopFit.itemListBySlot = {
        [1] = { { itemLink = "item:1", bag = 0, slot = 1 } },
        [2] = { { itemLink = "item:1", bag = 0, slot = 1 } },
    }
    TopFit.slotCounters = { [1] = 1, [2] = 1 }

    assertTrue(TopFit:IsDuplicateItem(2), "same bag slot cannot fill two equipment slots")

    TopFit.itemListBySlot[2][1].slot = 2
    assertFalse(TopFit:IsDuplicateItem(2), "two physical copies of the same item are distinct")
end

function tests.classArmorTypeUsesClassToken()
    UnitClass = function()
        return "Warrior", "WARRIOR"
    end
    assertEqual(TopFit:GetClassArmorType(), "Plate", "warrior armor type")

    UnitClass = function()
        return "Mage", "MAGE"
    end
    assertEqual(TopFit:GetClassArmorType(), "Cloth", "mage armor type")
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

print(("passed %d calculation tests"):format(#names))
