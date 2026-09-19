-- Keep a small, diverse frontier of complete gear configurations.
--
-- The legacy search only retains its single current maximum. This adapter forces the existing
-- SaveCurrentCombination implementation to materialize each cap-valid candidate, records a bounded
-- Top-N frontier, then restores the legacy best/max state so the recursive search behaves exactly
-- as before.

local LegacySaveCurrentCombination = TopFit.SaveCurrentCombination
local LegacyCalculateRecommendations = TopFit.CalculateRecommendations

TopFit.alternativeResultLimit = 5
TopFit.alternativeVariantsPerGearSet = 2

local SYMMETRIC_SLOT_GROUPS = {
    { 11, 12 }, -- rings
    { 13, 14 }, -- trinkets
}

local function CopyArray(input)
    local result = {}
    for index, value in ipairs(input or {}) do
        result[index] = value
    end
    return result
end

local function CopySlotCounters(input)
    local result = {}
    for slotID, value in pairs(input or {}) do
        result[slotID] = value
    end
    return result
end

local function LocationOutcomeKey(location)
    if not location then
        return "-"
    end
    return tostring(location.itemLink or location.physicalItemLink or "-")
end

local function LocationGearKey(self, location)
    if not location then
        return "-"
    end

    local lookupLink = location.physicalItemLink or location.itemLink
    local itemTable = lookupLink and self:GetCachedItem(lookupLink)
    if not itemTable and location.itemLink then
        itemTable = self:GetCachedItem(location.itemLink)
    end

    return tostring((itemTable and itemTable.itemID) or lookupLink or "-")
end

local function AddRegularSlotSignature(parts, slotID, key)
    parts[#parts + 1] = tostring(slotID) .. "=" .. key
end

local function BuildSignature(self, combination, keyFunction)
    local items = (combination and combination.items) or {}
    local parts = {}
    local symmetric = {}

    for _, group in ipairs(SYMMETRIC_SLOT_GROUPS) do
        for _, slotID in ipairs(group) do
            symmetric[slotID] = true
        end
    end

    for slotID = 1, 20 do
        if not symmetric[slotID] then
            AddRegularSlotSignature(parts, slotID, keyFunction(self, items[slotID]))
        end
    end

    for _, group in ipairs(SYMMETRIC_SLOT_GROUPS) do
        local keys = {}
        for _, slotID in ipairs(group) do
            keys[#keys + 1] = keyFunction(self, items[slotID])
        end
        table.sort(keys)
        parts[#parts + 1] = table.concat(group, ",") .. "=" .. table.concat(keys, "|")
    end

    return table.concat(parts, ";")
end

local function OutcomeKeyAdapter(_, location)
    return LocationOutcomeKey(location)
end

function TopFit:GetCombinationOutcomeSignature(combination)
    return BuildSignature(self, combination, OutcomeKeyAdapter)
end

function TopFit:GetCombinationGearSignature(combination)
    return BuildSignature(self, combination, LocationGearKey)
end

function TopFit.GetCombinationChangeSummary(combination)
    local summary = {
        gearChanges = 0,
        modifications = 0,
        banked = 0,
        unboundBoE = 0,
        virtual = 0,
    }

    for slotID, location in pairs((combination and combination.items) or {}) do
        if location.source ~= "equipped" or location.slot ~= slotID then
            summary.gearChanges = summary.gearChanges + 1
        end
        if location.requiresModification then
            summary.modifications = summary.modifications + 1
        end
        if location.source == "bank" then
            summary.banked = summary.banked + 1
        end
        if location.isUnboundBoE then
            summary.unboundBoE = summary.unboundBoE + 1
        end
        if location.isVirtual or location.source == "virtual" then
            summary.virtual = summary.virtual + 1
        end
    end

    summary.totalChanges = summary.gearChanges + summary.modifications
    summary.manualBlockers = summary.modifications + summary.banked + summary.unboundBoE + summary.virtual
    return summary
end

local function EntrySort(left, right)
    if left.score ~= right.score then
        return left.score > right.score
    end
    if left.changes.totalChanges ~= right.changes.totalChanges then
        return left.changes.totalChanges < right.changes.totalChanges
    end
    if left.changes.manualBlockers ~= right.changes.manualBlockers then
        return left.changes.manualBlockers < right.changes.manualBlockers
    end
    return left.signature < right.signature
end

local function PreferDuplicate(newEntry, oldEntry)
    if newEntry.score ~= oldEntry.score then
        return newEntry.score > oldEntry.score
    end
    if newEntry.changes.manualBlockers ~= oldEntry.changes.manualBlockers then
        return newEntry.changes.manualBlockers < oldEntry.changes.manualBlockers
    end
    return newEntry.changes.totalChanges < oldEntry.changes.totalChanges
end

function TopFit:ResetAlternativeResults(setCode)
    self.topCombinationsBySet = self.topCombinationsBySet or {}
    self.selectedAlternativeBySet = self.selectedAlternativeBySet or {}

    if setCode then
        self.topCombinationsBySet[setCode] = {}
        self.selectedAlternativeBySet[setCode] = 1
    end
end

function TopFit:GetAlternativeEntries(setCode)
    self.topCombinationsBySet = self.topCombinationsBySet or {}
    return self.topCombinationsBySet[setCode or self.setCode] or {}
end

function TopFit:ConsiderAlternativeCombination(combination)
    if not combination or not combination.totalScore then
        return
    end

    local setCode = self.setCode
    if not setCode then
        return
    end

    self.topCombinationsBySet = self.topCombinationsBySet or {}
    local entries = self.topCombinationsBySet[setCode] or {}
    local entry = {
        combination = combination,
        score = combination.totalScore,
        signature = self:GetCombinationOutcomeSignature(combination),
        gearSignature = self:GetCombinationGearSignature(combination),
        changes = self.GetCombinationChangeSummary(combination),
    }

    for index, existing in ipairs(entries) do
        if existing.signature == entry.signature then
            if PreferDuplicate(entry, existing) then
                entries[index] = entry
            end
            table.sort(entries, EntrySort)
            self.topCombinationsBySet[setCode] = entries
            return
        end
    end

    entries[#entries + 1] = entry
    table.sort(entries, EntrySort)

    local gearCounts = {}
    local filtered = {}
    for _, candidate in ipairs(entries) do
        local count = gearCounts[candidate.gearSignature] or 0
        if count < self.alternativeVariantsPerGearSet then
            filtered[#filtered + 1] = candidate
            gearCounts[candidate.gearSignature] = count + 1
            if #filtered >= self.alternativeResultLimit then
                break
            end
        end
    end

    self.topCombinationsBySet[setCode] = filtered
end

function TopFit:GetAlternativeCombination(setCode, index)
    local entries = self:GetAlternativeEntries(setCode)
    local entry = entries[index or 1]
    return entry and entry.combination or nil
end

function TopFit:SetRecommendationsFromCombination(combination)
    self.itemRecommendations = {}
    for slotID, location in pairs((combination and combination.items) or {}) do
        self.itemRecommendations[slotID] = {
            locationTable = location,
        }
    end
end

function TopFit:CalculateRecommendations(...)
    self:ResetAlternativeResults(self.setCode)
    return LegacyCalculateRecommendations(self, ...)
end

function TopFit:SaveCurrentCombination()
    local previousBest = self.bestCombination
    local previousMax = self.maxScore
    local previousDebugCounters = CopySlotCounters(self.debugSlotCounters)

    -- Make the existing implementation materialize this cap-valid candidate even when it is not
    -- better than the global maximum. The adapter restores the real maximum immediately after.
    self.bestCombination = nil
    self.maxScore = nil

    LegacySaveCurrentCombination(self)

    local candidate = self.bestCombination
    local candidateDebugCounters = CopySlotCounters(self.debugSlotCounters)

    if candidate then
        self:ConsiderAlternativeCombination(candidate)
    end

    if candidate and (previousMax == nil or candidate.totalScore > previousMax) then
        self.bestCombination = candidate
        self.maxScore = candidate.totalScore
        self.debugSlotCounters = candidateDebugCounters
    else
        self.bestCombination = previousBest
        self.maxScore = previousMax
        self.debugSlotCounters = previousDebugCounters
    end
end

function TopFit:GetAlternativePercentOfBest(setCode, index)
    local entries = self:GetAlternativeEntries(setCode)
    local best = entries[1]
    local selected = entries[index or 1]
    if not best or not selected or best.score == 0 then
        return nil
    end
    return (selected.score / best.score) * 100
end

function TopFit:GetAlternativeIndexes(setCode)
    local entries = self:GetAlternativeEntries(setCode)
    local indexes = {}
    for index = 1, #entries do
        indexes[index] = index
    end
    return CopyArray(indexes)
end
