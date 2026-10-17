local APD = AnimalProductDistribution
local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("PASS " .. name)
end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function target(storage)
    return {
        free = function() return storage:getFreeCapacity() end,
        add = function(amount)
            local before = storage.amount
            storage:setFillLevel(before + amount)
            return storage.amount - before
        end
    }
end

test("default and invalid modes", function()
    local h = mockHusbandry()
    assert(APD.mode(h, 7) == 0)
    assert(not APD.applyMode(h, 7, 3))
    assert(not APD.applyMode(h, 999, 1))
    assert(APD.mode(h, 7) == 0)
end)
test("distribution conserves product and weights capacity", function()
    local h = mockHusbandry()
    local a, b = mockStorage(0, 100), mockStorage(0, 300)
    local charged = 0
    local amount = APDDistribution.distribute(APD.source(h, 7), {target(a), target(b)}, function(_, liters) charged = charged + liters end)
    near(amount, 100); near(a.amount, 25); near(b.amount, 75)
    near(h.spec_husbandryPallets.pendingLiters[7], 0); near(charged, 100)
end)
test("no receiver retains all stock", function()
    local h = mockHusbandry()
    near(APDDistribution.distribute(APD.source(h, 7), {}, function() error("charged") end), 0)
    near(h.spec_husbandryPallets.pendingLiters[7], 100)
end)
test("full and capacity limited destinations retain overflow", function()
    local h = mockHusbandry()
    local a, b = mockStorage(10, 10), mockStorage(0, 30)
    near(APDDistribution.distribute(APD.source(h, 7), {target(a), target(b)}, function() end), 30)
    near(h.spec_husbandryPallets.pendingLiters[7], 70)
end)
test("partial acceptance refunds unaccepted source", function()
    local h = mockHusbandry()
    local charged = 0
    local t = {free = function() return 100 end, add = function() return 10 end}
    near(APDDistribution.distribute(APD.source(h, 7), {t}, function(_, n) charged = n end), 10)
    near(h.spec_husbandryPallets.pendingLiters[7], 90); near(charged, 10)
end)
test("sale credits once and zero price preserves stock", function()
    local h, money = mockHusbandry(), 0
    local source = APD.source(h, 7)
    APDDistribution.sell(source, 0, function() error("credited") end)
    near(source.available(), 100)
    APDDistribution.sell(source, 1.8, function(value) money = money + value end)
    APDDistribution.sell(source, 1.8, function(value) money = money + value end)
    near(money, 180); near(source.available(), 0)
end)
test("milk adapter handles actual tank amounts", function()
    local h = mockHusbandry()
    h.spec_husbandry = {storage = mockStorage(50, 100)}
    h.spec_husbandryMilk = {hasMilkProduction = true, fillTypes = {4}}
    local source = APD.source(h, 4)
    near(source.take(80), 50); source.put(20); near(source.available(), 20)
    assert(APD.supports(h, 4))
end)
test("spawning hides only managed output and restores it", function()
    local h = mockHusbandry()
    APD.applyMode(h, 7, 2)
    APD.updatePallets(h, function(p)
        assert(p.spec_husbandryPallets.pendingLiters[7] == 0)
        p.spec_husbandryPallets.pendingLiters[8] = 0
    end)
    near(h.spec_husbandryPallets.pendingLiters[7], 100)
    near(h.spec_husbandryPallets.pendingLiters[8], 0)
end)
test("spawner exception restores pending stock", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 1)
    local ok = pcall(APD.updatePallets, h, function() error("spawn failed") end)
    assert(not ok); near(h.spec_husbandryPallets.pendingLiters[7], 100)
end)
test("in-flight callback cannot consume managed output", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 2)
    APD.getPalletCallback(h, function(p, pallet, result, fillType)
        assert(fillType == 7); near(p.spec_husbandryPallets.pendingLiters[7], 0)
        APD.updatePallets(p, function() end)
    end, {}, 0, 7)
    near(h.spec_husbandryPallets.pendingLiters[7], 100)
end)
test("store mode resumes native spawning", function()
    local h = mockHusbandry(); local calls = 0
    h.updatePallets = function() calls = calls + 1 end
    APD.applyMode(h, 7, 1); assert(calls == 0)
    APD.applyMode(h, 7, 0); assert(calls == 1)
end)
test("save and reload uses fill type names", function()
    local h, xml = mockHusbandry(), mockXML()
    APD.applyMode(h, 7, 2)
    APD.saveToXMLFile(h, xml, "barn.apd")
    assert(xml.values["barn.apd.product(0)#fillType"] == "TYPE_7")
    local loaded = mockHusbandry()
    APD.loadFromXMLFile(loaded, xml, "barn.apd", false)
    assert(APD.mode(loaded, 7) == 2 and APD.mode(loaded, 8) == 0)
    local reset = mockHusbandry(); APD.loadFromXMLFile(reset, xml, "barn.apd", true)
    assert(APD.mode(reset, 7) == 0)
end)
test("invalid save values fall back to storing", function()
    local h, xml = mockHusbandry(), mockXML()
    xml:setValue("barn.product(0)#fillType", "TYPE_7"); xml:setValue("barn.product(0)#mode", 999)
    xml:setValue("barn.product(1)#fillType", "UNKNOWN"); xml:setValue("barn.product(1)#mode", 1)
    APD.loadFromXMLFile(h, xml, "barn", false)
    assert(APD.mode(h, 7) == 0)
end)
test("join stream restores individual product modes", function()
    local h, c, stream = mockHusbandry(), mockHusbandry(), {}
    c.isServer = false; APD.applyMode(h, 7, 1); APD.applyMode(h, 8, 2)
    APD.onWriteStream(h, stream, {}); APD.onReadStream(c, stream, {})
    assert(APD.mode(c, 7) == 1 and APD.mode(c, 8) == 2 and #stream == 0)
end)
test("server rejects cross-farm requests and bad modes", function()
    local h = mockHusbandry()
    local connection = {farmId = 2, getIsServer = function() return false end}
    APDModeEvent.new(h, 7, 1):run(connection); assert(APD.mode(h, 7) == 0)
    connection.farmId = 1
    APDModeEvent.new(h, 7, 3):run(connection); assert(APD.mode(h, 7) == 0)
    g_currentMission.allowed = false
    APDModeEvent.new(h, 7, 1):run(connection); assert(APD.mode(h, 7) == 0)
    g_currentMission.allowed = true
    local before = g_server.count
    APDModeEvent.new(h, 7, 1):run(connection)
    assert(APD.mode(h, 7) == 1 and g_server.count == before + 1)
end)
test("event serialization and authoritative client application", function()
    local h, stream = mockHusbandry(), {}
    h.isServer = false
    APDModeEvent.new(h, 7, 2):writeStream(stream, {})
    APDModeEvent.emptyNew():readStream(stream, {getIsServer = function() return true end})
    assert(APD.mode(h, 7) == 2 and #stream == 0)
end)
test("deleted and unowned husbandries cannot be managed", function()
    local h = mockHusbandry(); h.farmId = 0; assert(not APD.canManage(h))
    h.farmId = 1; APD.onDelete(h); assert(not APD.canManage(h))
    assert(not APD.applyMode(h, 7, 1))
end)
test("ownership changes reset modes", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 2); APD.onOwnerChanged(h)
    assert(APD.mode(h, 7) == 0)
end)
test("only same-farm accepting production points receive goods", function()
    local h = mockHusbandry()
    local function point(farm, accepts)
        return {getOwnerFarmId = function() return farm end, storage = mockStorage(0, 500),
            inputFillTypeIds = {[7] = accepts}, owningPlaceable = {rootNode = 20}}
    end
    local good, foreign, wrong = point(1, true), point(2, true), point(1, false)
    g_currentMission.productionChainManager = {getProductionPointsForFarmId = function() return {good, foreign, wrong} end}
    assert(#APD.targets(h, 7) == 1)
    APD.applyMode(h, 7, 2); g_currentMission.money = 0
    APD.processHour(h)
    near(good.storage.amount, 100); near(foreign.storage.amount, 0); near(wrong.storage.amount, 0)
    near(g_currentMission.money, -100 * 100 * 0.000035)
end)
test("clients never process balances", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 1); h.isServer = false
    g_currentMission.money = 0; APD.processHour(h)
    near(g_currentMission.money, 0); near(h.spec_husbandryPallets.pendingLiters[7], 100)
end)
test("hourly sale preserves other output and uses native factor", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 1)
    g_currentMission.money = 0; APD.processHour(h); APD.processHour(h)
    near(g_currentMission.money, 180); near(h.spec_husbandryPallets.pendingLiters[8], 40)
end)
test("specialization registration works with a proxy and is idempotent", function()
    local entry = {specializations = {PlaceableHusbandryMilk}, specializationsByName = {}}
    local calls = 0
    local manager = {typeName = "placeable", types = {barn = entry}, addSpecialization = function(_, _, name)
        entry.specializationsByName[name] = true; calls = calls + 1
    end}
    TypeManager.validateTypes(manager); TypeManager.validateTypes(manager); assert(calls == 1)
    manager.typeName = "vehicle"; TypeManager.validateTypes(manager); assert(calls == 1)
end)
test("animal menu opens product and mode dialogs, cancel is harmless", function()
    local h = mockHusbandry()
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); assert(#frame.menuButtonInfo == 1)
    frame.menuButtonInfo[1].callback(); assert(#OptionDialog.options == 2)
    OptionDialog.callback(0); assert(APD.mode(h, 7) == 0)
    frame.menuButtonInfo[1].callback(); OptionDialog.callback(1)
    assert(#OptionDialog.options == 3)
    OptionDialog.callback(3); assert(APD.mode(h, 7) == 2)
end)
test("disabled mod leaves native animal menu alone", function()
    g_modIsLoaded[g_currentModName] = false
    local frame = {selectedHusbandry = mockHusbandry(), setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame)
    assert(#frame.menuButtonInfo == 0)
    g_modIsLoaded[g_currentModName] = true
end)
print(string.format("%d behavioral tests passed", passed))
