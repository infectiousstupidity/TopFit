-- Generated item socket metadata lookup helpers.

local SOCKET_COLOR_BY_MASK = {
    [1] = "META",
    [2] = "RED",
    [4] = "YELLOW",
    [8] = "BLUE",
    [14] = "PRISMATIC",
}

local function DecodePackedSocketData(packed)
    local firstMask = packed % 16
    local secondMask = math.floor(packed / 16) % 16
    local thirdMask = math.floor(packed / 256) % 16
    local socketBonusID = math.floor(packed / 4096)
    local colors = {}

    for _, mask in ipairs({ firstMask, secondMask, thirdMask }) do
        if mask ~= 0 then
            local color = SOCKET_COLOR_BY_MASK[mask]
            if not color then
                return nil
            end
            tinsert(colors, color)
        end
    end

    return colors, socketBonusID
end

function TopFit.GetItemSocketMetadata(itemID)
    local numericItemID = tonumber(itemID)
    local packed = numericItemID and TopFit.itemSocketData and TopFit.itemSocketData[numericItemID]
    if not packed then
        return nil
    end

    local colors, socketBonusID = DecodePackedSocketData(packed)
    if not colors then
        return nil
    end

    return {
        colors = colors,
        socketBonusID = socketBonusID,
    }
end

function TopFit:AttachSocketMetadata(itemTable, itemID)
    if not itemTable then
        return nil
    end

    local metadata = self.GetItemSocketMetadata(itemID or itemTable.itemID)
    if metadata then
        itemTable.baseSocketColors = metadata.colors
        itemTable.socketBonusID = metadata.socketBonusID
    else
        itemTable.baseSocketColors = {}
        itemTable.socketBonusID = 0
    end

    return itemTable
end
