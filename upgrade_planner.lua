-- Source-aware prospective upgrade evaluation.
--
-- Current-phase source data discovers candidates. Each shortlisted candidate is injected as exactly
-- one hypothetical physical item and receives a full rerun through the existing gear/gem/enchant
-- optimizer. The owned baseline is rerun first so gains are always measured against the same set
-- configuration and cap rules.

local LegacyGetEquippableItems = TopFit.GetEquippableItems
local LegacyEquipRecommendedItems = TopFit.EquipRecommendedItems
local LegacyAbortCalculations = TopFit.AbortCalculations

TopFit.upgradeWeightedCandidatesPerSlot = 3
TopFit.upgradeCapCandidatesPerSlot = 1
TopFit.upgradeCandidateLimit = 45
TopFit.upgradeResultLimit = 20
TopFit.upgradeItemLoadPasses = 4
TopFit.upgradeItemLoadFrames = 20

local DIFFICULTY_TEXT = {
    [0] = nil,
    [1] = "10-player",
    [2] = "25-player",
    [3] = "10/25-player",
}

local function CopyArray(input)
    local result = {}
    for index, value in ipairs(input or {}) do
        result[index] = value
    end
    return result
end

local function Contains(list, wanted)
    for _, value in ipairs(list or {}) do
        if value == wanted then
            return true
        end
    end
    return false
end

local function IsActiveCapList(capList)
    for _, cap in ipairs(capList or {}) do
        if cap.active then
            return true
        end
    end
    return false
end

local function ResultSort(left, right)
    if left.gain ~= right.gain then
        return left.gain > right.gain
    end
    if left.gainPercent ~= right.gainPercent then
        return left.gainPercent > right.gainPercent
    end
    return left.candidate.itemID < right.candidate.itemID
end

function TopFit:GetUpgradeSources(itemID)
    local result = {}
    for _, encoded in ipairs((self.upgradeSourceData and self.upgradeSourceData[itemID]) or {}) do
        local instance = self.upgradeSourceInstances and self.upgradeSourceInstances[encoded[1]]
        local encounter = instance and instance.encounters and instance.encounters[encoded[2]]
        if instance and encounter and (instance.minChromiePhase or 1) <= (self.chromiecraftPhase or 1) then
            tinsert(result, {
                type = "raid",
                instanceID = encoded[1],
                encounterIndex = encoded[2],
                zone = instance.name,
                encounter = encounter,
                difficultyMask = encoded[3] or 0,
                difficulty = DIFFICULTY_TEXT[encoded[3] or 0],
                minChromiePhase = instance.minChromiePhase or 1,
            })
        end
    end
    return result
end

function TopFit.GetUpgradeSourceText(sources)
    local parts = {}
    local seen = {}
    for _, source in ipairs(sources or {}) do
        local text = source.zone .. " - " .. source.encounter
        if source.difficulty then
            text = text .. " (" .. source.difficulty .. ")"
        end
        if not seen[text] then
            seen[text] = true
            tinsert(parts, text)
        end
    end
    return table.concat(parts, "; ")
end

function TopFit:RequestUpgradeItemInfo()
    for itemID in pairs(self.upgradeSourceData or {}) do
        if #self:GetUpgradeSources(itemID) > 0 and GetItemInfo then
            GetItemInfo(itemID)
        end
    end
end

function TopFit:ResolveUpgradeSourceCandidates()
    local resolved = {}
    local unresolved = 0

    for itemID in pairs(self.upgradeSourceData or {}) do
        local sources = self:GetUpgradeSources(itemID)
        if #sources > 0 then
            local _, itemLink = GetItemInfo(itemID)
            if not itemLink then
                unresolved = unresolved + 1
            elseif not IsEquippableItem or IsEquippableItem(itemLink) then
                local itemTable = self:PrimeOwnedItemCache(itemLink)
                if
                    itemTable
                    and itemTable.itemEquipLoc
                    and (not itemTable.itemMinLevel or itemTable.itemMinLevel <= UnitLevel("player"))
                then
                    local eligibleSlots = self:GetEquipLocationsByInvType(itemTable.itemEquipLoc) or {}
                    if #eligibleSlots > 0 then
                        tinsert(resolved, {
                            itemID = itemID,
                            itemLink = itemLink,
                            itemTable = itemTable,
                            eligibleSlots = CopyArray(eligibleSlots),
                            sources = sources,
                            sourceText = self.GetUpgradeSourceText(sources),
                        })
                    end
                end
            end
        end
    end

    table.sort(resolved, function(left, right)
        return left.itemID < right.itemID
    end)
    return resolved, unresolved
end

function TopFit:ScoreUpgradeCandidate(candidate)
    candidate.quickBySlot = {}
    candidate.quickScore = 0

    for _, slotID in ipairs(candidate.eligibleSlots or {}) do
        local metrics = {
            score = 0,
            capValues = {},
        }
        local variants = self:BuildItemVariants(candidate.itemLink, slotID, self.setCode)
        if #variants == 0 then
            variants = {
                {
                    itemLink = candidate.itemLink,
                    itemTable = candidate.itemTable,
                },
            }
        end

        for _, variant in ipairs(variants) do
            self.itemsCache[variant.itemLink] = variant.itemTable
            self:CalculateItemScore(variant.itemLink)

            local score = self:GetItemScore(variant.itemLink, self.setCode, self.ignoreCapsForCalculation) or 0
            if score > metrics.score then
                metrics.score = score
            end
            for stat, capList in pairs(self.Utopia or {}) do
                if IsActiveCapList(capList) then
                    metrics.capValues[stat] =
                        math.max(metrics.capValues[stat] or 0, variant.itemTable.totalBonus[stat] or 0)
                end
            end
        end

        candidate.quickBySlot[slotID] = metrics
        candidate.quickScore = math.max(candidate.quickScore, metrics.score)
    end

    return candidate
end

local function AddMarked(marked, candidate, protected)
    local current = marked[candidate.itemID]
    if not current then
        marked[candidate.itemID] = {
            candidate = candidate,
            protected = protected and true or false,
        }
    elseif protected then
        current.protected = true
    end
end

function TopFit:SelectUpgradeCandidateQueue(candidates)
    local bySlot = {}
    for _, candidate in ipairs(candidates or {}) do
        self:ScoreUpgradeCandidate(candidate)
        for _, slotID in ipairs(candidate.eligibleSlots or {}) do
            bySlot[slotID] = bySlot[slotID] or {}
            tinsert(bySlot[slotID], candidate)
        end
    end

    local marked = {}
    for slotID, slotCandidates in pairs(bySlot) do
        table.sort(slotCandidates, function(left, right)
            local leftScore = (left.quickBySlot[slotID] and left.quickBySlot[slotID].score) or 0
            local rightScore = (right.quickBySlot[slotID] and right.quickBySlot[slotID].score) or 0
            if leftScore == rightScore then
                return left.itemID < right.itemID
            end
            return leftScore > rightScore
        end)

        for index = 1, math.min(self.upgradeWeightedCandidatesPerSlot, #slotCandidates) do
            AddMarked(marked, slotCandidates[index], false)
        end

        for stat, capList in pairs(self.Utopia or {}) do
            if IsActiveCapList(capList) then
                local capCandidates = CopyArray(slotCandidates)
                table.sort(capCandidates, function(left, right)
                    local leftValue =
                        (left.quickBySlot[slotID] and left.quickBySlot[slotID].capValues[stat]) or 0
                    local rightValue =
                        (right.quickBySlot[slotID] and right.quickBySlot[slotID].capValues[stat]) or 0
                    if leftValue == rightValue then
                        return left.itemID < right.itemID
                    end
                    return leftValue > rightValue
                end)
                for index = 1, math.min(self.upgradeCapCandidatesPerSlot, #capCandidates) do
                    local capValue =
                        (capCandidates[index].quickBySlot[slotID].capValues[stat]) or 0
                    if capValue > 0 then
                        AddMarked(marked, capCandidates[index], true)
                    end
                end
            end
        end
    end

    local protected = {}
    local weighted = {}
    for _, value in pairs(marked) do
        if value.protected then
            tinsert(protected, value.candidate)
        else
            tinsert(weighted, value.candidate)
        end
    end

    local function quickSort(left, right)
        if left.quickScore == right.quickScore then
            return left.itemID < right.itemID
        end
        return left.quickScore > right.quickScore
    end
    table.sort(protected, quickSort)
    table.sort(weighted, quickSort)

    local result = {}
    for _, candidate in ipairs(protected) do
        tinsert(result, candidate)
    end
    for _, candidate in ipairs(weighted) do
        if #result >= self.upgradeCandidateLimit then
            break
        end
        tinsert(result, candidate)
    end

    return result
end

function TopFit:CombinationUsesUpgradeCandidate(combination, itemID)
    for _, location in pairs((combination and combination.items) or {}) do
        if location.upgradeCandidateID == itemID then
            return true
        end
    end
    return false
end

function TopFit:RecordUpgradeResult(candidate, combination, baselineScore)
    if not candidate or not combination or not self:CombinationUsesUpgradeCandidate(combination, candidate.itemID) then
        return nil
    end

    local gain = (combination.totalScore or 0) - (baselineScore or 0)
    if gain <= 0 then
        return nil
    end

    local result = {
        candidate = candidate,
        combination = combination,
        score = combination.totalScore,
        gain = gain,
        gainPercent = baselineScore and baselineScore ~= 0 and (gain / baselineScore) * 100 or 0,
        sources = candidate.sources,
        sourceText = candidate.sourceText,
    }

    self.upgradeResultsBySet = self.upgradeResultsBySet or {}
    local results = self.upgradeResultsBySet[self.setCode] or {}
    tinsert(results, result)
    table.sort(results, ResultSort)
    while #results > self.upgradeResultLimit do
        tremove(results)
    end
    self.upgradeResultsBySet[self.setCode] = results
    return result
end

function TopFit:GetUpgradeResults(setCode)
    self.upgradeResultsBySet = self.upgradeResultsBySet or {}
    return self.upgradeResultsBySet[setCode or self.setCode] or {}
end

local function RemoveConfiguredVirtualItems(itemListBySlot)
    for _, itemList in pairs(itemListBySlot or {}) do
        for index = #itemList, 1, -1 do
            if itemList[index].source == "virtual" then
                tremove(itemList, index)
            end
        end
    end
end

local function AddProspectiveCandidate(self, itemListBySlot, candidate, requestedSlotID)
    if not candidate then
        return
    end

    for _, slotID in ipairs(candidate.eligibleSlots or {}) do
        if (not requestedSlotID or requestedSlotID == slotID) and itemListBySlot[slotID] then
            tinsert(itemListBySlot[slotID], {
                itemLink = candidate.itemLink,
                physicalItemLink = candidate.itemLink,
                source = "upgrade",
                isVirtual = true,
                upgradeCandidateID = candidate.itemID,
                upgradeSources = candidate.sources,
            })
        end
    end
end

function TopFit:GetEquippableItems(requestedSlotID)
    local result = LegacyGetEquippableItems(self, requestedSlotID)
    local scan = self.upgradeScan
    if not scan then
        return result
    end

    if requestedSlotID then
        local wrapped = { [requestedSlotID] = result or {} }
        RemoveConfiguredVirtualItems(wrapped)
        AddProspectiveCandidate(self, wrapped, scan.activeCandidate, requestedSlotID)
        return wrapped[requestedSlotID]
    end

    RemoveConfiguredVirtualItems(result)
    AddProspectiveCandidate(self, result, scan.activeCandidate)
    return result
end

function TopFit:EnsureUpgradePlannerFrame()
    if self.upgradePlannerFrame or not CreateFrame then
        return self.upgradePlannerFrame
    end

    self.upgradePlannerFrame = CreateFrame("Frame")
    self.upgradePlannerFrame:SetScript("OnUpdate", function()
        TopFit:UpgradePlannerOnUpdate()
    end)
    return self.upgradePlannerFrame
end

function TopFit:NotifyUpgradeScanChanged()
    if self.RefreshUpgradePlannerPlugin then
        self:RefreshUpgradePlannerPlugin()
    end
end

function TopFit:ScheduleUpgradeRun(kind, candidate)
    local scan = self.upgradeScan
    if not scan then
        return
    end
    scan.pendingRun = {
        kind = kind,
        candidate = candidate,
    }
end

function TopFit:BeginUpgradeRun(kind, candidate)
    local scan = self.upgradeScan
    if not scan then
        return
    end

    scan.pendingRun = nil
    scan.currentKind = kind
    scan.activeCandidate = candidate
    scan.stage = kind == "baseline" and "baseline" or "evaluating"

    self.setCode = scan.setCode
    self.Utopia = self.db.profile.sets[scan.setCode].caps
    self.ignoreCapsForCalculation = false
    self.silentCalculation = true
    self.isBlocked = true

    self:collectItems()
    self:CalculateRecommendations()
    self:NotifyUpgradeScanChanged()
end

local function CopyEntries(entries)
    local result = {}
    for index, entry in ipairs(entries or {}) do
        result[index] = entry
    end
    return result
end

function TopFit:CompleteUpgradeRun()
    local scan = self.upgradeScan
    if not scan then
        return false
    end

    local combination = self.bestCombination
    if scan.currentKind == "baseline" then
        if not combination then
            self:FinishUpgradeScan(true, "No owned baseline could be calculated.")
            return true
        end

        scan.baselineCombination = combination
        scan.baselineScore = combination.totalScore or 0
        scan.baselineAlternatives = CopyEntries(self:GetAlternativeEntries(scan.setCode))
        scan.candidates = self:SelectUpgradeCandidateQueue(scan.resolvedCandidates or {})
        scan.index = 0
    elseif scan.activeCandidate and combination then
        self:RecordUpgradeResult(scan.activeCandidate, combination, scan.baselineScore)
    end

    self.isBlocked = false
    self.ignoreCapsForCalculation = nil
    scan.activeCandidate = nil
    scan.currentKind = nil

    scan.index = scan.index + 1
    local nextCandidate = scan.candidates and scan.candidates[scan.index]
    if nextCandidate then
        self:ScheduleUpgradeRun("candidate", nextCandidate)
    else
        self:FinishUpgradeScan(false)
    end

    self:NotifyUpgradeScanChanged()
    return true
end

function TopFit:EquipRecommendedItems()
    if self.upgradeScan then
        self:CompleteUpgradeRun()
        return
    end
    return LegacyEquipRecommendedItems(self)
end

function TopFit:AbortCalculations()
    if self.upgradeScan then
        self.upgradeScan.cancelled = true
    end
    return LegacyAbortCalculations(self)
end

function TopFit:FinishUpgradeScan(cancelled, errorText)
    local scan = self.upgradeScan
    if not scan then
        return
    end

    if scan.baselineAlternatives then
        self.topCombinationsBySet = self.topCombinationsBySet or {}
        self.topCombinationsBySet[scan.setCode] = scan.baselineAlternatives
        self.selectedAlternativeBySet = self.selectedAlternativeBySet or {}
        self.selectedAlternativeBySet[scan.setCode] = 1
    end

    if scan.baselineCombination then
        self.bestCombination = scan.baselineCombination
        self.maxScore = scan.baselineScore
        self:SetRecommendationsFromCombination(scan.baselineCombination)
    end

    self.setCode = scan.setCode
    self.silentCalculation = scan.savedSilentCalculation
    self.ignoreCapsForCalculation = nil
    self.isBlocked = false
    self.abortCalculation = nil

    self.lastUpgradeScanBySet = self.lastUpgradeScanBySet or {}
    self.lastUpgradeScanBySet[scan.setCode] = {
        cancelled = cancelled and true or false,
        error = errorText,
        evaluated = math.max((scan.index or 1) - 1, 0),
        shortlisted = #(scan.candidates or {}),
        unresolved = scan.unresolved or 0,
        baselineScore = scan.baselineScore,
    }

    self.upgradeScan = nil
    if self.ProgressFrame then
        self.ProgressFrame:StoppedCalculation()
        if scan.baselineCombination then
            self.ProgressFrame:SetCurrentCombination(scan.baselineCombination)
        end
        if self.RefreshAlternativeControls then
            self:RefreshAlternativeControls(false)
        end
    end

    if self.upgradePlannerFrame then
        self.upgradePlannerFrame:SetScript("OnUpdate", nil)
    end
    self:NotifyUpgradeScanChanged()
end

function TopFit:UpgradePlannerOnUpdate()
    local scan = self.upgradeScan
    if not scan then
        if self.upgradePlannerFrame then
            self.upgradePlannerFrame:SetScript("OnUpdate", nil)
        end
        return
    end

    if scan.cancelled and not self.isBlocked then
        self:FinishUpgradeScan(true)
        return
    end

    if scan.pendingRun and not self.isBlocked then
        local pending = scan.pendingRun
        self:BeginUpgradeRun(pending.kind, pending.candidate)
        return
    end

    if scan.stage ~= "loading" then
        return
    end

    scan.frameCountdown = (scan.frameCountdown or 0) - 1
    if scan.frameCountdown > 0 then
        return
    end

    scan.loadPass = (scan.loadPass or 0) + 1
    scan.resolvedCandidates, scan.unresolved = self:ResolveUpgradeSourceCandidates()
    if scan.unresolved > 0 and scan.loadPass < self.upgradeItemLoadPasses then
        self:RequestUpgradeItemInfo()
        scan.frameCountdown = self.upgradeItemLoadFrames
        self:NotifyUpgradeScanChanged()
        return
    end

    self:ScheduleUpgradeRun("baseline")
    scan.stage = "ready"
    self:NotifyUpgradeScanChanged()
end

function TopFit:StartUpgradeScan(setCode)
    if self.isBlocked or self.upgradeScan then
        return false, "busy"
    end
    if not setCode or not self.db.profile.sets[setCode] then
        return false, "invalid-set"
    end

    self.upgradeResultsBySet = self.upgradeResultsBySet or {}
    self.upgradeResultsBySet[setCode] = {}
    self.setCode = setCode
    self.Utopia = self.db.profile.sets[setCode].caps
    self.ignoreCapsForCalculation = false

    self.upgradeScan = {
        setCode = setCode,
        stage = "loading",
        loadPass = 0,
        frameCountdown = 1,
        resolvedCandidates = {},
        unresolved = 0,
        candidates = {},
        index = 0,
        savedSilentCalculation = self.silentCalculation,
    }

    self:RequestUpgradeItemInfo()
    local frame = self:EnsureUpgradePlannerFrame()
    if frame then
        frame:SetScript("OnUpdate", function()
            TopFit:UpgradePlannerOnUpdate()
        end)
    else
        self.upgradeScan.loadPass = self.upgradeItemLoadPasses
        self:UpgradePlannerOnUpdate()
    end
    self:NotifyUpgradeScanChanged()
    return true
end

function TopFit:GetUpgradeScanProgress()
    local scan = self.upgradeScan
    if not scan then
        return nil
    end

    if scan.stage == "loading" or scan.stage == "ready" then
        return {
            stage = scan.stage,
            resolved = #(scan.resolvedCandidates or {}),
            unresolved = scan.unresolved or 0,
        }
    end

    if scan.stage == "baseline" then
        return {
            stage = "baseline",
        }
    end

    return {
        stage = "evaluating",
        current = math.min(scan.index, #(scan.candidates or {})),
        total = #(scan.candidates or {}),
        candidate = scan.activeCandidate,
    }
end
