TopFit = {}
tinsert = table.insert

dofile("ownership.lua")

local tests = {}

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function tests.bankSnapshotMergesEligibleSlotsPerPhysicalCopy()
    local items = {}

    TopFit:MergeBankSnapshotEntry(items, "item:1", -1, 4, true, 11)
    TopFit:MergeBankSnapshotEntry(items, "item:1", -1, 4, true, 12)
    TopFit:MergeBankSnapshotEntry(items, "item:1", -1, 5, true, 11)

    local first = items["bank:-1:4"]
    local second = items["bank:-1:5"]

    assertEqual(first.itemLink, "item:1", "first physical copy link")
    assertEqual(first.isBoE, true, "first physical copy BoE state")
    assertEqual(first.eligibleSlots[11], true, "first copy ring slot one")
    assertEqual(first.eligibleSlots[12], true, "first copy ring slot two")
    assertEqual(second.slot, 5, "second physical copy remains distinct")
end

function tests.bankSnapshotAddsOwnedCandidates()
    TopFit.db = {
        char = {
            bankSnapshot = {
                scanned = true,
                items = {
                    ["bank:-1:4"] = {
                        itemLink = "item:1",
                        isBoE = true,
                        source = "bank",
                        bag = -1,
                        slot = 4,
                        eligibleSlots = { [11] = true, [12] = true },
                    },
                },
            },
        },
    }
    TopFit.UpdateCache = function() end

    local lists = { [11] = {}, [12] = {} }
    TopFit:AddBankSnapshotItems(lists)

    assertEqual(#lists[11], 1, "bank item added to first eligible slot")
    assertEqual(#lists[12], 1, "bank item added to second eligible slot")
    assertEqual(lists[11][1].source, "bank", "candidate source")
    assertEqual(lists[11][1].bag, -1, "candidate bank container")
    assertEqual(lists[11][1].isBoE, true, "candidate BoE state")
end

function tests.recommendationBlockersKeepRiskyItemsManual()
    local blockers = TopFit:GetRecommendationEquipBlockers({
        { locationTable = { source = "bank", itemLink = "item:1" } },
        { locationTable = { source = "bags", itemLink = "item:2", isBoE = true } },
        { locationTable = { source = "virtual", itemLink = "item:3", isVirtual = true } },
        { locationTable = { source = "equipped", itemLink = "item:4" } },
    })

    assertEqual(blockers.bank, 1, "bank blockers")
    assertEqual(blockers.unboundBoE, 1, "BoE blockers")
    assertEqual(blockers.virtual, 1, "virtual blockers")
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

print(("passed %d ownership tests"):format(#names))
