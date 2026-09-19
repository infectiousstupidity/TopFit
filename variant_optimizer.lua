-- Integrate gem/enchant variants into TopFit's existing whole-set search.

local LegacySaveCurrentCombination = TopFit.SaveCurrentCombination
local LegacyEquipRecommendedItems = TopFit.EquipRecommendedItems
local LegacyCalculateBestInSlot = TopFit.CalculateBestInSlot
local LegacyIsCapsReached = TopFit.IsCapsReached
local LegacyIsCapsUnreachable = TopFit.IsCapsUnreachable

local function CopyLocation(location)
    local result = {}
    for key, value in pairs(location or {}) do
        result[key] = value
    end
    return result
end

local function PhysicalKey(location)
    if location.physicalKey then
        return location.physicalKey
    end
    if location.isVirtual or location.source == "virtual" then
        return "virtual:" .. tostring(location.physicalItemLink or location.itemLink)
    end
    return table.concat({
        tostring(location.source or "owned"),
        tostring(location.bag or ""),
        tostring(location.slot or ""),
        tostring(location.physicalItemLink or location.itemLink or ""),
    }, ":")
end

local function ConstraintSignature(location)
    local variant = location.variant
    if not variant then
        return "current"
    end

    local colors = variant.gemColorCounts or {}
    local unique = variant.uniqueGemCounts or {}
    local metaID = 0
    if variant.metaGems and variant.metaGems[1] then
        metaID = variant.metaGems[1].itemID or 0
    end

    return table.concat({
        math.min(colors.RED or 0, 3),
        math.min(colors.YELLOW or 0, 3),
        math.min(colors.BLUE or 0, 3),
        math.min(unique.JEWELERS_GEMS or 0, 3),
        metaID,
        variant.hasUnknownGem and 1 or 0,
    }, ":")
end

function TopFit:ExpandOwnedItemVariants()
    local expandedBySlot = {}
    local variantCache = {}

    for slotID, locations in pairs(self.itemListBySlot or {}) do
        local expanded = {}
        variantCache[slotID] = variantCache[slotID] or {}
        for _, location in ipairs(locations) do
            local physicalItemLink = location.physicalItemLink or location.itemLink
            local variants = variantCache[slotID][physicalItemLink]
            if not variants then
                variants = self:BuildItemVariants(physicalItemLink, slotID, self.setCode)
                variantCache[slotID][physicalItemLink] = variants
            end

            if #variants == 0 then
                tinsert(expanded, location)
            else
                for _, variant in ipairs(variants) do
                    self.itemsCache[variant.itemLink] = variant.itemTable
                    self:CalculateItemScore(variant.itemLink)

                    local variantLocation = CopyLocation(location)
                    variantLocation.physicalItemLink = physicalItemLink
                    variantLocation.physicalKey = PhysicalKey(variantLocation)
                    variantLocation.itemLink = variant.itemLink
                    variantLocation.variant = variant
                    variantLocation.requiresModification = variant.requiresModification
                    tinsert(expanded, variantLocation)
                end
            end
        end
        expandedBySlot[slotID] = expanded
    end

    self.itemListBySlot = expandedBySlot
end

local function HasCapContribution(self, itemTable)
    for statCode, capList in pairs(self.Utopia or {}) do
        if self:IsStatCapped(capList) and (itemTable.totalBonus[statCode] or 0) > 0 then
            return true
        end
    end
    return false
end

local function SameArmorFamily(itemTable, classArmorType)
    local subType = itemTable and itemTable.itemSubType
    if subType ~= "Cloth" and subType ~= "Leather" and subType ~= "Mail" and subType ~= "Plate" then
        return true
    end
    return subType == classArmorType
end

local function Dominates(self, betterLocation, worseLocation, slotID)
    if PhysicalKey(betterLocation) == PhysicalKey(worseLocation) then
        return false
    end
    if ConstraintSignature(betterLocation) ~= ConstraintSignature(worseLocation) then
        return false
    end

    local better = self:GetCachedItem(betterLocation.itemLink)
    local worse = self:GetCachedItem(worseLocation.itemLink)
    if not better or not worse or better.itemEquipLoc ~= worse.itemEquipLoc then
        return false
    end

    local betterScore = self:GetItemScore(better.itemLink, self.setCode, self.ignoreCapsForCalculation)
    local worseScore = self:GetItemScore(worse.itemLink, self.setCode, self.ignoreCapsForCalculation)
    if betterScore <= worseScore then
        return false
    end

    for statCode, capList in pairs(self.Utopia or {}) do
        if self:IsStatCapped(capList) and (better.totalBonus[statCode] or 0) < (worse.totalBonus[statCode] or 0) then
            return false
        end
    end

    if (slotID == 12 or slotID == 14 or slotID == 17) and betterLocation.physicalKey == worseLocation.physicalKey then
        return false
    end
    return true
end

-- Variant-aware replacement for the legacy reducer. It expands before score/dominance pruning so
-- an ungemmed or poorly enchanted physical item is judged by its useful variants, not its current
-- modification state.
function TopFit:ReduceItemList()
    for slotID, forceID in pairs(self.db.profile.sets[self.setCode].forced) do
        if self.itemListBySlot[slotID] then
            for index = #self.itemListBySlot[slotID], 1, -1 do
                local itemTable = self:GetCachedItem(self.itemListBySlot[slotID][index].itemLink)
                if not itemTable or itemTable.itemID ~= forceID then
                    tremove(self.itemListBySlot[slotID], index)
                end
            end
        end
    end

    if self.playerForceTwoHanded then
        if self.itemListBySlot[16] and not self.db.profile.sets[self.setCode].forced[16] then
            for index = #self.itemListBySlot[16], 1, -1 do
                local itemTable = self:GetCachedItem(self.itemListBySlot[16][index].itemLink)
                if not itemTable or itemTable.itemEquipLoc ~= "INVTYPE_2HWEAPON" then
                    tremove(self.itemListBySlot[16], index)
                end
            end
        end
        if self.itemListBySlot[17] and not self.db.profile.sets[self.setCode].forced[17] then
            self.itemListBySlot[17] = {}
        end
    end

    if self.db.profile.sets[self.setCode].forceArmorType then
        local armorType = self:GetClassArmorType()
        if armorType then
            for slotID, itemList in pairs(self.itemListBySlot) do
                if not self.db.profile.sets[self.setCode].forced[slotID] then
                    for index = #itemList, 1, -1 do
                        local itemTable = self:GetCachedItem(itemList[index].itemLink)
                        if not SameArmorFamily(itemTable, armorType) then
                            tremove(itemList, index)
                        end
                    end
                end
            end
        end
    end

    self:ExpandOwnedItemVariants()

    for slotID, itemList in pairs(self.itemListBySlot) do
        for index = #itemList, 1, -1 do
            local itemTable = self:GetCachedItem(itemList[index].itemLink)
            local score = self:GetItemScore(itemList[index].itemLink, self.setCode, self.ignoreCapsForCalculation)
            if not itemTable then
                tremove(itemList, index)
            elseif score <= 0 and not self.db.profile.sets[self.setCode].forced[slotID] then
                if not HasCapContribution(self, itemTable) then
                    tremove(itemList, index)
                end
            end
        end
    end

    for slotID, itemList in pairs(self.itemListBySlot) do
        if #itemList > 1 then
            for index = #itemList, 1, -1 do
                local dominatedPhysicalKeys = {}
                local needed = (slotID == 12 or slotID == 14 or slotID == 17) and 2 or 1

                for compareIndex = 1, #itemList do
                    if index ~= compareIndex and Dominates(self, itemList[compareIndex], itemList[index], slotID) then
                        dominatedPhysicalKeys[PhysicalKey(itemList[compareIndex])] = true
                    end
                end

                local count = 0
                for _ in pairs(dominatedPhysicalKeys) do
                    count = count + 1
                end
                if count >= needed then
                    tremove(itemList, index)
                end
            end
        end
    end
end

function TopFit:IsDuplicateItem(currentSlot)
    local currentIndex = self.slotCounters[currentSlot]
    if not currentIndex or currentIndex <= 0 then
        return false
    end

    local current = self.itemListBySlot[currentSlot][currentIndex]
    if not current then
        return false
    end
    local currentKey = PhysicalKey(current)

    for slotID = 1, currentSlot - 1 do
        local selectedIndex = self.slotCounters[slotID]
        if selectedIndex and selectedIndex > 0 then
            local selected = self.itemListBySlot[slotID][selectedIndex]
            if selected and PhysicalKey(selected) == currentKey then
                return true
            end
        end
    end
    return false
end

local function AddVariantConstraints(state, location)
    local variant = location and location.variant
    if not variant then
        return
    end

    for color in pairs(state.colors) do
        state.colors[color] = state.colors[color] + ((variant.gemColorCounts and variant.gemColorCounts[color]) or 0)
    end
    for group, count in pairs(variant.uniqueGemCounts or {}) do
        state.uniqueCounts[group] = (state.uniqueCounts[group] or 0) + count
    end
    for _, metaGem in ipairs(variant.metaGems or {}) do
        tinsert(state.metaGems, metaGem)
    end
    state.hasUnknownGem = state.hasUnknownGem or variant.hasUnknownGem
end

function TopFit:GetVariantUniqueLimits()
    if self.variantUniqueLimits then
        return self.variantUniqueLimits
    end

    self.variantUniqueLimits = {}
    for _, gem in ipairs(self.gemCandidates or {}) do
        if gem.uniqueGroup and gem.uniqueLimit then
            self.variantUniqueLimits[gem.uniqueGroup] = gem.uniqueLimit
        end
    end
    return self.variantUniqueLimits
end

function TopFit:GetVariantConstraintState(locations)
    local state = {
        colors = { RED = 0, YELLOW = 0, BLUE = 0 },
        uniqueCounts = {},
        uniqueLimits = self:GetVariantUniqueLimits(),
        metaGems = {},
        hasUnknownGem = false,
    }

    for _, location in pairs(locations or {}) do
        AddVariantConstraints(state, location)
    end
    return state
end

function TopFit:IsVariantConstraintStateValid(state, requireActiveMeta)
    for group, count in pairs(state.uniqueCounts or {}) do
        local limit = state.uniqueLimits and state.uniqueLimits[group]
        if limit and count > limit then
            return false, "unique-limit"
        end
    end

    if requireActiveMeta and not state.hasUnknownGem then
        for _, metaGem in ipairs(state.metaGems or {}) do
            if not self.IsMetaConditionSatisfied(metaGem, state.colors or {}) then
                return false, "meta-inactive"
            end
        end
    end

    return true
end

function TopFit:GetSelectedVariantLocations(currentSlot)
    local locations = {}
    for slotID = 1, currentSlot or 20 do
        local selectedIndex = self.slotCounters and self.slotCounters[slotID]
        if selectedIndex and selectedIndex > 0 and self.itemListBySlot[slotID] then
            local location = self.itemListBySlot[slotID][selectedIndex]
            if location then
                tinsert(locations, location)
            end
        end
    end
    return locations
end

function TopFit:WouldViolateVariantUniqueLimits(itemsAlreadyChosen, candidate)
    local locations = {}
    for _, location in pairs(itemsAlreadyChosen or {}) do
        if location then
            tinsert(locations, location)
        end
    end
    if candidate then
        tinsert(locations, candidate)
    end

    local state = self:GetVariantConstraintState(locations)
    local valid, reason = self:IsVariantConstraintStateValid(state, false)
    return not valid and reason == "unique-limit"
end

function TopFit:IsCapsReached(currentSlot)
    if not LegacyIsCapsReached(self, currentSlot) then
        return false
    end

    local state = self:GetVariantConstraintState(self:GetSelectedVariantLocations(currentSlot))
    local valid = self:IsVariantConstraintStateValid(state, true)
    return valid
end

function TopFit:IsCapsUnreachable(currentSlot)
    local state = self:GetVariantConstraintState(self:GetSelectedVariantLocations(currentSlot))
    local valid, reason = self:IsVariantConstraintStateValid(state, false)
    if not valid and reason == "unique-limit" then
        return true
    end
    return LegacyIsCapsUnreachable(self, currentSlot)
end

function TopFit:CalculateBestInSlot(itemsAlreadyChosen, insert, requestedSlotID, setCode, assertion)
    setCode = setCode or self.setCode
    local bestBySlot = {}
    local itemListBySlot = self.itemListBySlot or self:GetEquippableItems()

    for slotID, locations in pairs(itemListBySlot) do
        if not requestedSlotID or requestedSlotID == slotID then
            local best
            local bestScore
            for _, location in ipairs(locations) do
                local itemTable = self:GetCachedItem(location.itemLink)
                local score = itemTable and self:GetItemScore(location.itemLink, setCode, self.ignoreCapsForCalculation)
                local levelAllowed = itemTable and (itemTable.itemMinLevel <= self.characterLevel or location.isVirtual)
                local allowed = not assertion or assertion(location)

                local used = false
                if itemsAlreadyChosen then
                    local key = PhysicalKey(location)
                    for _, chosen in pairs(itemsAlreadyChosen) do
                        if chosen and PhysicalKey(chosen) == key then
                            used = true
                            break
                        end
                    end
                end

                local violatesUniqueLimit = self:WouldViolateVariantUniqueLimits(itemsAlreadyChosen, location)

                if
                    itemTable
                    and levelAllowed
                    and allowed
                    and not used
                    and not violatesUniqueLimit
                    and (not bestScore or score > bestScore)
                then
                    best = location
                    bestScore = score
                end
            end

            if best then
                bestBySlot[slotID] = { locationTable = best }
                if itemsAlreadyChosen and insert then
                    tinsert(itemsAlreadyChosen, best)
                end
            end
        end
    end

    if requestedSlotID then
        return bestBySlot[requestedSlotID] and bestBySlot[requestedSlotID].locationTable or nil
    end
    return bestBySlot
end

function TopFit:IsVariantCombinationValid(combination)
    local state = self:GetVariantConstraintState((combination and combination.items) or {})
    return self:IsVariantConstraintStateValid(state, true)
end

function TopFit:SaveCurrentCombination()
    local previousBest = self.bestCombination
    local previousMaxScore = self.maxScore

    LegacySaveCurrentCombination(self)

    if self.bestCombination ~= previousBest then
        local valid = self:IsVariantCombinationValid(self.bestCombination)
        if not valid then
            self.bestCombination = previousBest
            self.maxScore = previousMaxScore
        end
    end
end

function TopFit:EquipRecommendedItems()
    for _, recommendation in pairs(self.itemRecommendations or {}) do
        local location = recommendation.locationTable
        if location and location.requiresModification then
            self:Print(
                "The recommended set includes gem or enchant changes. TopFit will not auto-equip it until those changes are applied."
            )
            self.ProgressFrame:StoppedCalculation()
            self.isBlocked = false
            self.ignoreCapsForCalculation = nil
            if #self.workSetList > 0 then
                self:CalculateSets()
            end
            return
        end
    end

    return LegacyEquipRecommendedItems(self)
end

TopFit.LegacyCalculateBestInSlot = LegacyCalculateBestInSlot
