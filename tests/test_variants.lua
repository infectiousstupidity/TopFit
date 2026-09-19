TopFit = {}
tinsert = table.insert

dofile("data/gems.lua")
dofile("data/enchants.lua")
dofile("data/socket_modifications.lua")
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

local function enchant(enchantID)
    for _, candidate in ipairs(TopFit.enchantCandidates) do
        if candidate.enchantID == enchantID then
            return candidate
        end
    end
    error("missing enchant " .. tostring(enchantID))
end

local function modification(modificationID)
    for _, candidate in ipairs(TopFit.socketModificationCandidates) do
        if candidate.modificationID == modificationID then
            return candidate
        end
    end
    error("missing modification " .. tostring(modificationID))
end

local function glove()
    return {
        itemID = 45928,
        itemLevel = 226,
        itemEquipLoc = "INVTYPE_HAND",
        baseSocketColors = { "BLUE", "RED" },
        socketBonusID = 3316,
        itemBonus = { ITEM_MOD_STRENGTH_SHORT = 10 },
    }
end

function tests.socketBonusDataUsesFixed335Stats()
    assertEqual(TopFit.GetSocketBonusData(3316).stats.ITEM_MOD_CRIT_RATING_SHORT, 6, "Ulduar socket bonus")
    assertEqual(TopFit.GetSocketBonusData(3305).stats.ITEM_MOD_STAMINA_SHORT, 12, "stamina socket bonus")
    assertEqual(TopFit.GetSocketBonusData(3363).stats.ITEM_MOD_BLOCK_VALUE_SHORT, 9, "block value socket bonus")
    assertEqual(TopFit.GetSocketBonusData(2799).effects[1], "SCALED_STAMINA_SOCKET_BONUS", "scaled test bonus")
end

function tests.blacksmithSocketStacksWithNormalEnchant()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = { [164] = 400 } })
    local variant, reason = TopFit:BuildItemVariant(
        glove(),
        10,
        { gem(40008), gem(39996), gem(40008) },
        enchant(3246),
        modification(3723),
        context
    )

    assertTrue(variant ~= nil, reason)
    assertEqual(#variant.socketColors, 3, "extra socket")
    assertEqual(variant.enchant.enchantID, 3246, "normal glove enchant")
    assertEqual(variant.socketModification.modificationID, 3723, "blacksmith socket")
    assertEqual(variant.staticStats.ITEM_MOD_SPELL_POWER_SHORT, 28, "normal enchant stats")
end

function tests.addedSocketDoesNotChangeBaseSocketBonusRequirement()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = { [164] = 400 } })
    local variant, reason =
        TopFit:BuildItemVariant(glove(), 10, { gem(40008), gem(39996), gem(40014) }, nil, modification(3723), context)

    assertTrue(variant ~= nil, reason)
    assertTrue(variant.socketBonusActive, "matching original sockets should activate bonus")
    assertEqual(variant.staticStats.ITEM_MOD_CRIT_RATING_SHORT, 6, "socket bonus stat")
end

function tests.offColorBaseGemDisablesSocketBonus()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    local variant, reason = TopFit:BuildItemVariant(glove(), 10, { gem(39996), gem(40008) }, nil, nil, context)

    assertTrue(variant ~= nil, reason)
    assertFalse(variant.socketBonusActive, "swapped colors should disable socket bonus")
    assertEqual(variant.staticStats.ITEM_MOD_CRIT_RATING_SHORT, nil, "disabled bonus not added")
end

function tests.metaStatsRemainConditionalUntilWholeSetValidation()
    local item = {
        itemID = 45610,
        itemLevel = 239,
        itemEquipLoc = "INVTYPE_HEAD",
        baseSocketColors = { "META", "BLUE" },
        socketBonusID = 3313,
        itemBonus = {},
    }
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    local variant, reason = TopFit:BuildItemVariant(item, 1, { gem(41285), gem(40008) }, nil, nil, context)

    assertTrue(variant ~= nil, reason)
    assertEqual(#variant.metaGems, 1, "deferred meta gem")
    assertEqual(variant.colorCounts.BLUE, 1, "non-meta color contribution")
    assertEqual(variant.staticStats.ITEM_MOD_CRIT_RATING_SHORT, nil, "inactive meta stat is not unconditional")
    assertEqual(variant.staticStats.ITEM_MOD_AGILITY_SHORT, 8, "active socket bonus remains static")
end

function tests.jewelcrafterLimitIncludesExistingGlobalUsage()
    local item = {
        itemID = 1,
        itemLevel = 200,
        itemEquipLoc = "INVTYPE_CHEST",
        baseSocketColors = { "RED", "RED" },
        socketBonusID = 0,
        itemBonus = {},
    }
    local context = TopFit:BuildCandidateContext({
        phase = 3,
        professionSkills = { [755] = 450 },
        uniqueGemCounts = { JEWELERS_GEMS = 2 },
    })

    local variant, reason = TopFit:BuildItemVariant(item, 5, { gem(42142), gem(42142) }, nil, nil, context)
    assertEqual(variant, nil, "fourth Jeweler's Gem must be rejected")
    assertEqual(reason, "unique-limit", "unique limit reason")
end

function tests.choiceModelKeepsEnchantAndSocketModificationIndependent()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = { [164] = 400 } })
    local choices = TopFit:GetItemVariantChoices(10, glove(), context)
    local foundEnchant = false
    local foundSocket = false

    for _, candidate in ipairs(choices.enchants) do
        if candidate.enchantID == 3246 then
            foundEnchant = true
        end
        assertFalse(candidate.enchantID == 3723, "blacksmith socket must not remain an enchant choice")
    end
    for _, candidate in ipairs(choices.socketModifications) do
        if candidate.modificationID == 3723 then
            foundSocket = true
        end
    end

    assertTrue(foundEnchant, "normal enchant choice")
    assertTrue(foundSocket, "independent blacksmith socket choice")
end

function tests.unscoredEnchantEffectsArePreserved()
    local item = {
        itemID = 1,
        itemLevel = 200,
        itemEquipLoc = "INVTYPE_HAND",
        baseSocketColors = {},
        socketBonusID = 0,
        itemBonus = {},
    }
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = { [202] = 400 } })
    local variant, reason = TopFit:BuildItemVariant(item, 10, {}, enchant(3604), nil, context)

    assertTrue(variant ~= nil, reason)
    assertEqual(variant.effects[1], "HASTE_ON_USE", "engineering effect")
    assertTrue(variant.hasUnscoredEffect, "effect marker")
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

print(("passed %d item-variant tests"):format(#names))
