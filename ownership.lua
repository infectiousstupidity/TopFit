-- Owned-item source handling.
--
-- Bags and equipped items are live at all times. Bank contents are only queryable while the
-- bank is open, so TopFit stores a character-local snapshot of equippable bank items and reuses
-- it between bank visits.

local LegacyOnInitialize = TopFit.OnInitialize
local LegacyFrameOnEvent = TopFit.FrameOnEvent
local LegacyGetItemInfoTable = TopFit.GetItemInfoTable

local function InsertOnce(list, value)
    for _, existing in pairs(list) do
        if existing == value then
            return
        end
    end
    tinsert(list, value)
end

local function BankContainer()
    return BANK_CONTAINER or -1
end

local function ItemIDFromLink(itemLink)
    if not itemLink then
        return nil
    end
    return tonumber(string.match(itemLink, "item:(%d+)"))
end

local function ItemCacheKey(itemLink)
    if not itemLink then
        return nil
    end

    local itemID = string.match(itemLink, "item:(%d+)")
    if not itemID then
        return nil
    end

    local enchantID = string.match(itemLink, "item:%d+:(%d+)") or "0"
    local g1, g2, g3, g4 = string.match(itemLink, "item:%d+:%d+:(%d+):(%d+):(%d+):(%d+)")
    return string.format("%s:%s:%s:%s:%s:%s", itemID, enchantID, g1 or "0", g2 or "0", g3 or "0", g4 or "0")
end

local function AddEligibleSlot(availableSlots, itemID, slotID)
    if not itemID then
        return
    end

    availableSlots[itemID] = availableSlots[itemID] or {}
    InsertOnce(availableSlots[itemID], slotID)
end

local function AddOwnedCandidate(itemListBySlot, eligibleSlots, candidate)
    for _, slotID in pairs(eligibleSlots or {}) do
        if itemListBySlot[slotID] then
            tinsert(itemListBySlot[slotID], {
                itemLink = candidate.itemLink,
                isUnboundBoE = candidate.isUnboundBoE and true or false,
                isVirtual = candidate.isVirtual and true or false,
                source = candidate.source,
                bag = candidate.bag,
                slot = candidate.slot,
            })
        end
    end
end

function TopFit:EnsureBankSnapshot()
    self.db.char = self.db.char or {}
    self.db.char.bankSnapshot = self.db.char.bankSnapshot or {
        scanned = false,
        items = {},
    }
    self.db.char.bankSnapshot.items = self.db.char.bankSnapshot.items or {}
    return self.db.char.bankSnapshot
end

function TopFit.OwnedLocationKey(source, bag, slot)
    return tostring(source or "unknown") .. ":" .. tostring(bag or "") .. ":" .. tostring(slot or "")
end

function TopFit:MergeBankSnapshotEntry(items, itemLink, bag, slot, isUnboundBoE, equipSlot)
    local key = self.OwnedLocationKey("bank", bag, slot)
    local entry = items[key]

    if not entry then
        entry = {
            itemLink = itemLink,
            isUnboundBoE = isUnboundBoE and true or false,
            source = "bank",
            bag = bag,
            slot = slot,
            eligibleSlots = {},
        }
        items[key] = entry
    end

    entry.eligibleSlots[equipSlot] = true
    return entry
end

function TopFit:IsUnboundBoEInContainer(bag, slot)
    local bindText = _G["ITEM_BIND_ON_EQUIP"]
    if not bindText or not self.scanTooltip then
        return false
    end

    self.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    self.scanTooltip:SetBagItem(bag, slot)

    local isUnboundBoE = false
    for i = 1, self.scanTooltip:NumLines() do
        local leftLine = _G["TFScanTooltipTextLeft" .. i]
        local lineText = leftLine and leftLine:GetText()
        if lineText and string.find(lineText, bindText, 1, true) then
            isUnboundBoE = true
            break
        end
    end

    self.scanTooltip:Hide()
    return isUnboundBoE
end

function TopFit:GetItemInfoTable(item)
    local cacheKey = type(item) == "string" and ItemCacheKey(item) or nil
    local persistedCache = TopFit.db and TopFit.db.global and TopFit.db.global.itemCache

    if cacheKey and persistedCache and persistedCache[cacheKey] then
        return persistedCache[cacheKey]
    end

    return LegacyGetItemInfoTable(self, item)
end

function TopFit:PrimeOwnedItemCache(itemLink)
    if self.itemsCache[itemLink] then
        return self.itemsCache[itemLink]
    end

    local itemTable = self:GetItemInfoTable(itemLink)
    if not itemTable then
        return nil
    end

    self.itemsCache[itemLink] = itemTable
    self:CalculateItemScore(itemLink)
    return itemTable
end

function TopFit:RefreshBankSnapshot()
    if not self.isBankOpen then
        return false
    end

    local snapshot = self:EnsureBankSnapshot()
    local items = {}

    for _, equipSlot in pairs(self.slots) do
        local available = {}
        GetInventoryItemsForSlot(equipSlot, available)

        for location in pairs(available) do
            local _, bank, bags, slot, bag = EquipmentManager_UnpackLocation(location)
            if bank and slot and slot > 0 then
                local container = bags and bag or BankContainer()
                local itemLink = GetContainerItemLink(container, slot)

                if itemLink then
                    self:MergeBankSnapshotEntry(
                        items,
                        itemLink,
                        container,
                        slot,
                        self:IsUnboundBoEInContainer(container, slot),
                        equipSlot
                    )
                    self:PrimeOwnedItemCache(itemLink)
                end
            end
        end
    end

    snapshot.items = items
    snapshot.scanned = true

    local count = 0
    for _ in pairs(items) do
        count = count + 1
    end
    self:Debug("Bank snapshot updated with " .. count .. " equippable item(s).")
    return true
end

function TopFit:AddBankSnapshotItems(itemListBySlot)
    local snapshot = self:EnsureBankSnapshot()
    if not snapshot.scanned then
        return
    end

    for _, entry in pairs(snapshot.items) do
        if self:PrimeOwnedItemCache(entry.itemLink) then
            local eligibleSlots = {}
            for slotID, eligible in pairs(entry.eligibleSlots or {}) do
                if eligible then
                    tinsert(eligibleSlots, slotID)
                end
            end

            AddOwnedCandidate(itemListBySlot, eligibleSlots, entry)
        end
    end
end

function TopFit:WarnIfBankSnapshotMissing()
    local snapshot = self:EnsureBankSnapshot()
    if snapshot.scanned or self.warnedAboutMissingBankSnapshot then
        return
    end

    self.warnedAboutMissingBankSnapshot = true
    self:Print(
        "Bank items are not included yet. Open your bank once and TopFit will remember its equippable contents."
    )
end

function TopFit:GetRecommendationEquipBlockers(recommendations)
    recommendations = recommendations or self.itemRecommendations

    local blockers = {
        virtual = 0,
        bank = 0,
        unboundBoE = 0,
    }

    for _, recommendation in pairs(recommendations or {}) do
        local location = recommendation.locationTable or recommendation

        if location.isVirtual or location.source == "virtual" then
            blockers.virtual = blockers.virtual + 1
        end
        if location.source == "bank" then
            blockers.bank = blockers.bank + 1
        end
        if location.isUnboundBoE then
            blockers.unboundBoE = blockers.unboundBoE + 1
        end
    end

    return blockers
end

-- Replace the legacy inventory-source collector without changing the optimizer itself. This fixes
-- the 3.3.5 GetInventoryItemsForSlot contract (the API fills a caller-provided table) and adds the
-- persisted bank snapshot while preserving the original heirloom and virtual-item behavior.
function TopFit:GetEquippableItems(requestedSlotID)
    local itemListBySlot = {}
    local availableSlots = {}

    for _, slotID in pairs(self.slots) do
        itemListBySlot[slotID] = {}

        local slotAvailableItems = {}
        GetInventoryItemsForSlot(slotID, slotAvailableItems)
        for _, itemID in pairs(slotAvailableItems) do
            AddEligibleSlot(availableSlots, itemID, slotID)
        end

        if self.heirloomInfo.isPlateWearer and (slotID == 3 or slotID == 5) and UnitLevel("player") < 40 then
            for _, itemID in pairs(self.heirloomInfo.plateHeirlooms[slotID]) do
                AddEligibleSlot(availableSlots, itemID, slotID)
            end
        end

        if self.heirloomInfo.isMailWearer and (slotID == 3 or slotID == 5) and UnitLevel("player") < 40 then
            for _, itemID in pairs(self.heirloomInfo.mailHeirlooms[slotID]) do
                AddEligibleSlot(availableSlots, itemID, slotID)
            end
        end
    end

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local itemLink = GetContainerItemLink(bag, slot)
            local eligibleSlots = availableSlots[ItemIDFromLink(itemLink)]

            if itemLink and eligibleSlots then
                AddOwnedCandidate(itemListBySlot, eligibleSlots, {
                    itemLink = itemLink,
                    isUnboundBoE = self:IsUnboundBoEInContainer(bag, slot),
                    source = "bags",
                    bag = bag,
                    slot = slot,
                })
            end
        end
    end

    for _, invSlot in pairs(self.slots) do
        local itemLink = GetInventoryItemLink("player", invSlot)
        local eligibleSlots = availableSlots[ItemIDFromLink(itemLink)]

        if itemLink and eligibleSlots then
            AddOwnedCandidate(itemListBySlot, eligibleSlots, {
                itemLink = itemLink,
                source = "equipped",
                slot = invSlot,
            })
        end
    end

    self:AddBankSnapshotItems(itemListBySlot)
    if not self.silentCalculation then
        self:WarnIfBankSnapshotMissing()
    end

    if
        self.setCode
        and self.db.profile.sets[self.setCode].virtualItems
        and not self.db.profile.sets[self.setCode].skipVirtualItems
    then
        for _, itemLink in pairs(self.db.profile.sets[self.setCode].virtualItems) do
            local item = self:GetCachedItem(itemLink)
            if item then
                AddOwnedCandidate(itemListBySlot, self:GetEquipLocationsByInvType(item.itemEquipLoc), {
                    itemLink = itemLink,
                    isVirtual = true,
                    source = "virtual",
                })
            end
        end
    end

    if requestedSlotID then
        return itemListBySlot[requestedSlotID]
    end
    return itemListBySlot
end

-- Risky owned items remain valid recommendations. Safety is applied only when TopFit is about to
-- equip the result, so the optimizer does not artificially downgrade banked or unbound BoE gear.
function TopFit:EquipRecommendedItems()
    local blockers = self:GetRecommendationEquipBlockers(self.itemRecommendations)

    if blockers.virtual > 0 or blockers.bank > 0 or blockers.unboundBoE > 0 then
        if blockers.virtual > 0 then
            self:Print("The recommended set contains virtual items, so TopFit will not auto-equip it.")
        end
        if blockers.bank > 0 then
            self:Print(
                "The recommended set contains "
                    .. blockers.bank
                    .. " banked item(s). Withdraw them and recalculate before using auto-equip."
            )
        end
        if blockers.unboundBoE > 0 then
            self:Print(
                "The recommended set contains "
                    .. blockers.unboundBoE
                    .. " unbound Bind-on-Equip item(s). TopFit will not auto-equip them because doing so may bind them."
            )
        end

        self.ProgressFrame:StoppedCalculation()
        self.isBlocked = false
        self.ignoreCapsForCalculation = nil

        if #self.workSetList > 0 then
            self:CalculateSets()
        end
        return
    end

    self.updateEquipmentCounter = 10000
    self.equipRetries = 0
    self.updateFrame:SetScript("OnUpdate", self.onUpdateForEquipment)
end

function TopFit:FrameOnEvent(event, ...)
    if event == "BANKFRAME_OPENED" then
        TopFit.isBankOpen = true
        TopFit:RefreshBankSnapshot()
        return
    elseif event == "BANKFRAME_CLOSED" then
        TopFit.isBankOpen = false
        return
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        if TopFit.isBankOpen then
            TopFit:RefreshBankSnapshot()
        end
        return
    elseif event == "BAG_UPDATE" then
        local bag = ...
        if TopFit.isBankOpen and bag and (bag == BankContainer() or bag > 4) then
            TopFit:RefreshBankSnapshot()
            return
        end
    end

    return LegacyFrameOnEvent(self, event, ...)
end

function TopFit:OnInitialize()
    LegacyOnInitialize(self)
    TopFit:EnsureBankSnapshot()

    TopFit.eventFrame:RegisterEvent("BANKFRAME_OPENED")
    TopFit.eventFrame:RegisterEvent("BANKFRAME_CLOSED")
    TopFit.eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    TopFit.eventFrame:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
end
