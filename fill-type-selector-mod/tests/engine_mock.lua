-- Contract doubles, not copies of game implementations. The Sprayer double follows the decisions
-- documented in DEVELOPMENT.md for Sprayer.lua 1.25 so the tests can tell vanilla and Mod apart.
g_currentModName = "FS25_FillTypeSelector"
g_modIsLoaded = {[g_currentModName] = true}
GS_PRIO_HIGH = 2

-- Like the game: FillTypeManager:initDataStructures resets FillType while the map loads
-- (fillTypes/FillTypeManager.lua:103), after Mod scripts ran. Scripts see an empty table
-- at load time; tests call loadMapFillTypes() before anything uses fill types.
MOCK_FILL_TYPES = {UNKNOWN = 1, FERTILIZER = 2, LIQUIDFERTILIZER = 3, HERBICIDE = 4, LIME = 5, MANURE = 6,
    LIQUIDMANURE = 7, DIGESTATE = 8, SEEDS = 9, WHEAT = 10}
FillType = {}
function loadMapFillTypes() FillType = MOCK_FILL_TYPES end
FillTypeManager = {SEND_NUM_BITS = 8}
local titles = {FERTILIZER = "Solid Fertilizer", LIQUIDFERTILIZER = "Liquid Fertilizer", HERBICIDE = "Herbicide",
    LIME = "Lime", MANURE = "Manure", LIQUIDMANURE = "Slurry", DIGESTATE = "Digestate", SEEDS = "Seeds"}
local names = {}
for name, index in pairs(MOCK_FILL_TYPES) do names[index] = name end
g_fillTypeManager = {
    getFillTypeIndexByName = function(_, name) return name and FillType[string.upper(name)] end,
    getFillTypeNameByIndex = function(_, index) return names[index] end,
    getFillTypeTitleByIndex = function(_, index) return titles[names[index]] end
}
local sprayTypes = {FERTILIZER = true, LIQUIDFERTILIZER = true, HERBICIDE = true, LIME = true, MANURE = true,
    LIQUIDMANURE = true, DIGESTATE = true}
g_sprayTypeManager = {getSprayTypeByFillTypeIndex = function(_, index)
    if sprayTypes[names[index]] then return {name = names[index]} end
end}

InputAction = {TOGGLE_SEEDS = "TOGGLE_SEEDS", TOGGLE_SEEDS_BACK = "TOGGLE_SEEDS_BACK",
    -- The game creates this entry from modDesc <actions>.
    FTS_SELECT_FILL_TYPE = "FTS_SELECT_FILL_TYPE"}
g_inputBinding = {events = {}, nextId = 0}
function g_inputBinding:setActionEventText(id, value) self.events[id].text = value end
function g_inputBinding:setActionEventActive(id, value) self.events[id].active = value end
function g_inputBinding:setActionEventTextVisibility(id, value) self.events[id].visible = value end
function g_inputBinding:setActionEventTextPriority(id, value) self.events[id].priority = value end
g_i18n = {getText = function(_, key) return key == "fts_selectFillType" and "Select fertilizer" or key end}

warnings = {}
Logging = {
    error = function(message, ...) error(string.format(message, ...)) end,
    warning = function(message, ...) table.insert(warnings, string.format(message, ...)) end
}
Utils = {
    prependedFunction = function(old, new) return function(...) new(...); return old(...) end end,
    appendedFunction = function(old, new) return function(...) old(...); return new(...) end end
}
TypeManager = {validateTypes = function() end}

function Class(class, base)
    if base ~= nil then setmetatable(class, {__index = base}) end
    return {__index = class}
end
Event = {new = function(mt) return setmetatable({}, mt) end}
function InitEventClass() end
NetworkUtil = {
    writeNodeObject = function(s, v) table.insert(s, v) end,
    readNodeObject = function(s) return table.remove(s, 1) end
}
function streamWriteUIntN(s, v, bits)
    assert(v >= 0 and v < 2 ^ bits, "value does not fit the stream bits")
    table.insert(s, v)
end
function streamReadUIntN(s) return table.remove(s, 1) end

broadcasts = {}
g_server = {broadcastEvent = function(_, event, sendLocal, ignore, object)
    table.insert(broadcasts, {event = event, sendLocal = sendLocal, ignore = ignore, object = object})
end}
serverConnection = {getIsServer = function() return true end}
replies = {}
local function newClientConnection(farmId)
    return {farmId = farmId, getIsServer = function() return false end,
        sendEvent = function(self, event) table.insert(replies, {connection = self, event = event}) end}
end
clientConnection = newClientConnection(1)
otherFarmConnection = newClientConnection(2)

XMLValueType = {STRING = "string"}
savegamePaths = {}
Vehicle = {xmlSchemaSavegame = {register = function(_, valueType, path) savegamePaths[path] = valueType end}}

local stub = function() end
Sprayer = {name = "Sprayer", getExternalFill = stub, getIsSprayerExternallyFilled = stub, getIsSprayTypeActive = stub,
    setSprayerAITerrainDetailProhibitedRange = stub}
FillUnit = {name = "FillUnit", setFillUnitFillTypeToDisplay = stub, getFillUnitSupportedFillTypes = stub}
SowingMachine = {name = "SowingMachine"}
SpecializationUtil = {
    hasSpecialization = function(needle, list)
        for _, value in ipairs(list) do if value == needle then return true end end
        return false
    end,
    registerOverwrittenFunction = function(vehicleType, name, func)
        table.insert(vehicleType.overwrites, {name = name, func = func})
    end,
    registerEventListener = function(vehicleType, name, spec)
        vehicleType.listeners[name] = spec[name]
    end
}
g_specializationManager = {getSpecializationByName = function(_, name)
    if name == "fillTypeSelector" then return {name = g_currentModName .. ".fillTypeSelector"} end
end}

g_currentMission = {
    money = 0,
    missionInfo = {helperBuyFertilizer = true, helperManureSource = 1, helperSlurrySource = 1},
    addMoney = function(self, value, farmId, moneyType)
        self.money = self.money + value
        self.lastMoneyType = moneyType
    end,
    -- Prices per liter; a fill type without a price can't be bought (EconomyManager:getCostPerLiter).
    prices = {},
    economyManager = {getCostPerLiter = function(_, fillType) return g_currentMission.prices[fillType] end},
    liquidManureLoadingStations = {},
    getFarmId = function(_, connection) return connection and connection.farmId end,
    -- AccessHandler double: own farm only (the game also allows contracted farms).
    accessHandler = {canFarmAccess = function(_, farmId, object) return farmId == object:getOwnerFarmId() end}
}
PRICE = 2
MoneyType = {PURCHASE_FERTILIZER = "purchaseFertilizer"}
g_farmManager = {stats = {}, updateFarmStats = function(self, farmId, name, value) table.insert(self.stats, {farmId, name, value}) end}
local isSprayType = function(fillType) return sprayTypes[names[fillType]] == true end

-- Sprayer double: the vanilla decisions this Mod depends on.
local function vanillaExternalFill(self, fillType, dt)
    local unit = self:getSprayerFillUnitIndex()
    local allows = function(t) return self:getFillUnitAllowsFillType(unit, t) end
    local info = g_currentMission.missionInfo
    local unknown = fillType == FillType.UNKNOWN
    local found = false
    if fillType == FillType.LIQUIDMANURE or fillType == FillType.DIGESTATE
        or (unknown and (allows(FillType.LIQUIDMANURE) or allows(FillType.DIGESTATE))) then
        -- Sprayer.lua:505-530: buying always takes slurry while it has a price; a pit gives
        -- slurry before digestate.
        if info.helperSlurrySource == 2 then
            found = true
            fillType = g_currentMission.economyManager:getCostPerLiter(FillType.LIQUIDMANURE, false)
                and FillType.LIQUIDMANURE or FillType.DIGESTATE
        elseif info.helperSlurrySource > 2 then
            local station = g_currentMission.liquidManureLoadingStations[info.helperSlurrySource - 2]
            if self.isServer and station ~= nil then
                for _, candidate in ipairs({FillType.LIQUIDMANURE, FillType.DIGESTATE}) do
                    local usage = self:getSprayerUsage(candidate, dt)
                    if usage - station:removeFillLevel(candidate, usage, 1) > 0.000001 then
                        return candidate, usage
                    end
                end
            end
            return FillType.UNKNOWN, 0
        end
    elseif fillType == FillType.MANURE or (unknown and allows(FillType.MANURE)) then
        if info.helperManureSource == 2 then found, fillType = true, FillType.MANURE end
    elseif fillType == FillType.FERTILIZER or fillType == FillType.LIQUIDFERTILIZER or fillType == FillType.HERBICIDE
        or fillType == FillType.LIME or (unknown and (allows(FillType.LIQUIDFERTILIZER) or allows(FillType.FERTILIZER)
        or allows(FillType.HERBICIDE))) then
        if info.helperBuyFertilizer then
            found = true
            if unknown then
                if allows(FillType.LIQUIDFERTILIZER) then fillType = FillType.LIQUIDFERTILIZER
                elseif allows(FillType.FERTILIZER) then fillType = FillType.FERTILIZER
                else fillType = FillType.HERBICIDE end
            end
        end
    end
    if not found then return FillType.UNKNOWN, 0 end
    local usage = dt / 1000
    if self.isServer then g_currentMission:addMoney(-usage * PRICE * 1.5) end
    return fillType, usage
end

local function vanillaExternallyFilled(self)
    if not self.aiActive or not self.fieldWorkActive then return false end
    local spec, info = self.spec_sprayer, g_currentMission.missionInfo
    return (spec.isSlurryTanker and info.helperSlurrySource > 1)
        or (spec.isManureSpreader and info.helperManureSource > 1)
        or (spec.isFertilizerSprayer and info.helperBuyFertilizer)
end

local function vanillaSprayTypeActive(self, sprayType)
    if sprayType.fillTypes ~= nil then
        local current = self:getFillUnitFillType(sprayType.fillUnitIndex or self.spec_sprayer.fillUnitIndex)
        for _, name in ipairs(sprayType.fillTypes) do
            if current == g_fillTypeManager:getFillTypeIndexByName(name) then return true end
        end
        return false
    end
    return true
end

-- Foldable double: a later spec in the chain that only checks its own fields.
local function foldableSprayTypeActive(self, superFunc, sprayType)
    if sprayType.hasRequiredFoldingConfiguration == false then return false end
    return superFunc(self, sprayType)
end

local function raise(vehicle, name, ...)
    local listener = vehicle.vehicleType.listeners[name]
    if listener ~= nil then listener(vehicle, ...) end
end

-- Fill unit double following FillUnit:addFillUnitFillLevel event order: emptying raises
-- onChangedFillType before the non-persistent display fill type is reset.
local function addFillUnitFillLevel(self, unitIndex, delta, fillType)
    local unit = self.fillUnits[unitIndex]
    if unit.fillType == fillType then
        unit.fillLevel = math.max(0, unit.fillLevel + delta)
    elseif delta > 0 then
        local oldFillType = unit.fillType
        unit.fillLevel, unit.fillType = delta, fillType
        raise(self, "onChangedFillType", unitIndex, fillType, oldFillType)
    end
    if unit.fillLevel <= 0 then
        raise(self, "onChangedFillType", unitIndex, FillType.UNKNOWN, unit.fillType)
        unit.fillType = FillType.UNKNOWN
        if not unit.fillTypeToDisplayIsPersistent then unit.fillTypeToDisplay = FillType.UNKNOWN end
    end
    raise(self, "onFillUnitFillLevelChanged", unitIndex, delta, fillType)
end

-- options: fillTypes (names), manure/slurry flags, sprayTypes, seeds, specNames, isServer, isClient
function mockSprayer(options)
    options = options or {}
    local supported = {}
    for _, name in ipairs(options.fillTypes or {"FERTILIZER", "LIME"}) do supported[FillType[name]] = true end
    local vehicle = {
        isServer = options.isServer ~= false, isClient = options.isClient ~= false,
        aiActive = false, fieldWorkActive = false, synchronized = true, ownerFarmId = 1,
        actionEvents = {}, aiRanges = {},
        fillUnits = {{fillType = FillType.UNKNOWN, fillLevel = 0, supportedFillTypes = supported,
            fillTypeToDisplay = FillType.UNKNOWN, fillTypeToDisplayIsPersistent = false}},
        spec_sprayer = {fillUnitIndex = 1, isManureSpreader = options.manure == true, isSlurryTanker = options.slurry == true,
            sprayTypes = options.sprayTypes or {}, fillTypeSources = {}, supportedSprayTypes = {}},
        specializationNames = options.specNames or {"fillUnit", "sprayer"},
        specializations = {FillUnit, Sprayer}
    }
    vehicle.spec_sprayer.isFertilizerSprayer = not vehicle.spec_sprayer.isManureSpreader and not vehicle.spec_sprayer.isSlurryTanker
    for fillType in pairs(supported) do
        vehicle.spec_sprayer.fillTypeSources[fillType] = {}
        table.insert(vehicle.spec_sprayer.supportedSprayTypes, fillType)
    end
    if options.seeds ~= nil then
        vehicle.spec_sowingMachine = {seeds = options.seeds, fillUnitIndex = 2}
        table.insert(vehicle.specializations, SowingMachine)
    end
    vehicle.rootVehicle, vehicle.childVehicles = vehicle, {vehicle}
    function vehicle:getFillUnitFillLevel(i) return self.fillUnits[i].fillLevel end
    function vehicle:getFillUnitFillType(i) return self.fillUnits[i].fillType end
    function vehicle:getFillUnitSupportedFillTypes(i) return self.fillUnits[i] and self.fillUnits[i].supportedFillTypes end
    function vehicle:getFillUnitAllowsFillType(i, fillType)
        local unit = self.fillUnits[i]
        return unit.supportedFillTypes[fillType] == true and (unit.fillLevel <= 0 or unit.fillType == fillType)
    end
    function vehicle:setFillUnitFillTypeToDisplay(i, fillType, isPersistent)
        self.fillUnits[i].fillTypeToDisplay = fillType
        self.fillUnits[i].fillTypeToDisplayIsPersistent = isPersistent == true
    end
    function vehicle:getSprayerFillUnitIndex() return self.spec_sprayer.fillUnitIndex end
    function vehicle:getSprayerUsage(_, dt) return dt / 1000 end
    function vehicle:getActiveFarm() return self.ownerFarmId end
    function vehicle:getLastTouchedFarmlandFarmId() return self.ownerFarmId end
    function vehicle:setSprayerAITerrainDetailProhibitedRange(fillType) table.insert(self.aiRanges, fillType) end
    function vehicle:getIsSynchronized() return self.synchronized end
    function vehicle:getIsAIActive() return self.aiActive end
    function vehicle:getOwnerFarmId() return self.ownerFarmId end
    function vehicle:clearActionEventsTable(events)
        for action, event in pairs(events) do events[action] = nil; g_inputBinding.events[event.actionEventId] = nil end
    end
    function vehicle:addActionEvent(events, action, target, callback, up, down, always, active, state)
        g_inputBinding.nextId = g_inputBinding.nextId + 1
        local id = g_inputBinding.nextId
        g_inputBinding.events[id] = {action = action, target = target, callback = callback, state = state, active = active}
        events[action] = {actionEventId = id}
        return true, id
    end
    vehicle.getExternalFill = vanillaExternalFill
    vehicle.getIsSprayerExternallyFilled = vanillaExternallyFilled
    vehicle.getIsSprayTypeActive = function(self, sprayType) return vanillaSprayTypeActive(self, sprayType) end
    local inner = vehicle.getIsSprayTypeActive
    vehicle.getIsSprayTypeActive = function(self, sprayType) return foldableSprayTypeActive(self, inner, sprayType) end
    function vehicle:getActiveSprayType()
        for _, sprayType in ipairs(self.spec_sprayer.sprayTypes) do
            if self:getIsSprayTypeActive(sprayType) then return sprayType end
        end
    end
    function vehicle:addFill(delta, name) addFillUnitFillLevel(self, 1, delta, FillType[name]) end
    vehicle.raise = raise

    if options.withMod ~= false then
        -- Mirrors TypeManager:finalizeTypes and SpecializationUtil.createSpecializationEnvironments.
        local vehicleType = {overwrites = {}, listeners = {}}
        FillTypeSelector.registerOverwrittenFunctions(vehicleType)
        FillTypeSelector.registerEventListeners(vehicleType)
        for _, entry in ipairs(vehicleType.overwrites) do
            local superFunc = vehicle[entry.name]
            vehicle[entry.name] = function(self, ...) return entry.func(self, superFunc, ...) end
        end
        vehicle.vehicleType = vehicleType
        vehicle[FillTypeSelector.SPEC_TABLE_NAME] = setmetatable({actionEvents = {}}, {__index = vehicle})
        raise(vehicle, "onLoad", options.savegame)
        raise(vehicle, "onPostLoad", options.savegame)
    else
        vehicle.vehicleType = {listeners = {}}
    end
    return vehicle
end

function registerInput(vehicle, isActiveForInput)
    raise(vehicle, "onRegisterActionEvents", isActiveForInput ~= false, true)
    local spec = vehicle[FillTypeSelector.SPEC_TABLE_NAME]
    local result = {}
    for action, event in pairs(spec.actionEvents) do result[action] = g_inputBinding.events[event.actionEventId] end
    return result
end

function press(event)
    event.callback(event.target, event.action, 1, event.state, false)
end

function mockXML()
    return {values = {},
        setValue = function(self, key, value) self.values[key] = value end,
        getValue = function(self, key, default) local v = self.values[key]; if v == nil then return default end; return v end}
end

isSprayFillType = isSprayType
