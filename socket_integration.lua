-- Hydrate item-cache records with generated socket metadata without touching the legacy scanner.

local LegacyGetItemInfoTable = TopFit.GetItemInfoTable

function TopFit:GetItemInfoTable(item)
    local itemTable = LegacyGetItemInfoTable(self, item)
    if not itemTable then
        return nil
    end

    local _, _, _, itemLevel = GetItemInfo(item)
    itemTable.itemLevel = itemLevel or itemTable.itemLevel
    self:AttachSocketMetadata(itemTable, itemTable.itemID)

    return itemTable
end
