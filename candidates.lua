-- Candidate filtering and socket/meta rules for gem/enchant optimization.

TopFit.professionSkillLines = {
    [164] = { spellID = 2018, fallbackName = "Blacksmithing" },
    [165] = { spellID = 2108, fallbackName = "Leatherworking" },
    [197] = { spellID = 3908, fallbackName = "Tailoring" },
    [202] = { spellID = 4036, fallbackName = "Engineering" },
    [333] = { spellID = 7411, fallbackName = "Enchanting" },
    [755] = { spellID = 25229, fallbackName = "Jewelcrafting" },
    [773] = { spellID = 45357, fallbackName = "Inscription" },
}

local function Contains(list, wanted)
    for _, value in ipairs(list or {}) do
        if value == wanted then
            return true
        end
    end
    return false
end

local function CopyTable(input)
    local result = {}
    for key, value in pairs(input or {}) do
        result[key] = value
    end
    return result
end

local function SortedByID(candidates, idField)
    table.sort(candidates, function(left, right)
        return (left[idField] or 0) < (right[idField] or 0)
    end)
    return candidates
end

function TopFit:GetPlayerProfessionSkills()
    local professionNames = {}
    for skillLineID, definition in pairs(self.professionSkillLines) do
        local localizedName = GetSpellInfo and GetSpellInfo(definition.spellID)
        professionNames[localizedName or definition.fallbackName] = skillLineID
    end

    local result = {}
    if not GetNumSkillLines or not GetSkillLineInfo then
        return result
    end

    for index = 1, GetNumSkillLines() do
        local skillName, isHeader, _, skillRank = GetSkillLineInfo(index)
        local skillLineID = not isHeader and professionNames[skillName]
        if skillLineID then
            result[skillLineID] = tonumber(skillRank) or 0
        end
    end
    return result
end

function TopFit:BuildCandidateContext(overrides)
    overrides = overrides or {}
    return {
        phase = overrides.phase or self.chromiecraftPhase or 1,
        professionSkills = overrides.professionSkills or self:GetPlayerProfessionSkills(),
        uniqueGemCounts = CopyTable(overrides.uniqueGemCounts),
    }
end

function TopFit.IsCandidateProfessionAvailable(candidate, context)
    if not candidate.professionSkillLine then
        return true
    end

    local rank = context.professionSkills[candidate.professionSkillLine] or 0
    return rank >= (candidate.professionSkill or 1)
end

function TopFit:IsGemCandidateAvailable(candidate, context)
    context = context or self:BuildCandidateContext()
    if (candidate.minChromiePhase or 1) > context.phase then
        return false
    end
    if not self.IsCandidateProfessionAvailable(candidate, context) then
        return false
    end
    if candidate.uniqueGroup and candidate.uniqueLimit then
        local count = context.uniqueGemCounts[candidate.uniqueGroup] or 0
        if count >= candidate.uniqueLimit then
            return false
        end
    end
    return true
end

function TopFit.GemContributesColor(candidate, color)
    if color == "META" then
        return Contains(candidate.colors, "META")
    end
    return Contains(candidate.colors, color)
end

function TopFit:GemFitsSocket(candidate, socketColor)
    if socketColor == "META" then
        return self.GemContributesColor(candidate, "META")
    end
    return not self.GemContributesColor(candidate, "META")
end

function TopFit:GemMatchesSocket(candidate, socketColor)
    if socketColor == "PRISMATIC" then
        return not self.GemContributesColor(candidate, "META")
    end
    return self.GemContributesColor(candidate, socketColor)
end

function TopFit:CountGemColors(gems)
    local counts = { RED = 0, YELLOW = 0, BLUE = 0 }
    for _, gem in ipairs(gems or {}) do
        if not self.GemContributesColor(gem, "META") then
            for color in pairs(counts) do
                if self.GemContributesColor(gem, color) then
                    counts[color] = counts[color] + 1
                end
            end
        end
    end
    return counts
end

function TopFit.IsMetaConditionSatisfied(metaGem, colorCounts)
    local condition = metaGem.metaCondition
    if not condition then
        return true
    end

    for color, minimum in pairs(condition.minimum or {}) do
        if (colorCounts[color] or 0) < minimum then
            return false
        end
    end

    for _, comparison in ipairs(condition.comparisons or {}) do
        local left = colorCounts[comparison.left] or 0
        local right = colorCounts[comparison.right] or 0
        if comparison.op == ">" and left <= right then
            return false
        elseif comparison.op == ">=" and left < right then
            return false
        elseif comparison.op == "<" and left >= right then
            return false
        elseif comparison.op == "<=" and left > right then
            return false
        elseif comparison.op == "==" and left ~= right then
            return false
        end
    end

    return true
end

function TopFit:GetGemCandidatesForSocket(socketColor, context)
    context = context or self:BuildCandidateContext()
    local result = {}
    for _, candidate in ipairs(self.gemCandidates or {}) do
        if self:IsGemCandidateAvailable(candidate, context) and self:GemFitsSocket(candidate, socketColor) then
            tinsert(result, candidate)
        end
    end
    return SortedByID(result, "itemID")
end

function TopFit:BuildGemCandidateSets(socketColors, context)
    local result = {}
    for index, socketColor in ipairs(socketColors or {}) do
        result[index] = self:GetGemCandidatesForSocket(socketColor, context)
    end
    return result
end

function TopFit:ValidateGemLoadout(socketColors, gems, context)
    context = context or self:BuildCandidateContext()
    if #(socketColors or {}) ~= #(gems or {}) then
        return false, "socket-count-mismatch"
    end

    local uniqueCounts = CopyTable(context.uniqueGemCounts)
    for index, socketColor in ipairs(socketColors or {}) do
        local gem = gems[index]
        if not gem or not self:IsGemCandidateAvailable(gem, context) or not self:GemFitsSocket(gem, socketColor) then
            return false, "invalid-gem"
        end

        if gem.uniqueGroup and gem.uniqueLimit then
            uniqueCounts[gem.uniqueGroup] = (uniqueCounts[gem.uniqueGroup] or 0) + 1
            if uniqueCounts[gem.uniqueGroup] > gem.uniqueLimit then
                return false, "unique-limit"
            end
        end
    end

    local colorCounts = self:CountGemColors(gems)
    for _, gem in ipairs(gems or {}) do
        if self.GemContributesColor(gem, "META") and not self.IsMetaConditionSatisfied(gem, colorCounts) then
            return false, "meta-inactive"
        end
    end

    return true
end

function TopFit:IsSocketBonusActive(socketColors, gems)
    if #(socketColors or {}) ~= #(gems or {}) then
        return false
    end
    for index, socketColor in ipairs(socketColors or {}) do
        local gem = gems[index]
        if not gem or not self:GemMatchesSocket(gem, socketColor) then
            return false
        end
    end
    return true
end

function TopFit:IsEnchantCandidateAvailable(candidate, context, slotID, item)
    context = context or self:BuildCandidateContext()
    if (candidate.minChromiePhase or 1) > context.phase then
        return false
    end
    if not self.IsCandidateProfessionAvailable(candidate, context) then
        return false
    end
    if slotID and not Contains(candidate.slots, slotID) then
        return false
    end

    local itemLevel = item and item.itemLevel
    if candidate.minItemLevel and itemLevel and itemLevel < candidate.minItemLevel then
        return false
    end

    local equipLoc = item and item.itemEquipLoc
    if candidate.equipLocs and equipLoc and not Contains(candidate.equipLocs, equipLoc) then
        return false
    end
    if candidate.weaponOnly and equipLoc and not string.find(equipLoc, "WEAPON", 1, true) then
        return false
    end

    return true
end

function TopFit:GetEnchantCandidatesForItem(slotID, item, context)
    context = context or self:BuildCandidateContext()
    local result = {}
    for _, candidate in ipairs(self.enchantCandidates or {}) do
        if self:IsEnchantCandidateAvailable(candidate, context, slotID, item) then
            tinsert(result, candidate)
        end
    end
    return SortedByID(result, "enchantID")
end

function TopFit.CandidateHasUnscoredEffect(candidate)
    return candidate.effects ~= nil and #candidate.effects > 0
end
