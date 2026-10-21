local FTS = FillTypeSelector
local passed = 0
local function test(name, body)
    broadcasts, warnings, replies = {}, {}, {}
    g_currentMission.money = 0
    g_currentMission.missionInfo = {helperBuyFertilizer = true, helperManureSource = 1, helperSlurrySource = 1}
    body()
    passed = passed + 1
    print("PASS " .. name)
end
local function spec(vehicle) return vehicle[FTS.SPEC_TABLE_NAME] end
local function same(list, expected)
    assert(#list == #expected, "expected " .. #expected .. " entries, got " .. #list)
    for i, value in ipairs(expected) do assert(list[i] == value, "entry " .. i .. " differs") end
end
local function display(vehicle) return vehicle.fillUnits[1].fillTypeToDisplay end
local function startAI(vehicle) vehicle.aiActive, vehicle.fieldWorkActive = true, true end
local function combine(...)
    local vehicles = {...}
    for _, vehicle in ipairs(vehicles) do vehicle.rootVehicle, vehicle.childVehicles = vehicles[1], vehicles end
end

test("candidates are the spray fill types of the own tank", function()
    same(spec(mockSprayer({fillTypes = {"LIME", "FERTILIZER"}})).candidates, {FillType.FERTILIZER, FillType.LIME})
    same(spec(mockSprayer({fillTypes = {"HERBICIDE", "LIQUIDFERTILIZER"}})).candidates,
        {FillType.LIQUIDFERTILIZER, FillType.HERBICIDE})
    same(spec(mockSprayer({fillTypes = {"MANURE", "LIME"}, manure = true})).candidates, {FillType.LIME, FillType.MANURE})
    -- The game always picks slurry or digestate itself; seeds are not a spray type.
    same(spec(mockSprayer({fillTypes = {"LIQUIDMANURE", "DIGESTATE"}, slurry = true})).candidates, {})
    same(spec(mockSprayer({fillTypes = {"SEEDS", "FERTILIZER"}})).candidates, {FillType.FERTILIZER})
end)

test("implements with one possible type get no key", function()
    for _, types in ipairs({{"FERTILIZER"}, {"LIME"}, {"LIQUIDMANURE", "DIGESTATE"}}) do
        local events = registerInput(mockSprayer({fillTypes = types}))
        assert(next(events) == nil)
    end
end)

test("Y and Shift+Y are used when nothing else needs them", function()
    local sprayer = mockSprayer()
    local events = registerInput(sprayer)
    local forward, back = events[InputAction.TOGGLE_SEEDS], events[InputAction.TOGGLE_SEEDS_BACK]
    assert(forward ~= nil and back ~= nil and events[InputAction.FTS_SELECT_FILL_TYPE] == nil)
    assert(forward.text == "Select fertilizer" and forward.active and forward.priority == GS_PRIO_HIGH)
    assert(back.visible == false and back.active)
end)

test("a seeder with several seeds keeps Y and the Mod uses its own key", function()
    local seeder = mockSprayer({seeds = {1, 2}})
    local events = registerInput(seeder)
    assert(events[InputAction.FTS_SELECT_FILL_TYPE] ~= nil)
    assert(events[InputAction.TOGGLE_SEEDS] == nil and events[InputAction.TOGGLE_SEEDS_BACK] == nil)
    -- A seeder with one seed registers no seed key in the game, so Y stays free.
    events = registerInput(mockSprayer({seeds = {1}}))
    assert(events[InputAction.TOGGLE_SEEDS] ~= nil)
end)

test("the combination decides: a multi-seed seeder elsewhere or Precision Farming takes Y", function()
    local tractor, spreader = mockSprayer({fillTypes = {}}), mockSprayer()
    local seeder = mockSprayer({fillTypes = {"SEEDS"}, seeds = {1, 2, 3}})
    combine(tractor, seeder, spreader)
    assert(registerInput(spreader)[InputAction.FTS_SELECT_FILL_TYPE] ~= nil)
    local pf = mockSprayer({specNames = {"fillUnit", "sprayer", "FS25_precisionFarming.extendedSprayer"}})
    assert(registerInput(pf)[InputAction.FTS_SELECT_FILL_TYPE] ~= nil)
end)

test("missing own action falls back to no key instead of a conflict", function()
    local action = InputAction.FTS_SELECT_FILL_TYPE
    InputAction.FTS_SELECT_FILL_TYPE = nil
    assert(next(registerInput(mockSprayer({seeds = {1, 2}}))) == nil)
    InputAction.FTS_SELECT_FILL_TYPE = action
end)

test("two selectable implements: only the selected one listens", function()
    local front, rear = mockSprayer({fillTypes = {"LIQUIDFERTILIZER", "HERBICIDE"}}), mockSprayer()
    combine(front, rear)
    assert(next(registerInput(front, false)) == nil)
    assert(registerInput(rear, true)[InputAction.TOGGLE_SEEDS] ~= nil)
end)

test("cycling forward, backward and wrapping", function()
    local sprayer = mockSprayer()
    local events = registerInput(sprayer)
    press(events[InputAction.TOGGLE_SEEDS]); assert(FTS.getSelectedFillType(sprayer) == FillType.FERTILIZER)
    assert(events[InputAction.TOGGLE_SEEDS].text == "Select fertilizer (Solid Fertilizer)")
    press(events[InputAction.TOGGLE_SEEDS]); assert(FTS.getSelectedFillType(sprayer) == FillType.LIME)
    assert(events[InputAction.TOGGLE_SEEDS].text == "Select fertilizer (Lime)")
    press(events[InputAction.TOGGLE_SEEDS]); assert(FTS.getSelectedFillType(sprayer) == FillType.FERTILIZER)
    press(events[InputAction.TOGGLE_SEEDS_BACK]); assert(FTS.getSelectedFillType(sprayer) == FillType.LIME)
    local other = mockSprayer()
    press(registerInput(other)[InputAction.TOGGLE_SEEDS_BACK]); assert(FTS.getSelectedFillType(other) == FillType.LIME)
    local seeder = mockSprayer({seeds = {1, 2}})
    local own = registerInput(seeder)[InputAction.FTS_SELECT_FILL_TYPE]
    press(own); press(own); assert(FTS.getSelectedFillType(seeder) == FillType.LIME)
end)

test("only candidates are accepted", function()
    local sprayer = mockSprayer()
    assert(not FTS.setSelectedFillType(sprayer, FillType.HERBICIDE))
    assert(not FTS.setSelectedFillType(sprayer, FillType.SEEDS))
    assert(FTS.getSelectedFillType(sprayer) == nil and #broadcasts == 0)
    assert(FTS.setSelectedFillType(sprayer, FillType.LIME) and #broadcasts == 1)
end)

test("the empty tank shows the selection and the content when filled", function()
    local sprayer = mockSprayer()
    assert(display(sprayer) == FillType.UNKNOWN)
    FTS.setSelectedFillType(sprayer, FillType.LIME)
    assert(display(sprayer) == FillType.LIME and sprayer.fillUnits[1].fillTypeToDisplayIsPersistent)
    sprayer:addFill(500, "FERTILIZER")
    assert(display(sprayer) == FillType.UNKNOWN, "content must be shown, not the selection")
    sprayer:addFill(-500, "FERTILIZER")
    assert(display(sprayer) == FillType.LIME, "selection must come back once empty")
end)

test("no selection leaves the display alone", function()
    local sprayer = mockSprayer()
    sprayer:addFill(10, "LIME"); sprayer:addFill(-10, "LIME")
    assert(display(sprayer) == FillType.UNKNOWN)
    -- A single-type tank already shows its type in the game; the Mod does not mark it.
    assert(display(mockSprayer({fillTypes = {"LIME"}})) == FillType.UNKNOWN)
end)

test("locked while the tank holds something", function()
    local sprayer = mockSprayer()
    local events = registerInput(sprayer)
    FTS.setSelectedFillType(sprayer, FillType.LIME)
    sprayer:addFill(100, "FERTILIZER")
    assert(events[InputAction.TOGGLE_SEEDS].active == false and events[InputAction.TOGGLE_SEEDS_BACK].active == false)
    press(events[InputAction.TOGGLE_SEEDS]); assert(FTS.getSelectedFillType(sprayer) == FillType.LIME)
    assert(FTS.getEffectiveFillType(sprayer) == nil)
    startAI(sprayer)
    local fillType = sprayer:getExternalFill(FillType.FERTILIZER, 1000)
    assert(fillType == FillType.FERTILIZER, "content decides while the tank is not empty")
    sprayer:addFill(-100, "FERTILIZER")
    assert(events[InputAction.TOGGLE_SEEDS].active == true)
end)

test("an attached tank with content is used before the selection", function()
    local sprayer = mockSprayer()
    FTS.setSelectedFillType(sprayer, FillType.LIME)
    local frontTank = mockSprayer({withMod = false})
    frontTank.fillUnits[1].fillType, frontTank.fillUnits[1].fillLevel = FillType.FERTILIZER, 800
    sprayer.spec_sprayer.fillTypeSources[FillType.FERTILIZER] = {{vehicle = frontTank, fillUnitIndex = 1}}
    assert(FTS.getEffectiveFillType(sprayer) == nil)
    frontTank.fillUnits[1].fillLevel = 0
    assert(FTS.getEffectiveFillType(sprayer) == FillType.LIME)
end)

test("AI buys the selected type, lime included", function()
    local sprayer = mockSprayer()
    startAI(sprayer)
    assert(sprayer:getIsSprayerExternallyFilled())
    local fillType, usage = sprayer:getExternalFill(FillType.UNKNOWN, 1000)
    assert(fillType == FillType.FERTILIZER and usage == 1, "without selection the game picks fertilizer")
    FTS.setSelectedFillType(sprayer, FillType.LIME)
    fillType, usage = sprayer:getExternalFill(FillType.UNKNOWN, 1000)
    assert(fillType == FillType.LIME and usage == 1)
    assert(g_currentMission.money == -6, "server pays for both refills")
    local liquid = mockSprayer({fillTypes = {"LIQUIDFERTILIZER", "HERBICIDE"}})
    startAI(liquid)
    assert(liquid:getExternalFill(FillType.UNKNOWN, 1000) == FillType.LIQUIDFERTILIZER)
    FTS.setSelectedFillType(liquid, FillType.HERBICIDE)
    assert(liquid:getExternalFill(FillType.UNKNOWN, 1000) == FillType.HERBICIDE)
end)

test("a lime-only spreader buys lime without any key", function()
    local vanilla = mockSprayer({fillTypes = {"LIME"}, withMod = false})
    startAI(vanilla)
    assert(vanilla:getExternalFill(FillType.UNKNOWN, 1000) == FillType.UNKNOWN, "base game finds nothing to buy")
    local limeOnly = mockSprayer({fillTypes = {"LIME"}})
    startAI(limeOnly)
    assert(limeOnly:getExternalFill(FillType.UNKNOWN, 1000) == FillType.LIME)
    same(limeOnly.aiRanges, {FillType.LIME})
    -- Single types the game already picks stay with the game.
    local fertilizerOnly = mockSprayer({fillTypes = {"FERTILIZER"}})
    assert(spec(fertilizerOnly).defaultFillType == nil and #fertilizerOnly.aiRanges == 0)
end)

test("the fertilizer refill setting is respected", function()
    local sprayer = mockSprayer()
    startAI(sprayer)
    FTS.setSelectedFillType(sprayer, FillType.LIME)
    g_currentMission.missionInfo.helperBuyFertilizer = false
    assert(not sprayer:getIsSprayerExternallyFilled())
    assert(sprayer:getExternalFill(FillType.UNKNOWN, 1000) == FillType.UNKNOWN)
    assert(g_currentMission.money == 0)
    sprayer.aiActive = false
    g_currentMission.missionInfo.helperBuyFertilizer = true
    assert(not sprayer:getIsSprayerExternallyFilled(), "only AI workers refill")
end)

test("manure spreader with lime: lime follows the fertilizer setting", function()
    local spreader = mockSprayer({fillTypes = {"MANURE", "LIME"}, manure = true})
    startAI(spreader)
    local info = g_currentMission.missionInfo
    assert(not spreader:getIsSprayerExternallyFilled(), "base game: manure setting off")
    FTS.setSelectedFillType(spreader, FillType.LIME)
    assert(spreader:getIsSprayerExternallyFilled())
    assert(spreader:getExternalFill(FillType.UNKNOWN, 1000) == FillType.LIME)
    local sprayer = spreader.spec_sprayer
    assert(sprayer.isManureSpreader and not sprayer.isFertilizerSprayer and not sprayer.isSlurryTanker)
    info.helperBuyFertilizer, info.helperManureSource = false, 2
    assert(not spreader:getIsSprayerExternallyFilled())
    FTS.setSelectedFillType(spreader, FillType.MANURE)
    assert(spreader:getIsSprayerExternallyFilled(), "manure keeps the manure setting")
    assert(spreader:getExternalFill(FillType.UNKNOWN, 1000) == FillType.MANURE)
end)

test("spray types limited to a fill type follow the selection", function()
    local fertilizerSetup = {fillTypes = {"fertilizer", "unknown"}}
    local limeSetup = {fillTypes = {"lime"}}
    local sprayer = mockSprayer({sprayTypes = {fertilizerSetup, limeSetup}})
    assert(sprayer:getActiveSprayType() == fertilizerSetup, "base game uses the fertilizer setup when empty")
    FTS.setSelectedFillType(sprayer, FillType.LIME)
    assert(sprayer:getActiveSprayType() == limeSetup)
    FTS.setSelectedFillType(sprayer, FillType.FERTILIZER)
    assert(sprayer:getActiveSprayType() == fertilizerSetup)
    FTS.setSelectedFillType(sprayer, FillType.LIME)
    limeSetup.hasRequiredFoldingConfiguration = false
    assert(sprayer:getActiveSprayType() == nil, "other checks in the chain still apply")
    limeSetup.hasRequiredFoldingConfiguration = nil
    sprayer:addFill(50, "FERTILIZER")
    assert(sprayer:getActiveSprayType() == fertilizerSetup, "content decides once filled")
end)

test("AI ground requirements follow the selection on the server only", function()
    local server = mockSprayer()
    FTS.setSelectedFillType(server, FillType.LIME)
    FTS.setSelectedFillType(server, FillType.LIME)
    same(server.aiRanges, {FillType.LIME})
    server:addFill(10, "FERTILIZER"); server:addFill(-10, "FERTILIZER")
    same(server.aiRanges, {FillType.LIME, FillType.LIME})
    local client = mockSprayer({isServer = false})
    FTS.setSelectedFillType(client, FillType.LIME, true)
    assert(#client.aiRanges == 0)
end)

test("event round trip: client request, server check and broadcast", function()
    local server, client = mockSprayer(), mockSprayer({isServer = false})
    local packet = {}
    FTSSelectFillTypeEvent.new(server, FillType.LIME):writeStream(packet, serverConnection)
    FTSSelectFillTypeEvent.emptyNew():readStream(packet, clientConnection)
    assert(FTS.getSelectedFillType(server) == FillType.LIME)
    assert(#broadcasts == 1 and broadcasts[1].object == server and broadcasts[1].ignore == nil
        and broadcasts[1].sendLocal == false)
    packet = {}
    broadcasts[1].event:writeStream(packet, clientConnection)
    packet[1] = client
    FTSSelectFillTypeEvent.emptyNew():readStream(packet, serverConnection)
    assert(FTS.getSelectedFillType(client) == FillType.LIME and #broadcasts == 1, "clients do not echo")
    packet = {server, FillType.HERBICIDE}
    FTSSelectFillTypeEvent.emptyNew():readStream(packet, clientConnection)
    assert(FTS.getSelectedFillType(server) == FillType.LIME and #broadcasts == 1, "invalid choice is rejected")
    assert(#replies == 1 and replies[1].event.fillType == FillType.LIME, "sender gets the current value")
    server.synchronized = false
    FTSSelectFillTypeEvent.emptyNew():readStream({server, FillType.FERTILIZER}, clientConnection)
    assert(FTS.getSelectedFillType(server) == FillType.LIME)
end)

test("server rejects requests from another farm, with content or during AI work, and corrects the sender", function()
    local server = mockSprayer()
    FTS.setSelectedFillType(server, FillType.FERTILIZER)
    broadcasts = {}
    local function request(connection, fillType)
        FTSSelectFillTypeEvent.emptyNew():readStream({server, fillType}, connection)
    end
    request(otherFarmConnection, FillType.LIME)
    assert(FTS.getSelectedFillType(server) == FillType.FERTILIZER and #broadcasts == 0, "other farm")
    assert(#replies == 1 and replies[1].connection == otherFarmConnection
        and replies[1].event.fillType == FillType.FERTILIZER)
    server:addFill(100, "FERTILIZER")
    request(clientConnection, FillType.LIME)
    assert(FTS.getSelectedFillType(server) == FillType.FERTILIZER and #broadcasts == 0 and #replies == 2, "tank not empty")
    server:addFill(-100, "FERTILIZER")
    server.aiActive = true
    request(clientConnection, FillType.LIME)
    assert(FTS.getSelectedFillType(server) == FillType.FERTILIZER and #broadcasts == 0 and #replies == 3, "AI working")
    server.aiActive = false
    request(clientConnection, FillType.HERBICIDE)
    assert(#broadcasts == 0 and #replies == 4, "not a candidate")
    request(clientConnection, FillType.LIME)
    assert(FTS.getSelectedFillType(server) == FillType.LIME and #broadcasts == 1 and #replies == 4)
    -- The rejected client receives the server value and reverts its optimistic change.
    local client = mockSprayer({isServer = false})
    FTS.setSelectedFillType(client, FillType.LIME, true)
    local packet = {}
    replies[1].event:writeStream(packet, otherFarmConnection)
    packet[1] = client
    FTSSelectFillTypeEvent.emptyNew():readStream(packet, serverConnection)
    assert(FTS.getSelectedFillType(client) == FillType.FERTILIZER and display(client) == FillType.FERTILIZER)
end)

test("joining client receives the selection", function()
    local server, client = mockSprayer(), mockSprayer({isServer = false})
    FTS.setSelectedFillType(server, FillType.LIME)
    local stream = {}
    server:raise("onWriteStream", stream, clientConnection)
    client:raise("onReadStream", stream, serverConnection)
    assert(#stream == 0 and FTS.getSelectedFillType(client) == FillType.LIME and display(client) == FillType.LIME)
    local empty = mockSprayer()
    stream = {}
    empty:raise("onWriteStream", stream, clientConnection)
    assert(stream[1] == FillType.UNKNOWN)
    client:raise("onReadStream", stream, serverConnection)
    assert(FTS.getSelectedFillType(client) == nil and display(client) == FillType.UNKNOWN)
end)

test("save and load by fill type name; unknown names are ignored", function()
    local saved, xml = mockSprayer(), mockXML()
    local key = "vehicles.vehicle(0)." .. FTS.SPEC_NAME
    FTS.saveToXMLFile(saved, xml, key)
    assert(next(xml.values) == nil, "nothing is saved without a selection")
    FTS.setSelectedFillType(saved, FillType.LIME)
    FTS.saveToXMLFile(saved, xml, key)
    assert(xml.values[key .. "#fillType"] == "LIME")
    local loaded = mockSprayer({savegame = {xmlFile = xml, key = "vehicles.vehicle(0)"}})
    assert(FTS.getSelectedFillType(loaded) == FillType.LIME and display(loaded) == FillType.LIME)
    for _, name in ipairs({"NOT_A_FILLTYPE", "HERBICIDE"}) do
        xml.values[key .. "#fillType"] = name
        assert(FTS.getSelectedFillType(mockSprayer({savegame = {xmlFile = xml, key = "vehicles.vehicle(0)"}})) == nil)
    end
    assert(savegamePaths["vehicles.vehicle(?)." .. FTS.SPEC_NAME .. "#fillType"] == nil)
    FTS.initSpecialization()
    assert(savegamePaths["vehicles.vehicle(?)." .. FTS.SPEC_NAME .. "#fillType"] == XMLValueType.STRING)
end)

test("registration adds the specialization once to sprayer types only", function()
    local sprayerType = {specializations = {FillUnit, Sprayer}, specializationsByName = {}}
    local trailerType = {specializations = {FillUnit}, specializationsByName = {}}
    local calls = {}
    local manager
    manager = {typeName = "vehicle", types = {sprayer = sprayerType, trailer = trailerType},
        addSpecialization = function(_, typeName, specName)
            manager.types[typeName].specializationsByName[specName] = true
            table.insert(calls, typeName .. "/" .. specName)
        end}
    TypeManager.validateTypes(manager); TypeManager.validateTypes(manager)
    same(calls, {"sprayer/" .. FTS.SPEC_NAME})
    manager.typeName = "placeable"
    sprayerType.specializationsByName = {}
    TypeManager.validateTypes(manager)
    assert(#calls == 1)
    manager.typeName = "vehicle"
    g_modIsLoaded[g_currentModName] = false
    TypeManager.validateTypes(manager)
    g_modIsLoaded[g_currentModName] = true
    assert(#calls == 1, "inactive Mod adds nothing")
end)

test("missing game functions disable the Mod with one warning", function()
    local original = Sprayer.getExternalFill
    Sprayer.getExternalFill = nil
    local calls = 0
    local manager = {typeName = "vehicle", types = {sprayer = {specializations = {FillUnit, Sprayer}, specializationsByName = {}}},
        addSpecialization = function() calls = calls + 1 end}
    TypeManager.validateTypes(manager)
    assert(calls == 0 and #warnings == 1 and warnings[1]:find("Sprayer.getExternalFill", 1, true))
    Sprayer.getExternalFill = original
end)

print(string.format("%d behavioral tests passed", passed))
