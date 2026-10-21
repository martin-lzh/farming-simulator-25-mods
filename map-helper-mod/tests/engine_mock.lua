-- Contract doubles for the engine calls the Mod uses, not copies of game implementations.
g_currentModName = "FS25_MapHelper"
g_currentModDirectory = "map-helper-mod/"
g_modIsLoaded = {[g_currentModName] = true}
g_pixelSizeScaledX, g_pixelSizeScaledY = 1 / 1920, 1 / 1080
g_time = 0

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
    mh_notifyFinished = "%s finished", mh_queueFull = "Full at %d"
}
g_i18n = {getText = function(_, key) return texts[key] or key end}

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
function streamWriteInt32(s, v) push(s, v) end
function streamReadInt32(s) return pop(s) end
function streamWriteFloat32(s, v) push(s, v) end
function streamReadFloat32(s) return pop(s) end
function streamWriteBool(s, v) push(s, v and true or false); return v end
function streamReadBool(s) return pop(s) end

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
AIJobType = {GOTO = 1, FIELDWORK = 2, LOADANDDELIVER = 3}

-- Jobs: the parameters and native serialization an AIJob exposes.
local VehicleParameter = {}
VehicleParameter.__index = VehicleParameter
function VehicleParameter:getType() return AIParameterType.TEXT end
function VehicleParameter:setVehicle(vehicle) self.vehicleId = NetworkUtil.getObjectId(vehicle) end
function VehicleParameter:getVehicle() return NetworkUtil.getObject(self.vehicleId) end

local PositionParameter = {}
PositionParameter.__index = PositionParameter
function PositionParameter:getType() return AIParameterType.POSITION_ANGLE end
function PositionParameter:setPosition(x, z) self.x, self.z = x, z end
function PositionParameter:getPosition() return self.x, self.z end

local StationParameter = {}
StationParameter.__index = StationParameter
function StationParameter:getType() return AIParameterType.LOADING_STATION end
function StationParameter:getString() return self.name or "" end

local function group(parameter)
    return {getParameters = function() return {parameter} end}
end

MockJob = {}
MockJob.__index = MockJob
function MockJob.new(typeIndex)
    local self = setmetatable({jobTypeIndex = typeIndex, setValuesCount = 0, valid = true, resetCount = 0}, MockJob)
    self.vehicleParameter = setmetatable({}, VehicleParameter)
    self.namedParameters = {{name = "vehicle", parameter = self.vehicleParameter}}
    self.groups = {group(self.vehicleParameter)}
    if typeIndex == AIJobType.LOADANDDELIVER then
        self.stationParameter = setmetatable({}, StationParameter)
        table.insert(self.namedParameters, {name = "loadingStation", parameter = self.stationParameter})
        table.insert(self.groups, group(self.stationParameter))
    else
        self.positionParameter = setmetatable({}, PositionParameter)
        table.insert(self.namedParameters, {name = "positionAngle", parameter = self.positionParameter})
        table.insert(self.groups, group(self.positionParameter))
    end
    return self
end
function MockJob:getNamedParameter(name)
    for _, item in ipairs(self.namedParameters) do
        if item.name:upper() == name:upper() then return item.parameter end
    end
end
function MockJob:getGroupedParameters() return self.groups end
function MockJob:setValues() self.setValuesCount = self.setValuesCount + 1 end
function MockJob:resetTasks() self.resetCount = self.resetCount + 1 end
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
    return true, 0
end
function MockJob:writeStream(s, connection)
    streamWriteBool(s, false)
    if streamWriteBool(s, self.jobId ~= nil) then streamWriteInt32(s, self.jobId) end
    push(s, self.vehicleParameter.vehicleId or 0)
    if self.positionParameter ~= nil then
        push(s, self.positionParameter.x); push(s, self.positionParameter.z)
    else
        push(s, self.stationParameter.name or "")
    end
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
    self.vehicleParameter.vehicleId = pop(s)
    if self.positionParameter ~= nil then
        self.positionParameter.x = pop(s); self.positionParameter.z = pop(s)
    else
        self.stationParameter.name = pop(s)
    end
    self:setValues()
    streamReadUInt8(s)
    -- Like AIJobFieldWork:readStream: keep the sender's settings until the first update.
    if self.jobTypeIndex == AIJobType.FIELDWORK and streamReadBool(s) then
        self.pendingData = pop(s)
        self.pendingVehicle = true
    end
end
function MockJob:saveToXMLFile(xmlFile, key)
    xmlFile:setString(key .. ".parameter(0)#name", "vehicle")
    if self.positionParameter ~= nil then
        xmlFile:setString(key .. ".parameter(1)#name", "positionAngle")
        xmlFile:setFloat(key .. ".parameter(1)#x", self.positionParameter.x)
        xmlFile:setFloat(key .. ".parameter(1)#z", self.positionParameter.z)
    else
        xmlFile:setString(key .. ".parameter(1)#name", "loadingStation")
        xmlFile:setString(key .. ".parameter(1)#station", self.stationParameter.name)
    end
    return true
end
function MockJob:loadFromXMLFile(xmlFile, key)
    if self.positionParameter ~= nil then
        self.positionParameter.x = xmlFile:getFloat(key .. ".parameter(1)#x")
        self.positionParameter.z = xmlFile:getFloat(key .. ".parameter(1)#z")
    else
        self.stationParameter.name = xmlFile:getString(key .. ".parameter(1)#station")
    end
end
function MockJob:delete() self.deleted = true end

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
        {name = "LOADANDDELIVER", title = "Load and deliver", classObject = jobClass("Deliver")}
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
function AISystem:startJob(job, farmId)
    job.jobId = self.nextId
    self.nextId = self.nextId + 1
    job.startedFarmId = farmId
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
function FSBaseMission:delete() end
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

-- GUI doubles.
function mockElement(name)
    local e = {name = name, elements = {}, visible = true, disabled = false, text = "",
        absPosition = {0.5, 0.8}, absSize = {0.15, 0.03}, position = {0, 0}, size = {0.15, 0.03}}
    function e:setText(text) self.text = text end
    function e:setVisible(visible) self.visible = visible end
    function e:getIsVisible() return self.visible end
    function e:setDisabled(disabled) self.disabled = disabled end
    function e:getIsDisabled() return self.disabled end
    function e:updateAbsolutePosition() self.positioned = true end
    function e:setPosition(x, y) self.position = {x, y} end
    function e:setSize(x, y) self.size = {x or self.size[1], y or self.size[2]} end
    function e:invalidateLayout() self.layoutCount = (self.layoutCount or 0) + 1 end
    function e:addElement(child) table.insert(self.elements, child); child.parent = self end
    function e:unlinkElement()
        if self.parent ~= nil then
            for i, child in ipairs(self.parent.elements) do
                if child == self then table.remove(self.parent.elements, i); break end
            end
            self.parent = nil
        end
    end
    function e:delete() self:unlinkElement(); self.deleted = true end
    function e:getDescendantByName(wanted)
        for _, child in ipairs(self.elements) do
            if child.name == wanted then return child end
            local found = child:getDescendantByName(wanted)
            if found ~= nil then return found end
        end
    end
    function e:clone(parent)
        local copy = mockElement(self.name)
        copy.size = {self.size[1], self.size[2]}
        for _, child in ipairs(self.elements) do child:clone(copy) end
        if parent ~= nil then parent:addElement(copy) end
        return copy
    end
    return e
end

xmlHandles, nextXmlHandle = {}, 1
function loadXMLFile(_, path)
    local handle = nextXmlHandle
    nextXmlHandle = nextXmlHandle + 1
    xmlHandles[handle] = path
    return handle
end
function delete() end

FocusManager = {currentGui = "InGameMenu"}
function FocusManager:setGui(name) self.currentGui = name end
function FocusManager:setFocus(element) self.focused = element; return true end
function FocusManager:getFocusedElement() return self.focused end
function FocusManager:linkElements(a, direction, b) a.links = a.links or {}; a.links[direction] = b end
function FocusManager:removeElement() end
FocusManager.TOP, FocusManager.BOTTOM = 1, 2

DialogElement = {TYPE_INFO = 2, TYPE_WARNING = 1}
MessageDialog = {}
function MessageDialog.new(_, mt) return setmetatable({time = 0}, mt) end
function MessageDialog:onGuiSetupFinished() end
function MessageDialog:onCreate() self:setDialogType(DialogElement.TYPE_WARNING) end
function MessageDialog:setDialogType(dialogType) self.dialogType = dialogType end
function MessageDialog:onOpen() self.isOpen = true end
function MessageDialog:onClose() self.isOpen = false end
function MessageDialog:close() self:onClose(); g_gui.openDialog = nil end
function MessageDialog:update() end
function MessageDialog:delete() self.deleted = true end

infoDialogs = {}
InfoDialog = {show = function(text) table.insert(infoDialogs, text) end}

g_gui = {guis = {}, profiles = {}, presets = {}, nameScreenTypes = {}, profileLoads = 0, guiLoads = 0, recLoads = 0}
function g_gui:closeDialogByName(name) self.guis[name].target:close() end
function g_gui:loadProfileSet(xmlFile)
    self.profileLoads = self.profileLoads + 1
    local path = xmlHandles[xmlFile]
    if path:find("DrawerToggle") then self.profiles.mh_toggleContainer = {} end
    if path:find("QueueButton") then self.profiles.mh_queueContainer = {} end
end
function g_gui:loadGuiRec(xmlFile, _, parent, target)
    self.recLoads = self.recLoads + 1
    local path = xmlHandles[xmlFile]
    local root = mockElement("root")
    root:addElement(mockElement("text"))
    local button = mockElement("button")
    root:addElement(button)
    if path:find("DrawerToggle") then
        button.onClickCallback = target.onClickToggle
    elseif path:find("QueueButton") then
        button.onClickCallback = target.onClickAddToQueue
    end
    button.target = target
    parent:addElement(root)
end
function g_gui:loadGui(path, name, controller)
    self.guiLoads = self.guiLoads + 1
    controller.name = name
    local root = mockElement("root")
    for _, id in ipairs({"drawerPanel", "titleText", "statusText", "actionBox", "centerButton", "createButton",
        "startStopButton", "goToButton", "clearButton", "queueTitle", "queueRows", "queueEmptyText"}) do
        controller[id] = mockElement(id)
    end
    root:addElement(controller.drawerPanel)
    controller.queueRows.absSize = {0.2, 0.2}
    local row = mockElement("row")
    row:addElement(mockElement("label"))
    row:addElement(mockElement("remove"))
    controller.rowTemplate = row
    controller.drawerPanel:addElement(row)
    controller:onGuiSetupFinished()
    controller:onCreate()
    self.guis[name] = {target = controller, root = root, delete = function(gui) gui.deleted = true end}
    self.nameScreenTypes[name] = MHDrawerDialog
    return self.guis[name]
end
function g_gui:showDialog(name)
    local dialog = self.guis[name].target
    self.openDialog = dialog
    dialog:onOpen()
    dialog.time = dialog.time + 300
end
function g_gui:getIsDialogVisible() return self.openDialog ~= nil end

InputAction = {MH_TOGGLE_DRAWER = "MH_TOGGLE_DRAWER", MH_ADD_TO_QUEUE = "MH_ADD_TO_QUEUE"}
g_inputBinding = {events = {}, nextId = 1}
function g_inputBinding:registerActionEvent(action, target, callback)
    for _, event in ipairs(self.events) do
        assert(not (event.action == action and event.target == target), "duplicate action event")
    end
    local id = "event" .. self.nextId
    self.nextId = self.nextId + 1
    table.insert(self.events, {action = action, target = target, callback = callback, id = id})
    return true, id
end
function g_inputBinding:removeActionEventsByTarget(target)
    for i = #self.events, 1, -1 do
        if self.events[i].target == target then table.remove(self.events, i) end
    end
end
function g_inputBinding:setActionEventTextVisibility() end
function g_inputBinding:trigger(action)
    for _, event in ipairs(self.events) do
        if event.action == action then event.callback(event.target, action, 1) end
    end
end

IngameMapElement = {panToHotspot = function() end, setCenterToWorldPosition = function() end}

InGameMenuMapFrame = {AI_MODE_OVERVIEW = 1, AI_MODE_CREATE = 2}
function InGameMenuMapFrame:onLoadMapFinished() end
function InGameMenuMapFrame:registerInput() end
function InGameMenuMapFrame:setJobMenuVisible(isVisible) self.jobMenuVisible = isVisible end
function InGameMenuMapFrame:getIsPicking() return self.picking == true end
function InGameMenuMapFrame:setMapSelectionItem(hotspot) self.selected = hotspot end
function InGameMenuMapFrame:getCanStartJob()
    return self.mode == InGameMenuMapFrame.AI_MODE_CREATE and not self:getIsPicking() and g_currentMission:getHasPlayerPermission("hireAssistant")
end
-- Like the native flow: select, pan, then open the job menu after the permission check.
function InGameMenuMapFrame:setAIVehicle(vehicle)
    self:setMapSelectionItem(vehicle:getMapHotspot())
    self.ingameMap:panToHotspot(vehicle:getMapHotspot())
    if g_currentMission:getHasPlayerPermission("hireAssistant") then
        self.mode = InGameMenuMapFrame.AI_MODE_CREATE
        self.currentJobVehicle = vehicle
        self.currentJob = nil
        self:setJobMenuVisible(true)
        self.currentJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.GOTO)
        self.currentJob.vehicleParameter:setVehicle(vehicle)
        self.currentJob.positionParameter:setPosition(vehicle.x or 0, vehicle.z or 0)
    end
end
function InGameMenuMapFrame:onStartGoToJob() self.goToStarted = (self.goToStarted or 0) + 1 end
function InGameMenuMapFrame:onStartCancelJob() self.startCancel = (self.startCancel or 0) + 1 end
function InGameMenuMapFrame:onClickBack()
    if self.mode == InGameMenuMapFrame.AI_MODE_CREATE then
        self.currentJob:resetTasks()
        self.currentJobVehicle = nil
        self.mode = InGameMenuMapFrame.AI_MODE_OVERVIEW
        self:setJobMenuVisible(false)
    end
    return true
end
function InGameMenuMapFrame:updateWarnings() self.warningsUpdated = true end

function mockFrame()
    local frame = setmetatable({mode = InGameMenuMapFrame.AI_MODE_OVERVIEW, elements = {mockElement("frameRoot")}}, {__index = InGameMenuMapFrame})
    frame.shopMoneyBox = mockElement("shopMoneyBox")
    mockElement("header"):addElement(frame.shopMoneyBox)
    frame.createJobContainer = mockElement("createJobContainer")
    frame.ingameMap = {
        panToHotspot = function(map, hotspot) map.pannedTo = hotspot end,
        setCenterToWorldPosition = function(map, x, z) map.centered = {x, z} end
    }
    frame.jobTypeInstances = {
        [AIJobType.GOTO] = {getIsAvailableForVehicle = function(_, vehicle) return not vehicle:getIsAIActive() end},
        [AIJobType.FIELDWORK] = {getIsAvailableForVehicle = function(_, vehicle) return vehicle.canFieldWork == true end}
    }
    return frame
end

-- Mission, players and vehicles.
function mockVehicle(networkId, farmId, uniqueId)
    local vehicle = {networkId = networkId, farmId = farmId or 1, uniqueId = uniqueId or ("vehicle" .. networkId),
        spec_aiJobVehicle = {}, x = 100, z = 200}
    vehicle.hotspot = {vehicle = vehicle}
    function vehicle:getOwnerFarmId() return self.farmId end
    function vehicle:getIsAIActive() return self.aiJob ~= nil end
    function vehicle:getName() return "Tractor " .. self.networkId end
    function vehicle:getUniqueId() return self.uniqueId end
    function vehicle:getMapHotspot() return self.hotspot end
    function vehicle:getOwnerConnection() return self.ownerConnection end
    function vehicle:stopCurrentAIJob(aiMessage) g_currentMission.aiSystem:stopJob(self.aiJob, aiMessage) end
    objects[networkId] = vehicle
    return vehicle
end

function newMission(isServer)
    local mission = setmetatable({isServer = isServer, farmId = 1, allowed = true, paused = false,
        notifications = {}, updateables = {}}, {__index = FSBaseMission})
    mission.aiSystem = AISystem.new()
    mission.aiJobTypeManager = AIJobTypeManager.new()
    mission.accessHandler = {canPlayerAccess = function() return true end}
    mission.vehicleSystem = {getVehicleByUniqueId = function(_, uniqueId)
        for _, object in pairs(objects) do
            if object.uniqueId == uniqueId then return object end
        end
    end}
    mission.missionInfo = {isValid = true, savegameDirectory = "savegame1"}
    return mission
end

g_currentMission = newMission(true)
g_localPlayer = {farmId = 1}
function g_localPlayer:getCurrentVehicle() return self.vehicle end
function g_localPlayer:getPosition() return 11, 0, 22 end

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
