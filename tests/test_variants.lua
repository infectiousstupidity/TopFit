TopFit = {}
tinsert = table.insert

TopFit.chromiecraftPhase = 3

dofile("data/gems.lua")
dofile("data/enchants.lua")
dofile("data/socket_bonuses.lua")
dofile("candidates.lua")
dofile("variants.lua")

local tests = {}

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertTrue(value, message)
    assertEqual(value, true, message)
end

local function findGem(itemID)
    for _, gem in ipairs(TopFit.gemCandidates) do
        if gem.itemID == itemID then
            return gem
        end
    end
    error("missing gem " .. tostring(itemID))
end

function tests.variantLinkReplacesEnchantAndGemFields()
    local base = "|cffa335ee|Hitem:45610:111:1:2:3:4:0:0:80:0|h[Test]|h|r"
    local result = TopFit.BuildVariantItemLink(base, 222, { 10, 20, 30, 40 })

    assertTrue(string.find(result, "item:45610:222:10:20:30:40:0:0:80:0", 1, true) ~= nil, "variant item string")
end

function tests.modificationIdsRoundTrip()
    local link = "item:45610:222:10:20:30:40:0:0:80:0"
    local enchantID, gems = TopFit.GetItemModificationIDs(link)

    assertEqual(enchantID, 222, "enchant ID")
    assertEqual(gems[1], 10, "gem one")
    assertEqual(gems[4], 40, "gem four")
end

function tests.baseVariantStatsRemoveCurrentGemsAndEnchant()
    local item = {
        totalBonus = { STR = 30, HIT = 12, PROC = 5 },
        gemBonus = { STR = 10 },
        enchantBonus = { HIT = 12 },
    }

    local stats = TopFit.GetBaseVariantStats(item)

    assertEqual(stats.STR, 20, "base strength")
    assertEqual(stats.HIT, nil, "enchant removed")
    assertEqual(stats.PROC, 5, "non-modification effect preserved")
end

function tests.phaseThreeStrengthVariantGetsRealSocketBonus()
    local baseLink = "item:999001:0:0:0:0:0:0:0:80:0"
    local item = {
        itemLink = baseLink,
        itemID = 999001,
        itemLevel = 226,
        itemMinLevel = 80,
        itemEquipLoc = "INVTYPE_NECK",
        itemSubType = "Miscellaneous",
        itemBonus = { ITEM_MOD_STRENGTH_SHORT = 10 },
        gemBonus = {},
        enchantBonus = {},
        totalBonus = { ITEM_MOD_STRENGTH_SHORT = 10 },
        baseSocketColors = { "RED" },
        socketBonusID = 3312,
        emptySocketColors = { "RED" },
    }

    TopFit.db = {
        profile = {
            sets = {
                test = {
                    weights = { ITEM_MOD_STRENGTH_SHORT = 1 },
                    caps = {},
                },
            },
        },
    }
    TopFit.GetCachedItem = function(_, link)
        if link == baseLink then
            return item
        end
    end

    local variants = TopFit:BuildItemVariants(baseLink, 2, "test")
    local bestStrength = 0
    local foundBonus = false
    for _, variant in ipairs(variants) do
        bestStrength = math.max(bestStrength, variant.itemTable.totalBonus.ITEM_MOD_STRENGTH_SHORT or 0)
        if variant.socketBonusActive and variant.itemTable.gemBonus.ITEM_MOD_STRENGTH_SHORT == 28 then
            foundBonus = true
        end
    end

    assertEqual(bestStrength, 38, "base + Bold Stormjewel + socket bonus")
    assertTrue(foundBonus, "matching socket bonus was scored")
end

function tests.capRelevantOffColorGemSurvivesCandidateSelection()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    local selected = TopFit:SelectGemCandidatesForVariant(
        "RED",
        context,
        { ITEM_MOD_STRENGTH_SHORT = 1 },
        { ITEM_MOD_HIT_RATING_SHORT = { { active = true, value = 200 } } },
        nil
    )

    local foundHit = false
    for _, gem in ipairs(selected) do
        if (gem.stats.ITEM_MOD_HIT_RATING_SHORT or 0) >= 16 then
            foundHit = true
            assertTrue(TopFit:GemFitsSocket(gem, "RED"), "off-color hit gem physically fits red socket")
        end
    end
    assertTrue(foundHit, "cap-relevant hit gem retained")
end

function tests.hybridColorClassSurvivesFrontier()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    local selected = TopFit:SelectGemCandidatesForVariant("RED", context, { ITEM_MOD_STRENGTH_SHORT = 1 }, {}, nil)

    local foundPurple = false
    for _, candidate in ipairs(selected) do
        if TopFit.GemContributesColor(candidate, "RED") and TopFit.GemContributesColor(candidate, "BLUE") then
            foundPurple = true
            break
        end
    end
    assertTrue(foundPurple, "red+blue hybrid retained for global meta activation")
end

function tests.currentUnknownEnchantCanBePreservedWhileRegemming()
    local baseLink = "item:999002:9999:39996:0:0:0:0:0:80:0"
    local item = {
        itemLink = baseLink,
        itemID = 999002,
        itemLevel = 226,
        itemMinLevel = 80,
        itemEquipLoc = "INVTYPE_NECK",
        itemSubType = "Miscellaneous",
        itemBonus = { ITEM_MOD_STRENGTH_SHORT = 10 },
        gemBonus = { ITEM_MOD_STRENGTH_SHORT = 16 },
        enchantBonus = { ITEM_MOD_HIT_RATING_SHORT = 7 },
        totalBonus = {
            ITEM_MOD_STRENGTH_SHORT = 26,
            ITEM_MOD_HIT_RATING_SHORT = 7,
        },
        baseSocketColors = { "RED" },
        socketBonusID = 0,
        emptySocketColors = {},
    }

    TopFit.db = {
        profile = {
            sets = {
                test = {
                    weights = {
                        ITEM_MOD_STRENGTH_SHORT = 1,
                        ITEM_MOD_HIT_RATING_SHORT = 1,
                    },
                    caps = {},
                },
            },
        },
    }
    TopFit.GetCachedItem = function(_, link)
        if link == baseLink then
            return item
        end
    end

    local variants = TopFit:BuildItemVariants(baseLink, 2, "test")
    local found = false
    for _, variant in ipairs(variants) do
        local enchantID = TopFit.GetItemModificationIDs(variant.itemLink)
        if enchantID == 9999 and variant.requiresModification then
            assertEqual(variant.itemTable.enchantBonus.ITEM_MOD_HIT_RATING_SHORT, 7, "current enchant stats preserved")
            found = true
            break
        end
    end
    assertTrue(found, "regem variant preserves unknown current enchant")
end

function tests.currentGemIsRetainedEvenWhenNotTopWeighted()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    local current = findGem(40008)
    local selected = TopFit:SelectGemCandidatesForVariant(
        "BLUE",
        context,
        { ITEM_MOD_STRENGTH_SHORT = 1 },
        {},
        current.itemID
    )

    local found = false
    for _, gem in ipairs(selected) do
        if gem.itemID == current.itemID then
            found = true
        end
    end
    assertTrue(found, "current gem retained")
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

print(("passed %d variant tests"):format(#names))
