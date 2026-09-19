-- Concrete item-variant composition for the future whole-set search.
--
-- This module intentionally does not enumerate every gem combination. It exposes legal choice
-- dimensions and composes one selected combination into a deterministic variant record.

local function CopyList(input)
    local result = {}
    for _, value in ipairs(input or {}) do
        tinsert(result, value)
    end
    return result
end

local function CopyStats(input)
    local result = {}
    for stat, value in pairs(input or {}) do
        result[stat] = value
    end
    return result
end

local function AddStats(target, source)
    for stat, value in pairs(source or {}) do
        target[stat] = (target[stat] or 0) + value
    end
end

local function AppendEffects(target, source)
    for _, effect in ipairs(source or {}) do
        tinsert(target, effect)
    end
end

function TopFit.GetSocketBonusData(socketBonusID)
    local numericID = tonumber(socketBonusID)
    return numericID and TopFit.socketBonusData and TopFit.socketBonusData[numericID] or nil
end

function TopFit:GetEffectiveSocketColors(itemTable, socketModification)
    local colors = CopyList(itemTable and itemTable.baseSocketColors)
    if socketModification and socketModification.addsSocket then
        tinsert(colors, socketModification.addsSocket)
    end
    return colors
end

function TopFit:GetItemVariantChoices(slotID, itemTable, context)
    context = context or self:BuildCandidateContext()
    local baseSocketColors = self:GetEffectiveSocketColors(itemTable)
    local modifications = self:GetSocketModificationCandidatesForItem(slotID, itemTable, context)
    local modified = {}

    for _, modification in ipairs(modifications) do
        local socketColors = self:GetEffectiveSocketColors(itemTable, modification)
        tinsert(modified, {
            modification = modification,
            socketColors = socketColors,
            gemCandidates = self:BuildGemCandidateSets(socketColors, context),
        })
    end

    return {
        socketColors = baseSocketColors,
        gemCandidates = self:BuildGemCandidateSets(baseSocketColors, context),
        enchants = self:GetEnchantCandidatesForItem(slotID, itemTable, context),
        socketModifications = modifications,
        modifiedSocketChoices = modified,
    }
end

function TopFit:BuildItemVariant(itemTable, slotID, gems, enchant, socketModification, context)
    context = context or self:BuildCandidateContext()
    gems = gems or {}

    if not itemTable then
        return nil, "missing-item"
    end
    if enchant and not self:IsEnchantCandidateAvailable(enchant, context, slotID, itemTable) then
        return nil, "invalid-enchant"
    end
    if
        socketModification
        and not self:IsSocketModificationCandidateAvailable(socketModification, context, slotID, itemTable)
    then
        return nil, "invalid-socket-modification"
    end

    local baseSocketColors = CopyList(itemTable.baseSocketColors)
    local socketColors = self:GetEffectiveSocketColors(itemTable, socketModification)
    if #socketColors ~= #gems then
        return nil, "socket-count-mismatch"
    end

    local localUniqueCounts = {}
    local colorCounts = { RED = 0, YELLOW = 0, BLUE = 0 }
    local metaGems = {}
    local staticStats = CopyStats(itemTable.itemBonus)

    for index, socketColor in ipairs(socketColors) do
        local gem = gems[index]
        if not gem or not self:IsGemCandidateAvailable(gem, context) or not self:GemFitsSocket(gem, socketColor) then
            return nil, "invalid-gem"
        end

        if gem.uniqueGroup and gem.uniqueLimit then
            localUniqueCounts[gem.uniqueGroup] = (localUniqueCounts[gem.uniqueGroup] or 0) + 1
            local totalCount = (context.uniqueGemCounts[gem.uniqueGroup] or 0) + localUniqueCounts[gem.uniqueGroup]
            if totalCount > gem.uniqueLimit then
                return nil, "unique-limit"
            end
        end

        if self.GemContributesColor(gem, "META") then
            tinsert(metaGems, gem)
        else
            AddStats(staticStats, gem.stats)
            for color in pairs(colorCounts) do
                if self.GemContributesColor(gem, color) then
                    colorCounts[color] = colorCounts[color] + 1
                end
            end
        end
    end

    AddStats(staticStats, enchant and enchant.stats)
    AddStats(staticStats, socketModification and socketModification.stats)

    local baseGems = {}
    for index = 1, #baseSocketColors do
        baseGems[index] = gems[index]
    end

    local socketBonusActive = #baseSocketColors > 0 and self:IsSocketBonusActive(baseSocketColors, baseGems)
    local socketBonus = socketBonusActive and self.GetSocketBonusData(itemTable.socketBonusID) or nil
    local effects = {}
    if socketBonus then
        AddStats(staticStats, socketBonus.stats)
        AppendEffects(effects, socketBonus.effects)
    end
    AppendEffects(effects, enchant and enchant.effects)
    AppendEffects(effects, socketModification and socketModification.effects)

    return {
        item = itemTable,
        slotID = slotID,
        gems = gems,
        enchant = enchant,
        socketModification = socketModification,
        socketColors = socketColors,
        socketBonusActive = socketBonusActive and true or false,
        socketBonus = socketBonus,
        staticStats = staticStats,
        colorCounts = colorCounts,
        uniqueGemCounts = localUniqueCounts,
        metaGems = metaGems,
        effects = effects,
        procInfo = itemTable.procInfo,
        hasUnscoredProc = itemTable.hasUnscoredProc and true or false,
        hasUnscoredEffect = #effects > 0,
    }
end
