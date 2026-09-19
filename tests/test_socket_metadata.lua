TopFit = {}
tinsert = table.insert

dofile("data/item_sockets.lua")
dofile("socket_metadata.lua")

local legacyItemInfoCalls = 0
TopFit.GetItemInfoTable = function()
    legacyItemInfoCalls = legacyItemInfoCalls + 1
    return { itemID = 45610 }
end

dofile("socket_integration.lua")

local tests = {}

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertNil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. ": got " .. tostring(value), 2)
    end
end

function tests.knownUlduarHelmetKeepsOriginalSockets()
    local metadata = TopFit.GetItemSocketMetadata(46115)

    assertEqual(#metadata.colors, 2, "socket count")
    assertEqual(metadata.colors[1], "META", "first socket")
    assertEqual(metadata.colors[2], "BLUE", "second socket")
    assertEqual(metadata.socketBonusID, 3314, "socket bonus ID")
end

function tests.knownUlduarGlovesKeepOrderedColors()
    local metadata = TopFit.GetItemSocketMetadata(45928)

    assertEqual(#metadata.colors, 2, "socket count")
    assertEqual(metadata.colors[1], "BLUE", "first socket")
    assertEqual(metadata.colors[2], "RED", "second socket")
    assertEqual(metadata.socketBonusID, 3316, "socket bonus ID")
end

function tests.prismaticMaskDecodesWithoutExpandingGeneratedData()
    local itemID = 999999
    TopFit.itemSocketData[itemID] = 14 + 14 * 16 + 2392 * 4096

    local metadata = TopFit.GetItemSocketMetadata(itemID)

    TopFit.itemSocketData[itemID] = nil
    assertEqual(metadata.colors[1], "PRISMATIC", "first prismatic socket")
    assertEqual(metadata.colors[2], "PRISMATIC", "second prismatic socket")
    assertEqual(metadata.socketBonusID, 2392, "socket bonus ID")
end

function tests.attachHydratesPersistedCacheEntries()
    local item = { itemID = 45610 }

    TopFit:AttachSocketMetadata(item)

    assertEqual(item.baseSocketColors[1], "META", "cached first socket")
    assertEqual(item.baseSocketColors[2], "BLUE", "cached second socket")
    assertEqual(item.socketBonusID, 3313, "cached socket bonus ID")
end

function tests.integrationHydratesItemLevelAndSocketMetadata()
    local oldGetItemInfo = GetItemInfo
    GetItemInfo = function()
        return "Boundless Gaze", "item:45610", 4, 239
    end

    local item = TopFit:GetItemInfoTable("item:45610")

    GetItemInfo = oldGetItemInfo

    assertEqual(legacyItemInfoCalls, 1, "legacy item scanner call count")
    assertEqual(item.itemLevel, 239, "item level")
    assertEqual(item.baseSocketColors[1], "META", "integrated first socket")
    assertEqual(item.baseSocketColors[2], "BLUE", "integrated second socket")
    assertEqual(item.socketBonusID, 3313, "integrated socket bonus ID")
end

function tests.itemsWithoutSocketsGetNoMetadata()
    assertNil(TopFit.GetItemSocketMetadata(25), "unsocketed item metadata")

    local item = { itemID = 25 }
    TopFit:AttachSocketMetadata(item)
    assertEqual(#item.baseSocketColors, 0, "unsocketed color count")
    assertEqual(item.socketBonusID, 0, "unsocketed bonus ID")
end

local names = {}
for name in pairs(tests) do
    table.insert(names, name)
end
table.sort(names)

for _, name in ipairs(names) do
    tests[name]()
    print("ok - " .. name)
end

print(("passed %d socket-metadata tests"):format(#names))
