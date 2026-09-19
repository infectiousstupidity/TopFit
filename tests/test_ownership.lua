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
    assertEqual(first.isUnboundBoE, true, "first physical copy BoE state")
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
                        isUnboundBoE = true,
                        source = "bank",
                        bag = -1,
                        slot = 4,
                        eligibleSlots = { [11] = true, [12] = true },
                    },
                },
            },
        },
    }
    TopFit.PrimeOwnedItemCache = function()
        return true
    end

    local lists = { [11] = {}, [12] = {} }
    TopFit:AddBankSnapshotItems(lists)

    assertEqual(#lists[11], 1, "bank item added to first eligible slot")
    assertEqual(#lists[12], 1, "bank item added to second eligible slot")
    assertEqual(lists[11][1].source, "bank", "candidate source")
    assertEqual(lists[11][1].bag, -1, "candidate bank container")
    assertEqual(lists[11][1].isUnboundBoE, true, "candidate BoE state")
end

function tests.persistedItemCacheSupportsColdBankLinks()
    local itemLink = "|Hitem:123:456:1:2:3:4:0:0:0|h[Test Item]|h"
    local cached = { marker = "persisted" }

    TopFit.db = {
        global = {
            itemCache = {
                ["123:456:1:2:3:4"] = cached,
            },
        },
    }

    assertEqual(TopFit:GetItemInfoTable(itemLink), cached, "persisted item data should not require a live item lookup")
end

function tests.slotCollectorUsesWow335ReturnTableContract()
    local oldAddBankSnapshotItems = TopFit.AddBankSnapshotItems

    TopFit.slots = { Finger0Slot = 11 }
    TopFit.heirloomInfo = {
        isPlateWearer = false,
        isMailWearer = false,
        plateHeirlooms = {},
        mailHeirlooms = {},
    }
    TopFit.db = { profile = { sets = {} } }
    TopFit.setCode = nil
    TopFit.silentCalculation = true

    UnitLevel = function()
        return 80
    end
    GetInventoryItemsForSlot = function(slotID, result)
        assertEqual(slotID, 11, "requested equipment slot")
        assertEqual(type(result), "table", "3.3.5 API requires a caller-provided result table")
        result[12345] = 123
    end
    GetContainerNumSlots = function(bag)
        return bag == 0 and 1 or 0
    end
    GetContainerItemLink = function(bag, slot)
        if bag == 0 and slot == 1 then
            return "|Hitem:123:0:0:0:0:0:0:0:0|h[Test Ring]|h"
        end
        return nil
    end
    GetInventoryItemLink = function()
        return nil
    end
    TopFit.IsUnboundBoEInContainer = function()
        return true
    end
    TopFit.AddBankSnapshotItems = function() end

    local items = TopFit:GetEquippableItems(11)

    TopFit.AddBankSnapshotItems = oldAddBankSnapshotItems

    assertEqual(#items, 1, "owned bag item should be collected")
    assertEqual(items[1].source, "bags", "bag source")
    assertEqual(items[1].bag, 0, "physical bag")
    assertEqual(items[1].slot, 1, "physical bag slot")
    assertEqual(items[1].isUnboundBoE, true, "BoE state")
end

function tests.recommendationBlockersKeepRiskyItemsManual()
    local blockers = TopFit:GetRecommendationEquipBlockers({
        { locationTable = { source = "bank", itemLink = "item:1" } },
        { locationTable = { source = "bags", itemLink = "item:2", isUnboundBoE = true } },
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
