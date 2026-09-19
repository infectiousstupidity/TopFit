-- Build bounded gem/enchant variants for an owned item.
--
-- The full Cartesian product is too large for the legacy frame-yielded gear search. This module
-- keeps a compact frontier that preserves score, cap, socket-color, meta, and Jewelcrafter choices.

local MAX_VARIANTS_PER_ITEM = 10
local GEM_BEAM_WIDTH = 24

local function CopyTable(input)
    local result = {}
    for key, value in pairs(input or {}) do
        result[key] = value
    end
    return result
end

local function CopyArray(input)
    local result = {}
    for index, value in ipairs(input or {}) do
        result[index] = value
    end
    return result
end

local function AddStats(target, source)
    for stat, value in pairs(source or {}) do
        target[stat] = (target[stat] or 0) + value
        if target[stat] == 0 then
            target[stat] = nil
        end
    end
    return target
end

local function SubtractStats(target, source)
    for stat, value in pairs(source or {}) do
        target[stat] = (target[stat] or 0) - value
        if target[stat] == 0 then
            target[stat] = nil
        end
    end
    return target
end

local function WeightedScore(stats, weights)
    local score = 0
    for stat, value in pairs(stats or {}) do
        score = score + (weights[stat] or 0) * value
    end
    return score
end

local function HasActiveCap(capList)
    for _, entry in ipairs(capList or {}) do
        if entry.active then
            return true
        end
    end
    return false
end

local function InsertUniqueByID(list, candidate, idField)
    if not candidate then
        return
    end
    for _, existing in ipairs(list) do
        if existing[idField] == candidate[idField] then
            return
        end
    end
    tinsert(list, candidate)
end

local function SortByWeightedScore(list, weights)
    table.sort(list, function(left, right)
        local leftScore = WeightedScore(left.stats, weights)
        local rightScore = WeightedScore(right.stats, weights)
        if leftScore == rightScore then
            return (left.itemID or left.enchantID or 0) < (right.itemID or right.enchantID or 0)
        end
        return leftScore > rightScore
    end)
end

local function ActiveCapStats(caps)
    local stats = {}
    for stat, capList in pairs(caps or {}) do
        if HasActiveCap(capList) then
            tinsert(stats, stat)
        end
    end
    table.sort(stats)
    return stats
end

local function GemSignature(state, caps)
    local metaID = 0
    if state.metaGems and state.metaGems[1] then
        metaID = state.metaGems[1].itemID or 0
    end
    local colors = state.colorCounts or {}
    local unique = state.uniqueGemCounts or {}
    local parts = {
        math.min(colors.RED or 0, 3),
        math.min(colors.YELLOW or 0, 3),
        math.min(colors.BLUE or 0, 3),
        math.min(unique.JEWELERS_GEMS or 0, 3),
        metaID,
    }
    for _, stat in ipairs(ActiveCapStats(caps)) do
        tinsert(parts, stat)
        tinsert(parts, state.gemStats[stat] or 0)
    end
    return table.concat(parts, ":")
end

local function ParseItemFields(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end
    local payload = string.match(itemLink, "item:([^|]+)")
    if not payload and string.sub(itemLink, 1, 5) == "item:" then
        payload = string.sub(itemLink, 6)
    end
    if not payload then
        return nil
    end

    local fields = {}
    for value in string.gmatch(payload .. ":", "(.-):") do
        tinsert(fields, value)
    end
    while #fields < 10 do
        tinsert(fields, "0")
    end
    return fields
end

function TopFit.BuildVariantItemLink(itemLink, enchantID, gemIDs)
    local fields = ParseItemFields(itemLink)
    if not fields then
        return itemLink
    end

    fields[2] = tostring(enchantID or 0)
    for index = 1, 4 do
        fields[index + 2] = tostring((gemIDs and gemIDs[index]) or 0)
    end

    local replacement = "item:" .. table.concat(fields, ":")
    if string.find(itemLink, "|Hitem:", 1, true) then
        return (string.gsub(itemLink, "item:[^|]+", replacement, 1))
    end
    return replacement
end

function TopFit.GetItemModificationIDs(itemLink)
    local fields = ParseItemFields(itemLink)
    if not fields then
        return 0, {}
    end

    local gems = {}
    for index = 1, 4 do
        gems[index] = tonumber(fields[index + 2]) or 0
    end
    return tonumber(fields[2]) or 0, gems
end

function TopFit:EnsureCandidateIndexes()
    if self.gemCandidateByID and self.enchantCandidateByID then
        return
    end

    self.gemCandidateByID = {}
    for _, candidate in ipairs(self.gemCandidates or {}) do
        self.gemCandidateByID[candidate.itemID] = candidate
    end

    self.enchantCandidateByID = {}
    for _, candidate in ipairs(self.enchantCandidates or {}) do
        self.enchantCandidateByID[candidate.enchantID] = candidate
    end
end

function TopFit:GetBaseVariantStats(itemTable)
    local stats = CopyTable(itemTable.totalBonus)
    SubtractStats(stats, itemTable.gemBonus)
    SubtractStats(stats, itemTable.enchantBonus)
    return stats
end

function TopFit:GetSocketBonusStats(socketBonusID)
    return self.socketBonusStats and self.socketBonusStats[socketBonusID]
end

local function GemConstraintClass(self, candidate)
    if self.GemContributesColor(candidate, "META") then
        return "META:" .. tostring(candidate.itemID)
    end

    local colors = {}
    for _, color in ipairs({ "RED", "YELLOW", "BLUE" }) do
        if self.GemContributesColor(candidate, color) then
            tinsert(colors, color)
        end
    end
    return table.concat(colors, "+") .. ":" .. tostring(candidate.uniqueGroup or "normal")
end

function TopFit:SelectGemCandidatesForVariant(socketColor, context, weights, caps, currentGemID)
    local available = self:GetGemCandidatesForSocket(socketColor, context)
    local selected = {}

    if socketColor == "META" then
        for _, candidate in ipairs(available) do
            InsertUniqueByID(selected, candidate, "itemID")
        end
    end

    SortByWeightedScore(available, weights)
    for index = 1, math.min(3, #available) do
        InsertUniqueByID(selected, available[index], "itemID")
    end

    local bestByConstraintClass = {}
    for _, candidate in ipairs(available) do
        local key = GemConstraintClass(self, candidate)
        local current = bestByConstraintClass[key]
        if not current or WeightedScore(candidate.stats, weights) > WeightedScore(current.stats, weights) then
            bestByConstraintClass[key] = candidate
        end
    end
    for _, candidate in pairs(bestByConstraintClass) do
        InsertUniqueByID(selected, candidate, "itemID")
    end

    local matching = {}
    for _, candidate in ipairs(available) do
        if self:GemMatchesSocket(candidate, socketColor) then
            tinsert(matching, candidate)
        end
    end
    SortByWeightedScore(matching, weights)
    for index = 1, math.min(3, #matching) do
        InsertUniqueByID(selected, matching[index], "itemID")
    end

    for stat, capList in pairs(caps or {}) do
        if HasActiveCap(capList) then
            local best
            local bestValue = 0
            for _, candidate in ipairs(available) do
                local value = candidate.stats[stat] or 0
                if value > bestValue then
                    best = candidate
                    bestValue = value
                elseif value == bestValue and value > 0 and best then
                    if WeightedScore(candidate.stats, weights) > WeightedScore(best.stats, weights) then
                        best = candidate
                    end
                end
            end
            InsertUniqueByID(selected, best, "itemID")
        end
    end

    self:EnsureCandidateIndexes()
    InsertUniqueByID(selected, self.gemCandidateByID[currentGemID], "itemID")

    table.sort(selected, function(left, right)
        return left.itemID < right.itemID
    end)
    return selected
end

local function ExtendGemState(self, state, candidate, weights)
    local nextState = {
        gems = CopyArray(state.gems),
        gemIDs = CopyArray(state.gemIDs),
        gemStats = CopyTable(state.gemStats),
        colorCounts = CopyTable(state.colorCounts),
        uniqueGemCounts = CopyTable(state.uniqueGemCounts),
        metaGems = CopyArray(state.metaGems),
    }

    tinsert(nextState.gems, candidate)
    tinsert(nextState.gemIDs, candidate.itemID)
    AddStats(nextState.gemStats, candidate.stats)

    if self.GemContributesColor(candidate, "META") then
        tinsert(nextState.metaGems, candidate)
    else
        for _, color in ipairs({ "RED", "YELLOW", "BLUE" }) do
            if self.GemContributesColor(candidate, color) then
                nextState.colorCounts[color] = (nextState.colorCounts[color] or 0) + 1
            end
        end
    end

    if candidate.uniqueGroup then
        local count = (nextState.uniqueGemCounts[candidate.uniqueGroup] or 0) + 1
        if candidate.uniqueLimit and count > candidate.uniqueLimit then
            return nil
        end
        nextState.uniqueGemCounts[candidate.uniqueGroup] = count
    end

    nextState.localScore = WeightedScore(nextState.gemStats, weights)
    return nextState
end

local function PruneGemBeam(states, caps)
    table.sort(states, function(left, right)
        if left.localScore == right.localScore then
            return GemSignature(left, caps) < GemSignature(right, caps)
        end
        return left.localScore > right.localScore
    end)

    local result = {}
    local signatures = {}
    for _, state in ipairs(states) do
        local signature = GemSignature(state, caps)
        if not signatures[signature] then
            signatures[signature] = true
            tinsert(result, state)
        end
        if #result >= GEM_BEAM_WIDTH then
            break
        end
    end
    return result
end

function TopFit:BuildGemLoadouts(socketColors, context, weights, caps, currentGemIDs)
    local beam = {
        {
            gems = {},
            gemIDs = {},
            gemStats = {},
            colorCounts = { RED = 0, YELLOW = 0, BLUE = 0 },
            uniqueGemCounts = {},
            metaGems = {},
            localScore = 0,
        },
    }

    for index, socketColor in ipairs(socketColors or {}) do
        local candidates = self:SelectGemCandidatesForVariant(
            socketColor,
            context,
            weights,
            caps,
            currentGemIDs and currentGemIDs[index]
        )
        if #candidates == 0 then
            return {}
        end

        local extended = {}
        for _, state in ipairs(beam) do
            for _, candidate in ipairs(candidates) do
                local nextState = ExtendGemState(self, state, candidate, weights)
                if nextState then
                    tinsert(extended, nextState)
                end
            end
        end
        beam = PruneGemBeam(extended, caps)
    end

    return beam
end

local function CurrentVariantMetadata(self, itemLink)
    self:EnsureCandidateIndexes()
    local _, gemIDs = self.GetItemModificationIDs(itemLink)
    local metadata = {
        gemColorCounts = { RED = 0, YELLOW = 0, BLUE = 0 },
        uniqueGemCounts = {},
        metaGems = {},
        hasUnknownGem = false,
    }

    for _, gemID in ipairs(gemIDs) do
        if gemID and gemID > 0 then
            local gem = self.gemCandidateByID[gemID]
            if not gem then
                metadata.hasUnknownGem = true
            elseif self.GemContributesColor(gem, "META") then
                tinsert(metadata.metaGems, gem)
            else
                for _, color in ipairs({ "RED", "YELLOW", "BLUE" }) do
                    if self.GemContributesColor(gem, color) then
                        metadata.gemColorCounts[color] = metadata.gemColorCounts[color] + 1
                    end
                end
                if gem.uniqueGroup then
                    metadata.uniqueGemCounts[gem.uniqueGroup] = (metadata.uniqueGemCounts[gem.uniqueGroup] or 0) + 1
                end
            end
        end
    end
    return metadata
end

local function VariantSignature(variant, caps)
    local metaID = 0
    if variant.metaGems and variant.metaGems[1] then
        metaID = variant.metaGems[1].itemID or 0
    end
    local colors = variant.gemColorCounts or {}
    local unique = variant.uniqueGemCounts or {}
    local parts = {
        math.min(colors.RED or 0, 3),
        math.min(colors.YELLOW or 0, 3),
        math.min(colors.BLUE or 0, 3),
        math.min(unique.JEWELERS_GEMS or 0, 3),
        metaID,
        variant.socketBonusActive and 1 or 0,
    }
    for _, stat in ipairs(ActiveCapStats(caps)) do
        tinsert(parts, stat)
        tinsert(parts, variant.itemTable.totalBonus[stat] or 0)
    end
    return table.concat(parts, ":")
end

function TopFit:PruneItemVariants(variants, weights, caps)
    table.sort(variants, function(left, right)
        local leftScore = WeightedScore(left.itemTable.totalBonus, weights)
        local rightScore = WeightedScore(right.itemTable.totalBonus, weights)
        if leftScore == rightScore then
            return left.itemLink < right.itemLink
        end
        return leftScore > rightScore
    end)

    local result = {}
    local links = {}
    local signatures = {}

    local function keep(variant)
        if links[variant.itemLink] then
            return
        end
        links[variant.itemLink] = true
        signatures[VariantSignature(variant, caps)] = true
        tinsert(result, variant)
    end

    for _, variant in ipairs(variants) do
        if variant.isCurrent then
            keep(variant)
            break
        end
    end

    for index = 1, math.min(4, #variants) do
        keep(variants[index])
    end

    for stat, capList in pairs(caps or {}) do
        if HasActiveCap(capList) then
            local best
            local bestValue
            for _, variant in ipairs(variants) do
                local value = variant.itemTable.totalBonus[stat] or 0
                if not bestValue or value > bestValue then
                    best = variant
                    bestValue = value
                end
            end
            keep(best)
        end
    end

    for _, variant in ipairs(variants) do
        local signature = VariantSignature(variant, caps)
        if not signatures[signature] then
            keep(variant)
        end
        if #result >= MAX_VARIANTS_PER_ITEM then
            break
        end
    end

    return result
end

function TopFit:BuildItemVariants(baseItemLink, slotID, setCode)
    local itemTable = self:GetCachedItem(baseItemLink)
    if not itemTable then
        return {}
    end

    self:EnsureCandidateIndexes()

    local setTable = self.db.profile.sets[setCode]
    local weights = setTable.weights or {}
    local caps = setTable.caps or {}
    local context = self:BuildCandidateContext()
    local currentEnchantID, currentGemIDs = self.GetItemModificationIDs(baseItemLink)
    local baseStats = self:GetBaseVariantStats(itemTable)
    local variants = {}

    local currentMetadata = CurrentVariantMetadata(self, baseItemLink)
    tinsert(variants, {
        itemLink = baseItemLink,
        itemTable = itemTable,
        gemColorCounts = currentMetadata.gemColorCounts,
        uniqueGemCounts = currentMetadata.uniqueGemCounts,
        metaGems = currentMetadata.metaGems,
        hasUnknownGem = currentMetadata.hasUnknownGem,
        isCurrent = true,
        requiresModification = false,
    })

    local enchantChoices = {
        { enchantID = 0, stats = {}, name = "No enchant" },
    }
    for _, enchant in ipairs(self:GetEnchantCandidatesForItem(slotID, itemTable, context)) do
        tinsert(enchantChoices, enchant)
    end

    local currentEnchant = self.enchantCandidateByID[currentEnchantID]
    if currentEnchantID and currentEnchantID > 0 then
        local currentEnchantChoice = {
            enchantID = currentEnchantID,
            name = (currentEnchant and currentEnchant.name) or "Current enchant",
            stats = CopyTable(itemTable.enchantBonus),
            effects = currentEnchant and currentEnchant.effects,
            addsSocket = currentEnchant and currentEnchant.addsSocket,
        }
        InsertUniqueByID(enchantChoices, currentEnchantChoice, "enchantID")
    end

    for _, enchant in ipairs(enchantChoices) do
        local socketColors = CopyArray(itemTable.baseSocketColors)
        if enchant.addsSocket then
            tinsert(socketColors, enchant.addsSocket)
        end

        local loadouts
        if #socketColors == 0 then
            loadouts = {
                {
                    gems = {},
                    gemIDs = {},
                    gemStats = {},
                    colorCounts = { RED = 0, YELLOW = 0, BLUE = 0 },
                    uniqueGemCounts = {},
                    metaGems = {},
                },
            }
        else
            loadouts = self:BuildGemLoadouts(socketColors, context, weights, caps, currentGemIDs)
        end

        for _, loadout in ipairs(loadouts) do
            local totalStats = CopyTable(baseStats)
            AddStats(totalStats, loadout.gemStats)
            AddStats(totalStats, enchant.stats)

            local socketBonusActive = self:IsSocketBonusActive(socketColors, loadout.gems)
            local socketBonusStats
            local hasUnscoredSocketBonus = false
            if socketBonusActive and itemTable.socketBonusID and itemTable.socketBonusID > 0 then
                socketBonusStats = self:GetSocketBonusStats(itemTable.socketBonusID)
                if socketBonusStats then
                    AddStats(totalStats, socketBonusStats)
                else
                    hasUnscoredSocketBonus = true
                end
            end

            local gemBonus = CopyTable(loadout.gemStats)
            AddStats(gemBonus, socketBonusStats)
            local variantLink = self.BuildVariantItemLink(baseItemLink, enchant.enchantID, loadout.gemIDs)
            local variantTable = CopyTable(itemTable)
            variantTable.itemLink = variantLink
            variantTable.totalBonus = totalStats
            variantTable.gemBonus = gemBonus
            variantTable.enchantBonus = CopyTable(enchant.stats)
            variantTable.gems = CopyArray(loadout.gemIDs)
            variantTable.emptySocketColors = {}
            variantTable.socketBonusInfo = nil
            variantTable.variantSourceItemLink = baseItemLink
            local hasUnscoredGemEffect = false
            for _, gem in ipairs(loadout.gems) do
                if self.CandidateHasUnscoredEffect(gem) then
                    hasUnscoredGemEffect = true
                    break
                end
            end
            variantTable.hasUnscoredVariantEffect = self.CandidateHasUnscoredEffect(enchant)
                or hasUnscoredGemEffect
                or hasUnscoredSocketBonus

            tinsert(variants, {
                itemLink = variantLink,
                itemTable = variantTable,
                gemColorCounts = CopyTable(loadout.colorCounts),
                uniqueGemCounts = CopyTable(loadout.uniqueGemCounts),
                metaGems = CopyArray(loadout.metaGems),
                socketBonusActive = socketBonusActive,
                hasUnscoredSocketBonus = hasUnscoredSocketBonus,
                hasUnscoredEffect = variantTable.hasUnscoredVariantEffect,
                isCurrent = variantLink == baseItemLink,
                requiresModification = variantLink ~= baseItemLink,
            })
        end
    end

    return self:PruneItemVariants(variants, weights, caps)
end
