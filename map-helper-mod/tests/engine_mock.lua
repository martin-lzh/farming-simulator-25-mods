-- Contract doubles for the engine calls the Mod uses, not copies of game implementations.
-- Behaviour that matters to the Mod (callbacks bound at load, hooks on class tables, list
-- data sources, the create-job flow of the map page) follows the 1.25 references cited in
-- DEVELOPMENT.md.
g_currentModName = "FS25_MapHelper"
g_currentModDirectory = "map-helper-mod/"
g_modIsLoaded = {[g_currentModName] = true}
g_pixelSizeScaledX, g_pixelSizeScaledY = 1 / 1920, 1 / 1080
g_time = 0
GS_PRIO_VERY_LOW = 5
-- The game runs Luau, which has the Lua 5.1 global unpack.
unpack = unpack or table.unpack

function Class(class, base)
    if base ~= nil then
        setmetatable(class, {__index = base})
    end
    class.superClass = function() return base end
    return {__index = class}
end

Utils = {
    appendedFunction = function(old, new)
        if old == nil then return new end
        return function(...) old(...); new(...) end
    end,
    prependedFunction = function(old, new)
        if old == nil then return new end
        return function(...) new(...); old(...) end
    end
}

logged = {warnings = {}, infos = {}}
Logging = {
    warning = function(message, ...) table.insert(logged.warnings, string.format(message, ...)) end,
    info = function(message, ...) table.insert(logged.infos, string.format(message, ...)) end,
    error = function(message, ...) error(string.format(message, ...)) end
}

local texts = {
    mh_statusPaused = "Paused: %s", mh_statusWaiting = "Waiting: %d", mh_notifyPaused = "%s paused, %d waiting",
    mh_notifyFinished = "%s finished", mh_queueFull = "Full at %d", ui_fieldNo = "Field No."
}
g_i18n = {getText = function(_, key) return texts[key] or key end}
function g_i18n:formatArea(area, precision) return string.format("%." .. precision .. "f ha", area) end
function g_i18n:formatDistance(distance, precision) return string.format("%d m", math.floor(distance + 0.5)) end
Overlay = {DEFAULT_UVS = {0, 0, 0, 1, 1, 0, 1, 1}}
MathUtil = {vector2Length = function(x, z) return math.sqrt(x * x + z * z) end}
function getWorldTranslation(node) return node.x, 0, node.z end

-- Streams: ordered value lists; the bit width is checked against the value.
local function push(stream, value) table.insert(stream, value) end
local function pop(stream)
    assert(#stream > 0, "read past the end of the stream")
    return table.remove(stream, 1)
end
function streamWriteUIntN(s, v, bits)
    assert(math.type(v) == "integer" and v >= 0 and v < 2 ^ bits, "value does not fit " .. tostring(bits) .. " bits")
    push(s, v)
end
function streamReadUIntN(s) return pop(s) end
function streamWriteUInt8(s, v) streamWriteUIntN(s, v, 8) end
function streamReadUInt8(s) return pop(s) end
function streamWriteUInt16(s, v) streamWriteUIntN(s, v, 16) end
function streamReadUInt16(s) return pop(s) end
function streamWriteInt32(s, v) assert(math.type(v) == "integer", "Int32 needs an integer"); push(s, v) end
function streamReadInt32(s) return pop(s) end
function streamWriteFloat32(s, v) push(s, v) end
function streamReadFloat32(s) return pop(s) end
function streamWriteBool(s, v) assert(type(v) == "boolean", "bool expected"); push(s, v); return v end
function streamReadBool(s) local v = pop(s); assert(type(v) == "boolean", "bool expected"); return v end

objects = {}
NetworkUtil = {
    getObjectId = function(object) return object ~= nil and object.networkId or nil end,
    getObject = function(id) return objects[id] end,
    writeNodeObject = function(s, object) push(s, object ~= nil and object.networkId or 0) end,
    readNodeObject = function(s) return objects[pop(s)] end
}

Event = {new = function(mt) return setmetatable({}, mt) end}
registeredEvents = {}
function InitEventClass(class, name) registeredEvents[name] = (registeredEvents[name] or 0) + 1 end

FarmManager = {SPECTATOR_FARM_ID = 0, FARM_ID_SEND_NUM_BITS = 4}
MessageType = {AI_JOB_STOPPED = 133}
g_messageCenter = {subscribers = {}}
function g_messageCenter:subscribe(messageType, callback, target)
    table.insert(self.subscribers, {type = messageType, callback = callback, target = target})
end
function g_messageCenter:unsubscribeAll(target)
    for i = #self.subscribers, 1, -1 do
        if self.subscribers[i].target == target then table.remove(self.subscribers, i) end
    end
end
function g_messageCenter:publish(messageType, ...)
    for _, s in ipairs(self.subscribers) do
        if s.type == messageType then s.callback(s.target, ...) end
    end
end

-- AI messages with GIANTS-style isa.
local function messageClass(base)
    local class = {}
    class.__index = class
    class.base = base
    class.new = function() return setmetatable({}, class) end
    class.isa = function(self, other)
        local current = getmetatable(self)
        while current ~= nil do
            if current == other then return true end
            current = current.base
        end
        return false
    end
    if base ~= nil then setmetatable(class, {__index = base}) end
    return class
end
AIMessage = messageClass(nil)
AIMessageSuccessFinishedJob = messageClass(AIMessage)
AIMessageSuccessSiloEmpty = messageClass(AIMessage)
AIMessageSuccessStoppedByUser = messageClass(AIMessage)
AIMessageErrorOutOfFill = messageClass(AIMessage)

AIParameterType = {TEXT = 1, SELECTOR = 2, POSITION = 3, POSITION_ANGLE = 4, UNLOADING_STATION = 5, LOADING_STATION = 6, FILLTYPE = 7}
-- Same names and order as AIJobTypeManager:loadMapData registers them (1.25).
AIJobType = {GOTO = 1, FIELDWORK = 2, CONVEYOR = 3, DELIVER = 4, LOAD_AND_DELIVER = 5}

-- Stations: a placeable with a map hotspot, synchronized network objects.
function mockStation(networkId, name, x, z)
    local station = {networkId = networkId, name = name}
    station.owningPlaceable = {getHotspot = function() return {getWorldPosition = function() return x, z end} end}
    function station:getName() return self.name end
    objects[networkId] = station
    return station
end

-- Parameters: the getters and setters the Mod and the native form use.
local VehicleParameter = {}
VehicleParameter.__index = VehicleParameter
function VehicleParameter:getType() return AIParameterType.TEXT end
function VehicleParameter:setVehicle(vehicle) self.vehicleId = NetworkUtil.getObjectId(vehicle) end
function VehicleParameter:getVehicle() return NetworkUtil.getObject(self.vehicleId) end
function VehicleParameter:getString() local v = self:getVehicle(); return v ~= nil and v:getName() or "" end

local PositionParameter = {}
PositionParameter.__index = PositionParameter
function PositionParameter:getType() return AIParameterType.POSITION_ANGLE end
function PositionParameter:setPosition(x, z) self.x, self.z = x, z end
function PositionParameter:getPosition() return self.x, self.z end
function PositionParameter:setAngle(angle) self.angle = angle end
function PositionParameter:getAngle() return self.angle end
function PositionParameter:getString() return string.format("< %.1f , %.1f >", self.x or 0, self.z or 0) end

local function stationParameter(kind)
    local parameter = {kind = kind, ids = {}}
    parameter[kind .. "StationIds"] = parameter.ids
    function parameter:getType()
        return kind == "loading" and AIParameterType.LOADING_STATION or AIParameterType.UNLOADING_STATION
    end
    local setName = kind == "loading" and "setLoadingStation" or "setUnloadingStation"
    local getName = kind == "loading" and "getLoadingStation" or "getUnloadingStation"
    parameter[setName] = function(self, station) self.stationId = NetworkUtil.getObjectId(station) end
    parameter[getName] = function(self) return NetworkUtil.getObject(self.stationId) end
    function parameter:getString() local s = NetworkUtil.getObject(self.stationId); return s ~= nil and s:getName() or "" end
    function parameter:setValid(stations)
        for i = #self.ids, 1, -1 do self.ids[i] = nil end
        for _, station in ipairs(stations) do table.insert(self.ids, station.networkId) end
        self.stationId = self.stationId or self.ids[1]
    end
    return parameter
end

local function group(title, ...)
    local parameters = {...}
    return {getTitle = function() return title end, getParameters = function() return parameters end}
end

-- A job with the parameters of its 1.25 type (SDK ai/jobs/*.lua constructors).
MockJob = {}
MockJob.__index = MockJob
MockJob.class = function() return MockJob end
function MockJob.new(typeIndex)
    local self = setmetatable({jobTypeIndex = typeIndex, setValuesCount = 0, valid = true, resetCount = 0,
        currentTaskIndex = 0, tasks = {}}, MockJob)
    self.vehicleParameter = setmetatable({}, VehicleParameter)
    self.namedParameters = {{name = "vehicle", parameter = self.vehicleParameter}}
    self.groups = {group("ai_parameterGroupTitleVehicle", self.vehicleParameter)}
    local function addPosition(title)
        self.positionAngleParameter = setmetatable({angle = 0}, PositionParameter)
        table.insert(self.namedParameters, {name = "positionAngle", parameter = self.positionAngleParameter})
        table.insert(self.groups, group(title, self.positionAngleParameter))
    end
    if typeIndex == AIJobType.GOTO or typeIndex == AIJobType.FIELDWORK then
        addPosition("ai_parameterGroupTitlePosition")
        self.driveToTask = {}
        self.tasks = {self.driveToTask}
    elseif typeIndex == AIJobType.DELIVER then
        self.unloadingStationParameter = stationParameter("unloading")
        table.insert(self.namedParameters, {name = "unloadingStation", parameter = self.unloadingStationParameter})
        table.insert(self.groups, group("ai_parameterGroupTitleUnloadingStation", self.unloadingStationParameter))
        addPosition("ai_parameterGroupTitleLoadingPosition")
    elseif typeIndex == AIJobType.LOAD_AND_DELIVER then
        self.loadingStationParameter = stationParameter("loading")
        self.unloadingStationParameter = stationParameter("unloading")
        table.insert(self.namedParameters, {name = "loadingStation", parameter = self.loadingStationParameter})
        table.insert(self.namedParameters, {name = "unloadingStation", parameter = self.unloadingStationParameter})
        table.insert(self.groups, group("ai_parameterGroupTitleLoadingStation", self.loadingStationParameter))
        table.insert(self.groups, group("ai_parameterGroupTitleUnloadingStation", self.unloadingStationParameter))
    end
    -- Older tests address these by their earlier names.
    self.positionParameter = self.positionAngleParameter
    self.stationParameter = self.loadingStationParameter
    return self
end
function MockJob:getNamedParameter(name)
    for _, item in ipairs(self.namedParameters) do
        if item.name:upper() == name:upper() then return item.parameter end
    end
end
function MockJob:getNamedParameters() return self.namedParameters end
function MockJob:getGroupedParameters() return self.groups end
function MockJob:onParameterValueChanged(parameter) self.changedParameter = parameter end
-- Like the SDK applyCurrentState: vehicle, its position as default target, valid stations.
function MockJob:applyCurrentState(vehicle, mission, farmId, isDirectStart)
    self.vehicleParameter:setVehicle(vehicle)
    if self.positionAngleParameter ~= nil then
        self.positionAngleParameter:setPosition(vehicle.x or 0, vehicle.z or 0)
        self.positionAngleParameter:setAngle(0)
    end
    local stations = mission.stations or {loading = {}, unloading = {}}
    if self.loadingStationParameter ~= nil then self.loadingStationParameter:setValid(stations.loading) end
    if self.unloadingStationParameter ~= nil then self.unloadingStationParameter:setValid(stations.unloading) end
end
function MockJob:setValues()
    self.setValuesCount = self.setValuesCount + 1
    if self.driveToTask ~= nil and self.positionAngleParameter ~= nil then
        self.driveToTask.x, self.driveToTask.z = self.positionAngleParameter:getPosition()
    end
end
function MockJob:resetTasks() self.resetCount = self.resetCount + 1 end
function MockJob:getTaskByIndex(index) return self.tasks[index] end
function MockJob:getDescription()
    return g_currentMission.aiJobTypeManager:getJobTypeByIndex(self.jobTypeIndex).title .. " - task " .. self.currentTaskIndex
end
function MockJob:getHelperName() return "Helper" end
function MockJob:validate(farmId)
    self.validatedFarm = farmId
    if not self.valid then return false, "invalid target" end
    return self.vehicleParameter:getVehicle() ~= nil, "no vehicle"
end
function MockJob:getIsStartable(connection)
    self.startConnection = connection
    local vehicle = self.vehicleParameter:getVehicle()
    if vehicle == nil then return false, 2 end
    if g_currentMission.aiSystem.limitReached then return false, 1 end
    if vehicle:getIsAIActive() then return false, 4 end
    -- Enterable:getIsInUse: someone sits in it and the start comes from another connection.
    if vehicle.spec_enterable ~= nil and vehicle.spec_enterable.isControlled and vehicle:getOwnerConnection() ~= connection then
        return false, 5
    end
    return true, 0
end
local function writeParameters(job, s)
    push(s, job.vehicleParameter.vehicleId or 0)
    for _, item in ipairs(job.namedParameters) do
        local p = item.parameter
        if p == job.positionAngleParameter then
            push(s, p.x); push(s, p.z); push(s, p.angle)
        elseif p.kind ~= nil then
            push(s, p.stationId or 0)
        end
    end
end
local function readParameters(job, s)
    job.vehicleParameter.vehicleId = pop(s)
    for _, item in ipairs(job.namedParameters) do
        local p = item.parameter
        if p == job.positionAngleParameter then
            p.x = pop(s); p.z = pop(s); p.angle = pop(s)
        elseif p.kind ~= nil then
            local id = pop(s)
            p.stationId = id ~= 0 and id or nil
        end
    end
end
function MockJob:writeStream(s, connection)
    streamWriteBool(s, false)
    if streamWriteBool(s, self.jobId ~= nil) then streamWriteInt32(s, self.jobId) end
    writeParameters(self, s)
    streamWriteUInt8(s, 0)
    -- Like AIJobFieldWork:writeStream: the vehicle's worker settings at write time.
    if self.jobTypeIndex == AIJobType.FIELDWORK then
        local vehicle = self.vehicleParameter:getVehicle()
        if streamWriteBool(s, vehicle ~= nil) then push(s, vehicle.aiSettings or "default") end
    end
end
function MockJob:readStream(s, connection)
    streamReadBool(s)
    if streamReadBool(s) then self.jobId = streamReadInt32(s) end
    readParameters(self, s)
    self:setValues()
    streamReadUInt8(s)
    -- Like AIJobFieldWork:readStream: keep the sender's settings until the first update.
    if self.jobTypeIndex == AIJobType.FIELDWORK and streamReadBool(s) then
        self.pendingData = pop(s)
        self.pendingVehicle = true
    end
end
function MockJob:saveToXMLFile(xmlFile, key)
    local index = 0
    for _, item in ipairs(self.namedParameters) do
        local p = item.parameter
        local paramKey = string.format("%s.parameter(%d)", key, index)
        xmlFile:setString(paramKey .. "#name", item.name)
        if p == self.positionAngleParameter then
            xmlFile:setFloat(paramKey .. "#x", p.x)
            xmlFile:setFloat(paramKey .. "#z", p.z)
            xmlFile:setFloat(paramKey .. "#angle", p.angle)
        elseif p.kind ~= nil then
            xmlFile:setInt(paramKey .. "#station", p.stationId)
        end
        index = index + 1
    end
    return true
end
function MockJob:loadFromXMLFile(xmlFile, key)
    xmlFile:iterate(key .. ".parameter", function(_, paramKey)
        local p = self:getNamedParameter(xmlFile:getString(paramKey .. "#name"))
        if p == self.positionAngleParameter and p ~= nil then
            p.x, p.z = xmlFile:getFloat(paramKey .. "#x"), xmlFile:getFloat(paramKey .. "#z")
            p.angle = xmlFile:getFloat(paramKey .. "#angle")
        elseif p ~= nil and p.kind ~= nil then
            p.stationId = xmlFile:getInt(paramKey .. "#station")
        end
    end)
end
-- AIJob:delete (SDK ai/jobs/AIJob.lua:41-48) calls delete on every parameter, and no
-- AIParameter class has one: the real call raises, so must this double.
function MockJob:delete()
    error("dataS/scripts/ai/jobs/AIJob.lua:43: attempt to call missing method 'delete' of table")
end

AIJob = MockJob
local function jobClass(prefix)
    return {getIsStartErrorText = function(state) return prefix .. " start error " .. tostring(state) end}
end
AIJobTypeManager = {}
AIJobTypeManager.__index = AIJobTypeManager
function AIJobTypeManager.new()
    return setmetatable({jobTypes = {
        {name = "GOTO", title = "Go to", classObject = jobClass("GoTo")},
        {name = "FIELDWORK", title = "Field work", classObject = jobClass("FieldWork")},
        {name = "CONVEYOR", title = "Conveyor", classObject = jobClass("Conveyor")},
        {name = "DELIVER", title = "Deliver", classObject = jobClass("Deliver")},
        {name = "LOAD_AND_DELIVER", title = "Load and deliver", classObject = jobClass("LoadAndDeliver")}
    }}, AIJobTypeManager)
end
function AIJobTypeManager:createJob(index)
    if self.jobTypes[index] == nil then return nil end
    return MockJob.new(index)
end
function AIJobTypeManager:getJobTypeIndex(job) return job.jobTypeIndex end
function AIJobTypeManager:getJobTypeByIndex(index) return self.jobTypes[index] end
function AIJobTypeManager:getJobTypeIndexByName(name)
    for index, jobType in ipairs(self.jobTypes) do
        if jobType.name == name then return index end
    end
end

AISystem = {}
AISystem.__index = AISystem
function AISystem.new() return setmetatable({started = {}, nextId = 1}, AISystem) end
-- Jobs that run now (AISystem:getActiveJobs, SDK ai/AISystem.lua:541): started and not stopped.
function AISystem:getActiveJobs()
    local active = {}
    for _, job in ipairs(self.started) do
        local vehicle = job.vehicleParameter:getVehicle()
        if vehicle ~= nil and vehicle.aiJob == job then table.insert(active, job) end
    end
    return active
end
function AISystem:startJob(job, farmId)
    job.jobId = self.nextId
    self.nextId = self.nextId + 1
    job.startedFarmId = farmId
    job.currentTaskIndex = 1
    table.insert(self.started, job)
    local vehicle = job.vehicleParameter:getVehicle()
    vehicle.aiJob = job
    -- AIJobFieldWork:update applies pending settings to the vehicle on the first update.
    if job.pendingVehicle then
        vehicle.aiSettings = job.pendingData
        job.pendingData, job.pendingVehicle = nil, nil
    end
end
function AISystem:stopJobInternal(job, aiMessage)
    local vehicle = job.vehicleParameter:getVehicle()
    if vehicle ~= nil then vehicle.aiJob = nil end
    g_messageCenter:publish(MessageType.AI_JOB_STOPPED, job, aiMessage)
end
AISystem.stopJob = AISystem.stopJobInternal

FSBaseMission = {INGAME_NOTIFICATION_OK = "ok", INGAME_NOTIFICATION_INFO = "info", INGAME_NOTIFICATION_CRITICAL = "critical"}
function FSBaseMission:onStartMission() end
-- Like FSBaseMission:delete: resets the in-game menu, whose map frame clears its selection.
-- It also deletes the AI system, which stops every active job and publishes
-- AI_JOB_STOPPED (SDK ai/AISystem.lua:97, :587).
function FSBaseMission:delete()
    self.deleted = true
    if self.aiSystem ~= nil then
        for _, job in ipairs(self.aiSystem.started) do
            local vehicle = job.vehicleParameter:getVehicle()
            if vehicle ~= nil and vehicle.aiJob == job then
                self.aiSystem:stopJobInternal(job, nil)
            end
        end
    end
    if g_inGameMenu ~= nil and g_inGameMenu.pageMapOverview ~= nil then
        g_inGameMenu.pageMapOverview:setMapSelectionItem(nil)
    end
end
function FSBaseMission:sendInitialClientState() end
function FSBaseMission:addUpdateable(updateable) self.updateables[updateable] = updateable end
function FSBaseMission:removeUpdateable(updateable) self.updateables[updateable] = nil end
function FSBaseMission:getIsServer() return self.isServer end
function FSBaseMission:getFarmId(connection)
    if connection ~= nil then return connection.farmId end
    return self.farmId
end
function FSBaseMission:getHasPlayerPermission(permission, connection, farmId)
    assert(permission == "hireAssistant")
    if connection ~= nil then return connection.allowed end
    return self.allowed
end
function FSBaseMission:addIngameNotification(kind, text) table.insert(self.notifications, {kind = kind, text = text}) end
function FSBaseMission:addMapHotspot(hotspot) self.mapHotspots[hotspot] = true end
function FSBaseMission:removeMapHotspot(hotspot) self.mapHotspots[hotspot] = nil end
FSCareerMissionInfo = {saveToXMLFile = function() end}

-- XML files in memory, keyed by filename.
files = {}
XMLFile = {}
XMLFile.__index = XMLFile
function XMLFile.create(_, filename, root) return setmetatable({filename = filename, values = {}}, XMLFile) end
function XMLFile.loadIfExists(_, filename)
    if filename == nil or files[filename] == nil then return nil end
    local copy = {}
    for k, v in pairs(files[filename]) do copy[k] = v end
    return setmetatable({filename = filename, values = copy}, XMLFile)
end
function XMLFile:setString(path, value) self.values[path] = value end
XMLFile.setInt, XMLFile.setFloat = XMLFile.setString, XMLFile.setString
function XMLFile:getString(path, default) local v = self.values[path]; if v == nil then return default end; return v end
XMLFile.getInt, XMLFile.getFloat = XMLFile.getString, XMLFile.getString
function XMLFile:hasElement(path)
    for key in pairs(self.values) do
        if key:sub(1, #path) == path and (key:sub(#path + 1, #path + 1) == "#" or key:sub(#path + 1, #path + 1) == ".") then
            return true
        end
    end
    return false
end
function XMLFile:iterate(path, closure)
    local i = 0
    while self:hasElement(path .. "(" .. i .. ")") do
        if closure(i + 1, path .. "(" .. i .. ")") == false then break end
        i = i + 1
    end
end
function XMLFile:save() files[self.filename] = self.values; self.saved = true end
function XMLFile:delete() self.deleted = true end

-- GUI doubles ---------------------------------------------------------------------------
FocusManager = {currentGui = "InGameMenu"}
function FocusManager:setGui(name) self.currentGui = name end
function FocusManager:setFocus(element)
    -- Like FocusManager:setFocus: only elements whose target belongs to the current gui.
    if element == nil or element.target == nil or element.target.name ~= self.currentGui then return false end
    self.focused = element
    return true
end
function FocusManager:getFocusedElement() return self.focused end
function FocusManager:linkElements() end
function FocusManager:removeElement() end

function mockElement(name, typeName)
    local e = {name = name, typeName = typeName or "GuiElement", elements = {}, visible = true, disabled = false, text = "",
        absPosition = {0.5, 0.8}, absSize = {0.15, 0.03}, position = {0, 0}, size = {0.15, 0.03}}
    function e:setText(text) self.text = text end
    function e:getText() return self.text end
    function e:setVisible(visible) self.visible = visible end
    -- GuiElement:getIsVisible checks the parents too.
    function e:getIsVisible()
        if not self.visible then return false end
        if self.parent ~= nil then return self.parent:getIsVisible() end
        return true
    end
    function e:setDisabled(disabled) self.disabled = disabled end
    function e:getIsDisabled() return self.disabled end
    function e:getIsFocused() return false end
    function e:getIsHighlighted() return false end
    function e:updateAbsolutePosition() self.positioned = true end
    -- Like GuiElement:setPosition, a position change moves absPosition by the same amount.
    function e:setPosition(x, y)
        x, y = x or self.position[1], y or self.position[2]
        self.absPosition = {self.absPosition[1] + x - self.position[1], self.absPosition[2] + y - self.position[2]}
        self.position = {x, y}
        self.anchorDeltasUpdated = (self.anchorDeltasUpdated or 0) + 1
    end
    function e:setSize(x, y)
        self.size = {x or self.size[1], y or self.size[2]}
        self.absSize = {self.size[1], self.size[2]}
    end
    function e:applyProfile(profile) self.profile = profile end
    function e:setImageSlice(_, slice) self.imageSlice = slice end
    function e:setImageFilename(filename) self.imageFilename = filename end
    function e:setImageUVs() end
    function e:invalidateLayout() self.layoutCount = (self.layoutCount or 0) + 1 end
    function e:addElement(child)
        if child.parent ~= nil then child:unlinkElement() end
        table.insert(self.elements, child); child.parent = self
    end
    function e:unlinkElement()
        if self.parent ~= nil then
            for i, child in ipairs(self.parent.elements) do
                if child == self then table.remove(self.parent.elements, i); break end
            end
            self.parent = nil
        end
    end
    function e:delete() self:unlinkElement(); self.deleted = true end
    function e:getDescendants()
        local result = {}
        for _, child in ipairs(self.elements) do
            for _, d in ipairs(child:getDescendants()) do table.insert(result, d) end
            table.insert(result, child)
        end
        return result
    end
    function e:getDescendantByName(wanted)
        for _, child in ipairs(self.elements) do
            if child.name == wanted then return child end
            local found = child:getDescendantByName(wanted)
            if found ~= nil then return found end
        end
    end
    function e:getDescendantById(wanted)
        for _, d in ipairs(self:getDescendants()) do
            if d.id == wanted then return d end
        end
    end
    function e:getAttribute(name) return self:getDescendantByName(name) end
    function e:onGuiSetupFinished()
        for _, child in ipairs(self.elements) do child:onGuiSetupFinished() end
        self.setupFinished = true
    end
    function e:clone(parent)
        local copy = mockElement(self.name, self.typeName)
        copy.profile, copy.id, copy.target, copy.onClickCallback = self.profile, nil, self.target, self.onClickCallback
        copy.size = {self.size[1], self.size[2]}
        copy.visible = self.visible
        for _, child in ipairs(self.elements) do child:clone(copy) end
        if parent ~= nil then parent:addElement(copy) end
        return copy
    end
    return e
end

-- MultiTextOption: setState(state, forceEvent) raises the onClick callback bound at load.
function mockMultiTextOption(name)
    local e = mockElement(name, "MultiTextOption")
    e.texts, e.state = {}, 1
    function e:setTexts(t) self.texts = t; self.state = math.min(self.state, math.max(#t, 1)) end
    function e:getState() return self.state end
    function e:setState(state, forceEvent)
        self.state = math.max(1, math.min(state, math.max(#self.texts, 1)))
        if forceEvent and self.onClickCallback ~= nil then self.onClickCallback(self.target, self.state, self) end
    end
    return e
end

-- SmoothList: asks its data source (the target) for sections and items and fills clones of
-- its ListItem templates; reports selection changes to the delegate (the target too).
function mockSmoothList(name, sectionHeaderName)
    local list = mockElement(name, "SmoothList")
    list.cells, list.selectedSectionIndex, list.selectedIndex, list.sectionHeaderName = {}, 1, 1, sectionHeaderName
    function list:onGuiSetupFinished()
        for _, child in ipairs(self.elements) do
            if child.typeName == "ListItem" then
                if self.sectionHeaderName ~= nil and child.name == self.sectionHeaderName then
                    self.headerTemplate = child
                else
                    self.cellTemplate = child
                end
            end
        end
        for _, template in ipairs({self.cellTemplate, self.headerTemplate}) do template:unlinkElement() end
    end
    function list:reloadData()
        local source = self.target
        self.cells, self.headers, self.count = {}, {}, 0
        local sections = source.getNumberOfSections ~= nil and source:getNumberOfSections(self) or 1
        for s = 1, sections do
            self.cells[s] = {}
            if self.headerTemplate ~= nil and source.getTitleForSectionHeader ~= nil then
                local title = source:getTitleForSectionHeader(self, s)
                if title ~= nil then
                    local header = self.headerTemplate:clone()
                    header:getAttribute("title"):setText(title)
                    self.headers[s] = header
                end
            end
            for i = 1, source:getNumberOfItemsInSection(self, s) do
                local cell = self.cellTemplate:clone()
                source:populateCellForItemInSection(self, s, i, cell)
                self.cells[s][i] = cell
                self.count = self.count + 1
            end
        end
        if self.count > 0 then
            self.selectedSectionIndex = math.min(self.selectedSectionIndex, sections)
            self.selectedIndex = math.min(self.selectedIndex, math.max(#self.cells[self.selectedSectionIndex], 1))
            self:setSelectedItem(self.selectedSectionIndex, self.selectedIndex, true)
        end
    end
    function list:getItemCount() return self.count or 0 end
    function list:getElementAtSectionIndex(s, i) return self.cells[s] ~= nil and self.cells[s][i] or nil end
    function list:setSelectedItem(s, i, force)
        self.selectedSectionIndex, self.selectedIndex = s, i
        if self.target.onListSelectionChanged ~= nil then self.target:onListSelectionChanged(self, s, i) end
    end
    function list:click(s, i)
        self:setSelectedItem(s, i, true)
        self.onClickCallback(self.target, self, s, i, self.cells[s][i], false)
    end
    -- Like SmoothListElement:mouseEvent: the first click selects, the second one raises the
    -- double click and then is handled as a click again.
    function list:doubleClick(s, i)
        self:click(s, i)
        if self.onDoubleClickCallback ~= nil then
            self.onDoubleClickCallback(self.target, self, s, i, self.cells[s][i], true)
        end
        self:click(s, i)
    end
    return list
end

local function profileValue(profiles, name, key)
    while name ~= nil and name ~= "" do
        local profile = profiles[name]
        if profile == nil then return nil end
        if profile.values[key] ~= nil then return profile.values[key] end
        name = profile.extends
    end
    return nil
end

-- Builds the real XML tree (handed over by the test runner) like Gui:loadGuiRec: elements
-- get the target, callbacks are bound once to target[name], onCreate is not used here.
local function buildElement(node, parent, target, profiles)
    local attributes = node.attributes
    local typeName = node.type
    local element
    if typeName == "SmoothList" then
        element = mockSmoothList(attributes.name, attributes.listSectionHeader)
    elseif typeName == "MultiTextOption" then
        element = mockMultiTextOption(attributes.name)
    else
        element = mockElement(attributes.name, typeName)
    end
    element.id, element.profile, element.target = attributes.id, attributes.profile, target
    element.visible = profileValue(profiles, attributes.profile, "visible") ~= "false"
    element.inputActionName = profileValue(profiles, attributes.profile, "inputAction")
    if attributes.text ~= nil then
        local key = attributes.text:match("^%$l10n_(.+)$")
        element.text = key ~= nil and g_i18n:getText(key) or attributes.text
        element.l10nKey = key
    end
    if attributes.onClick ~= nil then
        element.onClickCallback = target[attributes.onClick]
        assert(element.onClickCallback ~= nil, "no callback " .. attributes.onClick)
    end
    if attributes.onDoubleClick ~= nil then
        element.onDoubleClickCallback = target[attributes.onDoubleClick]
        assert(element.onDoubleClickCallback ~= nil, "no callback " .. attributes.onDoubleClick)
    end
    parent:addElement(element)
    for _, child in ipairs(node.children) do buildElement(child, element, target, profiles) end
    return element
end

xmlHandles, nextXmlHandle = {}, 1
function loadXMLFile(_, path)
    local handle = nextXmlHandle
    nextXmlHandle = nextXmlHandle + 1
    xmlHandles[handle] = path
    return handle
end
function delete() end
local function guiFileFor(handle)
    local path = xmlHandles[handle]
    for name, file in pairs(guiFiles) do
        if path:sub(-#name) == name then return file end
    end
    error("unknown gui file " .. tostring(path))
end

InfoDialog = {show = function(text) table.insert(infoDialogs, text) end}
infoDialogs = {}
DialogElement = {TYPE_INFO = 2, TYPE_WARNING = 1}

g_gui = {profiles = {}, presets = {}, profileLoads = 0, recLoads = 0}
function g_gui:loadProfileSet(xmlFile)
    self.profileLoads = self.profileLoads + 1
    for name in pairs(guiFileFor(xmlFile).profiles) do self.profiles[name] = true end
end
function g_gui:loadGuiRec(xmlFile, _, parent, target)
    self.recLoads = self.recLoads + 1
    local file = guiFileFor(xmlFile)
    for _, child in ipairs(file.tree.children) do buildElement(child, parent, target, file.profiles) end
end

InputAction = {MENU_EXTRA_1 = "MENU_EXTRA_1", MENU_MAP_ACTION_1 = "MENU_MAP_ACTION_1", MH_OPEN_MAP_HELPER = "MH_OPEN_MAP_HELPER"}
-- Events per context; the same action, target and trigger twice in one context is refused
-- like InputBinding:registerActionEvent does.
g_inputBinding = {events = {}, nextId = 1, currentContext = "PLAYER"}
function g_inputBinding:getContextName() return self.currentContext end
function g_inputBinding:beginActionEventsModification(context) self.registrationContext = context end
function g_inputBinding:endActionEventsModification() self.registrationContext = nil end
function g_inputBinding:registerActionEvent(action, target, callback)
    local context = self.registrationContext or self.currentContext
    for _, event in ipairs(self.events) do
        if event.action == action and event.target == target and event.context == context then
            return false, "", {event}
        end
    end
    local id = "event" .. self.nextId
    self.nextId = self.nextId + 1
    table.insert(self.events, {action = action, target = target, callback = callback, id = id, context = context})
    return true, id
end
function g_inputBinding:removeActionEventsByTarget(target)
    for i = #self.events, 1, -1 do
        if self.events[i].target == target then table.remove(self.events, i) end
    end
end
function g_inputBinding:setActionEventTextVisibility(id, visible)
    for _, event in ipairs(self.events) do if event.id == id then event.textVisible = visible end end
end
function g_inputBinding:setActionEventTextPriority(id, priority)
    for _, event in ipairs(self.events) do if event.id == id then event.priority = priority end end
end
function g_inputBinding:trigger(action, context)
    for _, event in ipairs(self.events) do
        if event.action == action and (context == nil or event.context == context) then event.callback(event.target, action, 1) end
    end
end

IngameMapElement = {panToHotspot = function() end, setCenterToWorldPosition = function() end}

-- The map frame: just the parts of the 1.25 InGameMenuMapFrame the Mod hooks or calls,
-- following decompiled gui/InGameMenuMapFrame.lua (states 1-7, create-job flow).
InGameMenuMapFrame = {MAP_FRUIT_TYPE = 1, MAP_HOTSPOTS = 4, MAP_FARMLANDS = 5, AI_CREATE_JOB = 6, AI_WORKER_LIST = 7,
    AI_MODE_OVERVIEW = 1, AI_MODE_CREATE = 2, AI_MODE_WORKER_LIST = 3}
function InGameMenuMapFrame:onLoadMapFinished() end
function InGameMenuMapFrame:registerInput()
    g_inputBinding:registerActionEvent(InputAction.MENU_MAP_ACTION_1, self, InGameMenuMapFrame.onMenuMapAction1)
end
function InGameMenuMapFrame:onMenuMapAction1()
    if self.buttonStartJobContainer:getIsVisible() then
        self.nativeStartPressed = (self.nativeStartPressed or 0) + 1
    end
end
function InGameMenuMapFrame:setupMapOverview()
    self.mapSelectorTexts = {"fruits", "growth", "soil", "hotspots", "farmlands", "button_createJob", "ui_activeAIJobs"}
    self.mapOverviewSelector:setTexts(self.mapSelectorTexts)
    self.isMapOverviewInitialized = true
end
function InGameMenuMapFrame:onClickMapOverviewSelector(state)
    self.filterListContainer:setVisible(state <= InGameMenuMapFrame.MAP_FARMLANDS)
    self.createJobEmptyText:setVisible(state == InGameMenuMapFrame.AI_CREATE_JOB)
    self.workerListContainer:setVisible(state == InGameMenuMapFrame.AI_WORKER_LIST)
    if self:getIsPicking() then self:executePickingCallback(false) end
    if state ~= InGameMenuMapFrame.AI_CREATE_JOB then self:setMapSelectionItem(nil) end
    self.previousSubCategoryState = state
end
function InGameMenuMapFrame:onFrameOpen()
    if not self.isMapOverviewInitialized then
        self:setupMapOverview()
        self.mapOverviewSelector:setState(1, true)
    end
    self:setMapSelectionItem(nil)
    self:generateJobTypes()
    self:setJobMenuVisible(false)
    self.mode = InGameMenuMapFrame.AI_MODE_OVERVIEW
    self:registerInput()
    self:onClickMapOverviewSelector(self.mapOverviewSelector:getState())
end
function InGameMenuMapFrame:onFrameClose()
    if self:getIsPicking() then self:executePickingCallback(false) end
end
function InGameMenuMapFrame:update(dt) end
function InGameMenuMapFrame:reset()
    self.isMapOverviewInitialized = false
    self:setMapSelectionItem(nil)
end
function InGameMenuMapFrame:generateJobTypes()
    self.jobTypeInstances = {
        [AIJobType.GOTO] = {class = MockJob.class, getIsAvailableForVehicle = function(_, vehicle) return not vehicle:getIsAIActive() end},
        -- AIJobFieldWork:getIsAvailableForVehicle: getCanStartFieldWork (false while the field worker
        -- runs) and AIJobVehicle:getCanStartAIVehicle (false while AI is active).
        [AIJobType.FIELDWORK] = {class = MockJob.class, getIsAvailableForVehicle = function(_, vehicle)
            return vehicle.getCanStartFieldWork ~= nil and vehicle:getCanStartFieldWork() and not vehicle:getIsAIActive()
        end},
        [AIJobType.CONVEYOR] = {class = MockJob.class, getIsAvailableForVehicle = function() return false end},
        [AIJobType.DELIVER] = {class = MockJob.class, getIsAvailableForVehicle = function(_, vehicle) return vehicle.canDeliver == true and not vehicle:getIsAIActive() end},
        [AIJobType.LOAD_AND_DELIVER] = {class = MockJob.class, getIsAvailableForVehicle = function(_, vehicle) return vehicle.canDeliver == true and not vehicle:getIsAIActive() end}
    }
end
function InGameMenuMapFrame:setJobMenuVisible(isVisible)
    if isVisible then
        self.createJobContainer:setVisible(false)
        self.mapOverviewSelector:setState(InGameMenuMapFrame.AI_CREATE_JOB, true)
    else
        for i = #self.jobMenuLayout.elements, 1, -1 do self.jobMenuLayout.elements[i]:delete() end
        self.currentJobElements = {}
        self.jobTypeElement:setTexts({})
        self.createJobContainer:setVisible(false)
    end
    self.createJobContainer:setVisible(isVisible)
    self.createJobEmptyText:setVisible(not isVisible)
    self.mapOverviewSelector:setDisabled(isVisible)
end
function InGameMenuMapFrame:getIsPicking() return self.isPickingLocation == true end
function InGameMenuMapFrame:executePickingCallback(...)
    self.isPickingLocation = false
    local cb = self.pickingCallback
    self.pickingCallback = nil
    if cb ~= nil then cb(...) end
end
function InGameMenuMapFrame:setMapSelectionItem(hotspot)
    self.selected = hotspot
    self.currentHotspot = hotspot
    if not self:getIsPicking() then
        g_currentMission:removeMapHotspot(self.aiTargetMapHotspot)
    end
    self.mode = InGameMenuMapFrame.AI_MODE_OVERVIEW
end
function InGameMenuMapFrame:refreshContextInput() self.contextRefreshed = (self.contextRefreshed or 0) + 1 end
-- Like the native setActiveJobTypeSelection: a fresh job with the vehicle's state and one
-- title row per group plus one row per parameter.
function InGameMenuMapFrame:setActiveJobTypeSelection(jobTypeIndex)
    if self.currentJob == nil or jobTypeIndex ~= self.currentJob.jobTypeIndex then
        for i = #self.jobMenuLayout.elements, 1, -1 do self.jobMenuLayout.elements[i]:delete() end
        self.currentJob = g_currentMission.aiJobTypeManager:createJob(jobTypeIndex)
        self.currentJob:applyCurrentState(self.currentJobVehicle, g_currentMission, g_localPlayer.farmId, false)
        self.currentJob.builtWhileAIActive = self.currentJobVehicle:getIsAIActive()
        self.currentJobElements = {}
        for _, group in ipairs(self.currentJob:getGroupedParameters()) do
            -- Every row of the native form is 40 px (fs25_aiCreateJobParameterTitle/-Button/-MultiTextOption).
            local title = mockElement("title", "Text")
            title.absSize = {0.2, 40 * g_pixelSizeScaledY}
            self.jobMenuLayout:addElement(title)
            for _, parameter in ipairs(group:getParameters()) do
                local row = mockElement("row", "Button")
                row.absSize = {0.2, 40 * g_pixelSizeScaledY}
                row.aiParameter = parameter
                self.jobMenuLayout:addElement(row)
                table.insert(self.currentJobElements, row)
            end
        end
        self:updateParameterValueTexts()
        self:validateParameters()
        self.jobMenuLayout:invalidateLayout()
    end
    self:refreshContextInput()
end
function InGameMenuMapFrame:onJobTypeChanged(index) self:setActiveJobTypeSelection(self.currentJobTypes[index]) end
function InGameMenuMapFrame:updateParameterValueTexts()
    self.valueTextsUpdated = (self.valueTextsUpdated or 0) + 1
    g_currentMission:addMapHotspot(self.aiTargetMapHotspot)
end
function InGameMenuMapFrame:validateParameters()
    if self.currentJob ~= nil then
        self.currentJob:setValues()
        self.lastValid = self.currentJob:validate(g_localPlayer.farmId)
    end
end
function InGameMenuMapFrame:updateWarnings() self.warningsUpdated = true end
-- Native createJob (context button Create job): selects state 6 through setJobMenuVisible.
function InGameMenuMapFrame:createJob()
    local vehicle = self.currentHotspot ~= nil and self.currentHotspot.vehicle or nil
    if vehicle == nil then return end
    self.currentJobTypes = {AIJobType.GOTO}
    self.jobTypeElement:setTexts({"Go to"})
    self.mode = InGameMenuMapFrame.AI_MODE_CREATE
    self.currentJobVehicle = vehicle
    self.currentJob = nil
    self:setJobMenuVisible(true)
    self:setActiveJobTypeSelection(AIJobType.GOTO)
end
function InGameMenuMapFrame:startPickPositionAndRotation(parameter, callback)
    self.isPickingLocation = true
    self.pickingCallback = function(success, x, z)
        if success then parameter:setPosition(x, z) end
        callback(success, x, z)
        self:validateParameters()
    end
end

local function hotspotMock(name)
    return {name = name, setWorldPosition = function(h, x, z) h.x, h.z = x, z end, setWorldRotation = function(h, r) h.rotation = r end}
end

-- The map page as InGameMenuMapFrame.xml builds it, with the selector callback bound to the
-- original function at load time (Gui:loadGuiRec → GuiElement:addCallback).
function mockFrame()
    local frame = setmetatable({mode = InGameMenuMapFrame.AI_MODE_OVERVIEW, name = "InGameMenu"}, {__index = InGameMenuMapFrame})
    local root = mockElement("frameRoot")
    frame.elements = {root}
    frame.filterBox = mockElement("filterBox")
    root:addElement(frame.filterBox)
    frame.mapOverviewSelector = mockMultiTextOption("mapOverviewSelector")
    frame.mapOverviewSelector.target = frame
    local original = InGameMenuMapFrame.onClickMapOverviewSelector
    frame.mapOverviewSelector.onClickCallback = function(target, state) original(target, state) end
    frame.filterBox:addElement(frame.mapOverviewSelector)
    frame.subCategoryDotBox = mockElement("subCategoryDotBox")
    for _ = 1, 7 do frame.subCategoryDotBox:addElement(mockElement("dot")) end
    frame.filterBox:addElement(frame.subCategoryDotBox)
    frame.filterListContainer = mockElement("filterListContainer")
    frame.workerListContainer = mockElement("workerListContainer")
    frame.createJobContainer = mockElement("createJobContainer")
    frame.createJobContainer.profile = "fs25_subCategoryListContainer"
    frame.createJobContainer.visible = false
    frame.jobTypeElement = mockMultiTextOption("jobTypeElement")
    frame.jobTypeElement.target = frame
    frame.jobTypeElement.absSize = {0.2, 40 * g_pixelSizeScaledY}
    frame.jobMenuLayout = mockElement("jobMenuLayout", "BoxLayout")
    frame.buttonStartJobContainer = mockElement("buttonStartJobContainer")
    frame.createJobContainer:addElement(frame.jobTypeElement)
    frame.createJobContainer:addElement(frame.jobMenuLayout)
    frame.createJobContainer:addElement(frame.buttonStartJobContainer)
    frame.createJobEmptyText = mockElement("createJobEmptyText")
    for _, element in ipairs({frame.filterListContainer, frame.createJobContainer, frame.createJobEmptyText, frame.workerListContainer}) do
        frame.filterBox:addElement(element)
    end
    frame.dataTables, frame.filterStates, frame.numSelectedFilters = {}, {}, {0, 0, 0, 0}
    frame.aiTargetMapHotspot = hotspotMock("target")
    frame.aiLoadingMarkerHotspot = hotspotMock("loading")
    frame.aiUnloadingMarkerHotspot = hotspotMock("unloading")
    frame.shopMoneyBox = mockElement("shopMoneyBox")
    frame.shopMoneyBoxBg = mockElement("shopMoneyBoxBg")
    frame.shopMoneyBoxBg.absPosition, frame.shopMoneyBoxBg.absSize = {0.75, 0.85}, {0.2, 0.06}
    frame.statusMessage = mockElement("statusMessage")
    frame.statusMessage.absPosition = {0.9, 0.82}
    local header = mockElement("header")
    header:addElement(frame.shopMoneyBox)
    root:addElement(header)
    frame.ingameMap = {
        panToHotspot = function(map, hotspot) map.pannedTo = hotspot end,
        setCenterToWorldPosition = function(map, x, z) map.centered = {x, z} end
    }
    frame:generateJobTypes()
    return frame
end

-- Mission, players and vehicles.
function mockVehicle(networkId, farmId, uniqueId)
    local vehicle = {networkId = networkId, farmId = farmId or 1, uniqueId = uniqueId or ("vehicle" .. networkId),
        spec_aiJobVehicle = {}, x = 100, z = 200}
    vehicle.rootNode = vehicle
    vehicle.hotspot = {vehicle = vehicle, getVehicle = function(h) return h.vehicle end}
    function vehicle:getOwnerFarmId() return self.farmId end
    function vehicle:getIsAIActive() return self.aiJob ~= nil end
    -- AIFieldWorker: the implement list follows canFieldWork; isActive is true while field work runs.
    vehicle.spec_aiFieldWorker = setmetatable({isActive = false}, {__index = function(_, key)
        if key == "aiImplementList" then return vehicle.canFieldWork and {{}} or {} end
    end})
    function vehicle:getCanStartFieldWork()
        local spec = self.spec_aiFieldWorker
        if spec.isActive then return false end
        return #spec.aiImplementList > 0
    end
    function vehicle:getJob() return self.aiJob end
    function vehicle:getName() return "Tractor " .. self.networkId end
    function vehicle:getImageFilename() return "store/tractor" .. self.networkId .. ".dds" end
    function vehicle:getUniqueId() return self.uniqueId end
    function vehicle:getMapHotspot() return self.hotspot end
    function vehicle:getOwnerConnection() return self.ownerConnection end
    function vehicle:stopCurrentAIJob(aiMessage) g_currentMission.aiSystem:stopJob(self.aiJob, aiMessage) end
    -- Vehicle:getRootVehicle / getChildVehicles (the list includes the root itself).
    vehicle.childVehicles = {vehicle}
    function vehicle:getRootVehicle() return self end
    function vehicle:getChildVehicles() return self.childVehicles end
    objects[networkId] = vehicle
    return vehicle
end

-- An attached implement with the given specialization tables (spec_plow = {}, ...).
function attachImplement(vehicle, specs)
    local implement = {fillTypes = {}, fillLevels = {}}
    for name, spec in pairs(specs) do implement[name] = spec end
    function implement:getSprayerFillUnitIndex() return 1 end
    function implement:getFillUnitFillType(index) return self.fillTypes[index] end
    function implement:getFillUnitFillLevel(index)
        return self.fillLevels[index] or (self.fillTypes[index] ~= nil and 1000 or 0)
    end
    table.insert(vehicle.childVehicles, implement)
    return implement
end

-- Field state at a point: the state of the field whose square contains it (FieldState:update).
FieldGroundType = {NONE = 1, STUBBLE_TILLAGE = 2, CULTIVATED = 3, SEEDBED = 4, PLOWED = 5, ROLLED_SEEDBED = 6, RIDGE = 7,
    SOWN = 8, DIRECT_SOWN = 9, PLANTED = 10, RIDGE_SOWN = 11, ROLLER_LINES = 12, HARVEST_READY = 13,
    HARVEST_READY_OTHER = 14, GRASS = 15, GRASS_CUT = 16}
FruitType = {UNKNOWN = 0}
FieldDensityMap = {SPRAY_LEVEL = "SPRAY_LEVEL"}
Platform = {gameplay = {useRolling = true, useLimeCounter = true, hasWeeder = true}}
SowingMachine = {AI_REQUIRED_GROUND_TYPES = {FieldGroundType.STUBBLE_TILLAGE, FieldGroundType.CULTIVATED,
    FieldGroundType.SEEDBED, FieldGroundType.PLOWED, FieldGroundType.ROLLED_SEEDBED, FieldGroundType.RIDGE},
    AI_OUTPUT_GROUND_TYPES = {FieldGroundType.SOWN, FieldGroundType.DIRECT_SOWN, FieldGroundType.PLANTED,
        FieldGroundType.RIDGE_SOWN, FieldGroundType.ROLLER_LINES, FieldGroundType.HARVEST_READY,
        FieldGroundType.HARVEST_READY_OTHER, FieldGroundType.GRASS, FieldGroundType.GRASS_CUT}}
-- Field spray types: FieldState keeps the type, the density map and spray types the value
-- (decompiled field/FieldSprayType.lua). Types and values differ, as in the game.
FieldSprayType = {NONE = 1, FERTILIZER = 2, LIME = 3, MANURE = 4, LIQUID_MANURE = 5,
    VALUES = {NONE = 0, FERTILIZER = 1, LIME = 2, MANURE = 3, LIQUID_MANURE = 4}}
function FieldSprayType.getTypeByValue(value)
    for name, v in pairs(FieldSprayType.VALUES) do
        if v == value then return FieldSprayType[name] end
    end
end
-- Ground type layer: field ground inside each field (40 m around its point, so neighbouring
-- fields 100 m apart keep a 20 m strip between them) and on strips the player worked
-- (workedStrips, {x1, z1, x2, z2} rectangles). Values differ from types, as in the game.
FieldDensityMap.GROUND_TYPE = "GROUND_TYPE"
function FieldGroundType.getTypeByValue(value) return (value or 0) + 1 end
workedStrips = {}
function groundValueAt(x, z)
    for _, field in ipairs(g_fieldManager.fields) do
        if math.abs(field.posX - x) <= 40 and math.abs(field.posZ - z) <= 40 then return field.state.groundType - 1 end
    end
    for _, strip in ipairs(workedStrips) do
        if x >= strip[1] and x <= strip[3] and z >= strip[2] and z <= strip[4] then return FieldGroundType.CULTIVATED - 1 end
    end
    return 0
end
FieldState = {}
FieldState.__index = FieldState
function FieldState.new() return setmetatable({isValid = false, groundType = FieldGroundType.NONE}, FieldState) end
function FieldState:update(x, z)
    fieldStateReads = (fieldStateReads or 0) + 1
    for _, field in ipairs(g_fieldManager.fields) do
        if math.abs(field.posX - x) <= 50 and math.abs(field.posZ - z) <= 50 then
            for key, value in pairs(field.state) do self[key] = value end
            self.isValid = true
            return
        end
    end
end
-- Fruits with the FruitTypeDesc checks the Mod uses: wheat (growing 1-3, harvest 4,
-- withered 5, cut 6, mulched 7), grass (growing 1-2, harvest 3), potato (foliage 4, harvest 5).
-- getIsHarvestable includes the forage states, like the game's harvest transitions
-- (FruitTypeDesc.lua:483/695); getIsGrowing ends before minHarvestingGrowthState (:713).
local function fruit(index, title, ranges)
    local desc = {index = index, title = title, mulchedState = ranges.mulched or 0,
        minHarvestingGrowthState = ranges.minHarvest, maxHarvestingGrowthState = ranges.maxHarvest,
        minForageGrowthState = ranges.minForage or 0}
    function desc:getIsGrowing(gs) return gs > 0 and gs < ranges.minHarvest and gs ~= ranges.prepare end
    function desc:getIsHarvestable(gs) return gs >= (ranges.minForage or ranges.minHarvest) and gs <= ranges.maxHarvest end
    function desc:getIsPreparable(gs) return gs == ranges.prepare end
    function desc:getIsWithered(gs) return gs == ranges.withered end
    function desc:getIsCut(gs) return gs == ranges.cut end
    function desc:getIsWeedable(gs) return gs > 0 and gs <= 2 end
    function desc:getIsHoeable(gs) return gs > 0 and gs <= 2 end
    return desc
end
FRUIT = {WHEAT = 1, GRASS = 2, POTATO = 3, MAIZE = 4}
-- Fill types here are their names, as in the spray type double below.
FillType = FillType or {}
FillType.STRAW, FillType.GRASS_WINDROW = "STRAW", "GRASS_WINDROW"
g_fruitTypeManager = {fruits = {
    fruit(1, "Wheat", {minHarvest = 4, maxHarvest = 4, withered = 5, cut = 6, mulched = 7}),
    fruit(2, "Grass", {minHarvest = 3, maxHarvest = 3, cut = 4}),
    fruit(3, "Potato", {minHarvest = 5, maxHarvest = 5, prepare = 4, cut = 6}),
    fruit(4, "Maize", {minForage = 3, minHarvest = 4, maxHarvest = 4, cut = 6})
}}
function g_fruitTypeManager:getFruitTypeByIndex(index) return self.fruits[index] end
g_sprayTypeManager = {}
function g_sprayTypeManager:getSprayTypeByFillTypeIndex(fillType)
    if fillType == nil then return nil end
    -- sprayGroundType is a density map value, as SprayTypeManager stores it; solid and liquid
    -- fertilizer share the FERTILIZER ground (maps_sprayTypes.xml), herbicide has none.
    local groundTypes = {FERTILIZER = FieldSprayType.VALUES.FERTILIZER, LIQUIDFERTILIZER = FieldSprayType.VALUES.FERTILIZER,
        LIME = FieldSprayType.VALUES.LIME}
    return {isLime = fillType == "LIME", isHerbicide = fillType == "HERBICIDE",
        isFertilizer = fillType == "FERTILIZER" or fillType == "LIQUIDFERTILIZER", sprayGroundType = groundTypes[fillType]}
end

-- Farmland squares of 100 m; the field of a farmland has the farmland's id.
g_farmlandManager = {owners = {}}
function g_farmlandManager:getFarmlandOwner(id) return self.owners[id] or 0 end
function g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
    local farmland = self:getFarmlandAtWorldPosition(x, z)
    return farmland ~= nil and farmland.id or 0
end
function g_farmlandManager:getFarmlandAtWorldPosition(x, z)
    for _, field in ipairs(g_fieldManager.fields) do
        if math.abs(field.posX - x) <= 50 and math.abs(field.posZ - z) <= 50 then return field.farmland end
    end
end
g_fieldManager = {fields = {}}
function g_fieldManager:getFields() return self.fields end
function g_fieldManager:getFieldById(id)
    for _, field in ipairs(self.fields) do if field.farmland.id == id then return field end end
end
function mockField(id, x, z, area, ownerFarmId, state)
    local field = {farmland = {id = id}, posX = x, posZ = z, areaHa = area}
    field.state = {groundType = FieldGroundType.STUBBLE_TILLAGE, fruitTypeIndex = 0, growthState = 0, sprayLevel = 0,
        limeLevel = 1, plowLevel = 1, rollerLevel = 0, weedState = 0, stoneLevel = 0}
    for key, value in pairs(state or {}) do field.state[key] = value end
    function field:getId() return self.farmland.id end
    function field:getAreaHa() return self.areaHa end
    function field:getCenterOfFieldWorldPosition() return self.posX, self.posZ end
    -- As on real maps, the name sign stands off the worked area (here outside every field
    -- square), so a state read there finds no field ground.
    function field:getIndicatorPosition() return self.posX + 80, self.posZ + 80 end
    table.insert(g_fieldManager.fields, field)
    g_farmlandManager.owners[id] = ownerFarmId
    return field
end
g_missionManager = {missions = {}}
function g_missionManager:getMissionsByFarmId(farmId)
    local result = {}
    for _, mission in ipairs(self.missions) do
        if mission.farmId == nil or mission.farmId == farmId then table.insert(result, mission) end
    end
    return result
end
function mockContract(field, farmId, title, completion, status, typeName)
    -- type is the registered mission type (MissionManager:registerMissionType), e.g. plowMission.
    local contract = {field = field, farmId = farmId, title = title, completion = completion, status = status or "running",
        type = typeName ~= nil and {name = typeName} or nil}
    function contract:getIsInProgress() return self.status == "running" end
    function contract:getField() return self.field end
    function contract:getWorldPosition() return self.field:getIndicatorPosition() end
    function contract:getTitle() return self.title end
    table.insert(g_missionManager.missions, contract)
    return contract
end

function newMission(isServer)
    local mission = setmetatable({isServer = isServer, farmId = 1, allowed = true, paused = false,
        notifications = {}, updateables = {}, mapHotspots = {}, stations = {loading = {}, unloading = {}}},
        {__index = FSBaseMission})
    mission.aiSystem = AISystem.new()
    mission.aiJobTypeManager = AIJobTypeManager.new()
    mission.accessHandler = {canPlayerAccess = function() return true end}
    mission.vehicleSystem = {getVehicleByUniqueId = function(_, uniqueId)
        for _, object in pairs(objects) do
            if object.uniqueId == uniqueId then return object end
        end
    end}
    mission.missionInfo = {isValid = true, savegameDirectory = "savegame1", plowingRequiredEnabled = true,
        limeRequired = true, weedsEnabled = true, stonesEnabled = true}
    mission.fieldGroundSystem = {
        getMaxValue = function(_, layer) assert(layer == "SPRAY_LEVEL"); return 2 end,
        getValueAtWorldPos = function(_, layer, x, _, z) assert(layer == "GROUND_TYPE"); return groundValueAt(x, z) end
    }
    mission.stoneSystem = {getMinMaxValues = function() return 2, 4 end, getMaskValue = function() return 1 end}
    -- Weed replacement tables: the weeder takes small weeds, the hoe also medium ones,
    -- herbicide all three states.
    mission.weedSystem = {
        getWeederReplacements = function(_, isHoe)
            return {weed = {replacements = isHoe and {[1] = 0, [2] = 0} or {[1] = 0}}}
        end,
        getHerbicideReplacements = function() return {weed = {replacements = {[1] = 0, [2] = 0, [3] = 0}}} end
    }
    mission.userManager = {getUserIdByConnection = function(_, connection) return connection ~= nil and connection.userId or nil end}
    return mission
end

g_currentMission = newMission(true)
g_localPlayer = {farmId = 1}
function g_localPlayer:getCurrentVehicle() return self.vehicle end
function g_localPlayer:getPosition() return 11, 0, 22 end
g_guidedTourManager = {getIsTourRunning = function() return false end}

-- The in-game menu opens the map page synchronously (InGameMenu:openMapOverview →
-- TabbedMenu:onPageChange → InGameMenuMapFrame:onFrameOpen).
InGameMenu = {}
function InGameMenu:openMapOverview()
    self.opened = (self.opened or 0) + 1
    self.pageMapOverview:onFrameOpen()
end
g_inGameMenu = setmetatable({}, {__index = InGameMenu})
PlayerInputComponent = {}
function PlayerInputComponent:registerGlobalPlayerActionEvents(context) end

-- Host: the server connection is the local stream; Connection:sendEvent runs the event
-- directly with the local client connection, which is not a server connection.
localConnection = {farmId = 1, allowed = true, getIsServer = function() return false end, getIsLocal = function() return true end}
g_client = {getServerConnection = function()
    return {sendEvent = function(_, event) event:run(localConnection) end}
end}
broadcasts = {}
g_server = {broadcastEvent = function(_, event, sendLocal, ignore, ghost)
    assert(sendLocal == false and ignore == nil and ghost == event.vehicle)
    table.insert(broadcasts, event)
end}
