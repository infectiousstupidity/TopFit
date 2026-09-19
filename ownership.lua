-- Owned-item source handling.
--
-- WoW exposes the live character bags/equipment at all times, but bank contents are only
-- queryable while the bank is open. TopFit therefore stores a character-local snapshot of
-- equippable bank items and reuses it while away from the bank.

local function BankContainer()
    return BANK_CONTAINER or -1
end

function TopFit:EnsureBankSnapshot()
    TopFit.db.char = TopFit.db.char or {}
    TopFit.db.char.bankSnapshot = TopFit.db.char.bankSnapshot or {
        scanned = false,
        items = {},
    }
    TopFit.db.char.bankSnapshot.items = TopFit.db.char.bankSnapshot.items or {}
    return TopFit.db.char.bankSnapshot
end

function TopFit:OwnedLocationKey(source, bag, slot)
    return tostring(source or "unknown") .. ":" .. tostring(bag or "") .. ":" .. tostring(slot or "")
end

function TopFit:MergeBankSnapshotEntry(items, itemLink, bag, slot, isBoE, equipSlot)
    local key = TopFit:OwnedLocationKey("bank", bag, slot)
    local entry = items[key]
    if not entry then
        entry = {
            itemLink = itemLink,
            isBoE = isBoE and true or false,
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
    if not bindText or not TopFit.scanTooltip then return false end

    TopFit.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    TopFit.scanTooltip:SetBagItem(bag, slot)

    local isBoE = false
    for i = 1, TopFit.scanTooltip:NumLines() do
        local leftLine = _G["TFScanTooltipTextLeft" .. i]
        local lineText = leftLine and leftLine:GetText()
        if lineText and string.find(lineText, bindText, 1, true) then
            isBoE = true
            break
        end
    end

    TopFit.scanTooltip:Hide()
    return isBoE
end

function TopFit:RefreshBankSnapshot()
    if not TopFit.isBankOpen then return false end

    local snapshot = TopFit:EnsureBankSnapshot()
    local items = {}

    for _, equipSlot in pairs(TopFit.slots) do
        local available = {}
        GetInventoryItemsForSlot(equipSlot, available)

        for location in pairs(available) do
            local _, bank, bags, slot, bag = EquipmentManager_UnpackLocation(location)
            if bank and slot and slot > 0 then
                local container = bags and bag or BankContainer()
                local itemLink = GetContainerItemLink(container, slot)
                if itemLink then
                    TopFit:MergeBankSnapshotEntry(
                        items,
                        itemLink,
                        container,
                        slot,
                        TopFit:IsUnboundBoEInContainer(container, slot),
                        equipSlot
                    )
                    TopFit:UpdateCache(itemLink)
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
    TopFit:Debug("Bank snapshot updated with " .. count .. " equippable item(s).")
    return true
end

function TopFit:AddBankSnapshotItems(itemListBySlot)
    local snapshot = TopFit:EnsureBankSnapshot()
    if not snapshot.scanned then return end

    for _, entry in pairs(snapshot.items) do
        TopFit:UpdateCache(entry.itemLink)
        for slotID, eligible in pairs(entry.eligibleSlots or {}) do
            if eligible and itemListBySlot[slotID] then
                tinsert(itemListBySlot[slotID], {
                    itemLink = entry.itemLink,
                    isBoE = entry.isBoE,
                    source = "bank",
                    bag = entry.bag,
                    slot = entry.slot,
                })
            end
        end
    end
end

function TopFit:WarnIfBankSnapshotMissing()
    local snapshot = TopFit:EnsureBankSnapshot()
    if snapshot.scanned or TopFit.warnedAboutMissingBankSnapshot then return end

    TopFit.warnedAboutMissingBankSnapshot = true
    TopFit:Print("Bank items are not included yet. Open your bank once and TopFit will remember its equippable contents.")
end

function TopFit:GetRecommendationEquipBlockers(recommendations)
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
        if location.isBoE then
            blockers.unboundBoE = blockers.unboundBoE + 1
        end
    end

    return blockers
end
