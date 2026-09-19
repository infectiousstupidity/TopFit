TopFit = {}
tinsert = table.insert

dofile("data/gems.lua")
dofile("data/enchants.lua")
dofile("candidates.lua")

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

function tests.offColorGemsPhysicallyFitButDoNotMatch()
    local red = gem(39996)
    assertTrue(TopFit:GemFitsSocket(red, "BLUE"), "red gem should physically fit a blue socket")
    assertFalse(TopFit:GemMatchesSocket(red, "BLUE"), "red gem should not satisfy a blue socket bonus")
    assertTrue(TopFit:GemMatchesSocket(red, "RED"), "red gem should satisfy a red socket")
end

function tests.hybridAndPrismaticColorContribution()
    local orange = gem(40038)
    local prismatic = gem(42702)
    local counts = TopFit:CountGemColors({ orange, prismatic })

    assertEqual(counts.RED, 2, "orange and prismatic both count red")
    assertEqual(counts.YELLOW, 2, "orange and prismatic both count yellow")
    assertEqual(counts.BLUE, 1, "only prismatic counts blue")
end

function tests.metaActivationUsesWholeLoadoutColors()
    local chaotic = gem(41285)
    local blue = gem(40008)
    local purple = gem(40022)

    assertTrue(
        TopFit:IsMetaConditionSatisfied(chaotic, TopFit:CountGemColors({ blue, purple })),
        "two blue contributions"
    )
    assertFalse(
        TopFit:IsMetaConditionSatisfied(chaotic, TopFit:CountGemColors({ blue })),
        "one blue contribution"
    )
end

function tests.currentPhaseExcludesTocEpicGems()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    assertFalse(TopFit:IsGemCandidateAvailable(gem(40111), context), "normal epic gem is phase 4")
    assertTrue(TopFit:IsGemCandidateAvailable(gem(45862), context), "Stormjewel is phase 3")
end

function tests.jewelcrafterGemsRequireSkillAndRespectUniqueLimit()
    local dragonEye = gem(42142)

    local noProfession = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    assertFalse(TopFit:IsGemCandidateAvailable(dragonEye, noProfession), "Dragon's Eye requires Jewelcrafting")

    local jeweler = TopFit:BuildCandidateContext({ phase = 3, professionSkills = { [755] = 350 } })
    assertTrue(TopFit:IsGemCandidateAvailable(dragonEye, jeweler), "Jewelcrafting 350 unlocks Dragon's Eye")

    local capped = TopFit:BuildCandidateContext({
        phase = 3,
        professionSkills = { [755] = 450 },
        uniqueGemCounts = { JEWELERS_GEMS = 3 },
    })
    assertFalse(TopFit:IsGemCandidateAvailable(dragonEye, capped), "three existing Jeweler's Gems reaches limit")
end

function tests.loadoutValidationEnforcesMetaAndUniqueRules()
    local chaotic = gem(41285)
    local blue = gem(40008)
    local purple = gem(40022)
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })

    local valid, reason = TopFit:ValidateGemLoadout({ "META", "BLUE", "RED" }, { chaotic, blue, purple }, context)
    assertTrue(valid, reason)

    valid, reason =
        TopFit:ValidateGemLoadout({ "META", "RED", "RED" }, { chaotic, gem(39996), gem(39996) }, context)
    assertFalse(valid, "chaotic should be inactive")
    assertEqual(reason, "meta-inactive", "inactive meta reason")
end

function tests.socketBonusRequiresColorMatchNotJustPhysicalFit()
    local red = gem(39996)
    local blue = gem(40008)

    assertTrue(TopFit:IsSocketBonusActive({ "RED", "BLUE" }, { red, blue }), "matching colors activate bonus")
    assertFalse(TopFit:IsSocketBonusActive({ "RED", "BLUE" }, { blue, red }), "off-colors disable bonus")
end

function tests.professionEnchantFiltering()
    local ringSpellpower = enchant(3840)
    local noProfession = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    assertFalse(
        TopFit:IsEnchantCandidateAvailable(ringSpellpower, noProfession, 11, { itemLevel = 200 }),
        "ring enchant is Enchanting-only"
    )

    local enchanter = TopFit:BuildCandidateContext({ phase = 3, professionSkills = { [333] = 400 } })
    assertTrue(
        TopFit:IsEnchantCandidateAvailable(ringSpellpower, enchanter, 11, { itemLevel = 200 }),
        "Enchanting 400 unlocks ring enchant"
    )
end

function tests.itemTypeRestrictsEnchantCandidates()
    local massacre = enchant(3827)
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })

    assertTrue(
        TopFit:IsEnchantCandidateAvailable(
            massacre,
            context,
            16,
            { itemLevel = 200, itemEquipLoc = "INVTYPE_2HWEAPON" }
        ),
        "Massacre fits two-hand weapon"
    )
    assertFalse(
        TopFit:IsEnchantCandidateAvailable(
            massacre,
            context,
            16,
            { itemLevel = 200, itemEquipLoc = "INVTYPE_WEAPON" }
        ),
        "Massacre must not fit one-hand weapon"
    )
end

function tests.professionScannerUsesWrathSkillLineApi()
    local oldGetSpellInfo = GetSpellInfo
    local oldGetNumSkillLines = GetNumSkillLines
    local oldGetSkillLineInfo = GetSkillLineInfo

    GetSpellInfo = function(spellID)
        if spellID == 25229 then
            return "Jewelcrafting"
        end
        if spellID == 7411 then
            return "Enchanting"
        end
        return "Profession " .. tostring(spellID)
    end
    GetNumSkillLines = function()
        return 3
    end
    GetSkillLineInfo = function(index)
        if index == 1 then
            return "Professions", true, nil, nil
        end
        if index == 2 then
            return "Jewelcrafting", false, nil, 385
        end
        return "Enchanting", false, nil, 450
    end

    local skills = TopFit:GetPlayerProfessionSkills()

    GetSpellInfo = oldGetSpellInfo
    GetNumSkillLines = oldGetNumSkillLines
    GetSkillLineInfo = oldGetSkillLineInfo

    assertEqual(skills[755], 385, "Jewelcrafting rank")
    assertEqual(skills[333], 450, "Enchanting rank")
end

function tests.candidateSetsAreDeterministicAndSocketSpecific()
    local context = TopFit:BuildCandidateContext({ phase = 3, professionSkills = {} })
    local sets = TopFit:BuildGemCandidateSets({ "RED", "META" }, context)

    assertTrue(#sets[1] > 0, "colored socket has candidates")
    assertTrue(#sets[2] > 0, "meta socket has candidates")
    assertFalse(TopFit:GemContributesColor(sets[1][1], "META"), "normal socket excludes meta gems")
    assertTrue(TopFit:GemContributesColor(sets[2][1], "META"), "meta socket contains only meta gems")

    for index = 2, #sets[1] do
        assertTrue(sets[1][index - 1].itemID < sets[1][index].itemID, "candidate order is stable by item ID")
    end
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

print(("passed %d candidate-model tests"):format(#names))
