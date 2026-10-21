-- Map Helper: command queues for AI workers. The server owns every queue; clients
-- only hold copies received through MHQueueStateEvent and send requests.
MapHelper = {}
local MH = MapHelper

MH.MOD_NAME = g_currentModName
MH.MOD_DIRECTORY = g_currentModDirectory
MH.LOG_PREFIX = "[Map Helper]"
MH.MAX_ENTRIES = 10
MH.ADVANCE_DELAY = 1500
MH.SAVE_FILENAME = "mapHelper.xml"
MH.SAVE_VERSION = 1

MH.ACTION = {ADD = 1, REMOVE = 2, CLEAR = 3, START = 4, MOVE = 5, EDIT = 6}
MH.ACTION_NUM_BITS = 3
MH.PAUSE = {NONE = 0, STOPPED = 1, START_FAILED = 2, INVALID = 3}
MH.PAUSE_NUM_BITS = 2
MH.NOTIFY = {NONE = 0, PAUSED = 1, FINISHED = 2}
MH.NOTIFY_NUM_BITS = 2

-- Engine class tables survive map changes, this table does not: start every mission clean.
MH.queues = {}
MH.nextEntryId = 1
MH.features = {page = false, queue = false, hotkey = false}
MH.missionActive = false
MH.warnings = {}
MH.listeners = {}

function MH.warnOnce(key, message, ...)
    if not MH.warnings[key] then
        MH.warnings[key] = true
        Logging.warning(MH.LOG_PREFIX .. " " .. message, ...)
    end
end

function MH.text(key)
    return g_i18n:getText(key, MH.MOD_NAME)
end

function MH.getIsServer()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end

function MH.getJobTypeManager()
    return g_currentMission ~= nil and g_currentMission.aiJobTypeManager or nil
end

function MH.createJob(jobTypeIndex)
    local manager = MH.getJobTypeManager()
    if manager == nil or jobTypeIndex == nil then
        return nil
    end
    return manager:createJob(jobTypeIndex)
end

function MH.getJobTypeIndex(job)
    local manager = MH.getJobTypeManager()
    if manager == nil or job == nil then
        return nil
    end
    return manager:getJobTypeIndex(job) or job.jobTypeIndex
end

-- Jobs are never deleted, only dropped. AIJob:delete (SDK ai/jobs/AIJob.lua:41-48) calls
-- delete on every parameter, and no AIParameter class has one, so it raises; the game itself
-- never deletes a job either and lets finished jobs go out of scope.

-- AIJobFieldWork:readStream stores the sender's worker settings in pendingData and
-- AIJobFieldWork:update applies them on the job's first update; AIJobFieldWork:writeStream
-- writes the vehicle's current settings instead, and AIJob:saveToXMLFile keeps none.
-- A queued job is started later through AISystem:startJob, whose AIJobStartEvent sends
-- the vehicle's settings of that moment. So queued field work always uses the settings
-- the vehicle has when the job starts: drop the stale copy that came with the request.
-- AIJobFieldWork:setValues already assigns the vehicle to its tasks.
function MH.useVehicleSettingsAtStart(job)
    if job ~= nil and job.pendingVehicle ~= nil then
        job.pendingData = nil
        job.pendingVehicle = nil
    end
end

function MH.getVehicleExists(vehicle)
    return vehicle ~= nil and not vehicle.isDeleted and not vehicle.isDeleting
end

-- Vehicles with <ai supportsAIJobs="false"> (AIJobVehicle.lua:124, e.g. the Emergency pack's
-- hose reel and traffic cart) can never take a worker.
function MH.getSupportsAI(vehicle)
    return MH.getVehicleExists(vehicle) and vehicle.spec_aiJobVehicle ~= nil
        and vehicle.spec_aiJobVehicle.supportsAIJobs ~= false
end

-- Same permission as the vanilla job start (AIJobGoTo/AIJobFieldWork:getIsStartable):
-- the hireAssistant right for the vehicle's farm, plus the requester's farm must own it.
function MH.getCanManage(vehicle, connection)
    if not MH.getSupportsAI(vehicle) then
        return false
    end
    local farmId = vehicle:getOwnerFarmId()
    if farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID then
        return false
    end
    local mission = g_currentMission
    if mission:getFarmId(connection) ~= farmId then
        return false
    end
    return mission:getHasPlayerPermission("hireAssistant", connection, farmId)
end

function MH.getJobVehicle(job)
    if job == nil or job.getNamedParameter == nil then
        return nil
    end
    local parameter = job:getNamedParameter("vehicle")
    if parameter == nil or parameter.getVehicle == nil then
        return nil
    end
    return parameter:getVehicle()
end

function MH.getQueue(vehicle, create)
    local queue = MH.queues[vehicle]
    if queue == nil and create then
        queue = {vehicle = vehicle, farmId = vehicle:getOwnerFarmId(), entries = {}, running = false,
            pause = MH.PAUSE.NONE}
        MH.queues[vehicle] = queue
    end
    return queue
end

function MH.getEntries(vehicle)
    local queue = MH.queues[vehicle]
    return queue ~= nil and queue.entries or {}
end

function MH.allocateEntryId()
    local id = MH.nextEntryId
    MH.nextEntryId = id + 1
    return id
end

-- Dropping the entries is all the cleanup a queued job needs (see the note above).
function MH.clearEntries(queue)
    queue.entries = {}
end

function MH.deleteQueue(vehicle)
    MH.queues[vehicle] = nil
end

-- A queue without entries, worker or message has nothing to show or keep.
function MH.pruneQueue(queue)
    if #queue.entries == 0 and not queue.running and queue.pause == MH.PAUSE.NONE then
        if MH.queues[queue.vehicle] == queue then
            MH.queues[queue.vehicle] = nil
        end
    end
end

function MH.setPause(queue, pause, startState, startJobTypeIndex)
    queue.pause = pause
    queue.startState = startState
    queue.startJobTypeIndex = startJobTypeIndex
end

function MH.addListener(callback, target)
    table.insert(MH.listeners, {callback = callback, target = target})
end

function MH.removeListener(target)
    for i = #MH.listeners, 1, -1 do
        if MH.listeners[i].target == target then
            table.remove(MH.listeners, i)
        end
    end
end

function MH.notifyListeners(vehicle)
    for _, listener in ipairs(MH.listeners) do
        listener.callback(listener.target, vehicle)
    end
end

-- Server: send the complete queue of one vehicle to every client that knows the vehicle.
function MH.publish(queue, notify)
    notify = notify or MH.NOTIFY.NONE
    if g_server ~= nil then
        g_server:broadcastEvent(MHQueueStateEvent.new(queue.vehicle, queue, notify), false, nil, queue.vehicle)
    end
    MH.showNotification(queue, notify)
    MH.pruneQueue(queue)
    MH.notifyListeners(queue.vehicle)
end

-- Client: replace the local copy with the server state.
function MH.applyState(vehicle, state, notify)
    if not MH.getVehicleExists(vehicle) then
        return
    end
    local queue = MH.getQueue(vehicle, true)
    MH.clearEntries(queue)
    queue.entries = state.entries
    queue.running = state.running
    queue.farmId = state.farmId
    MH.setPause(queue, state.pause, state.startState, state.startJobTypeIndex)
    MH.showNotification(queue, notify)
    MH.pruneQueue(queue)
    MH.notifyListeners(vehicle)
end

function MH.showNotification(queue, notify)
    if notify == nil or notify == MH.NOTIFY.NONE or g_localPlayer == nil or g_localPlayer.farmId ~= queue.farmId then
        return
    end
    local mission = g_currentMission
    local name = queue.vehicle:getName()
    if notify == MH.NOTIFY.PAUSED then
        mission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(MH.text("mh_notifyPaused"), name, #queue.entries))
    elseif notify == MH.NOTIFY.FINISHED then
        mission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(MH.text("mh_notifyFinished"), name))
    end
end

-- Requests ---------------------------------------------------------------------
-- Every change goes through MHQueueRequestEvent. On the host the event runs
-- locally without serialization (Connection:sendEvent on the local stream).
-- flag: ADD = insert as the next entry instead of at the end; MOVE = move up (earlier).
function MH.sendRequest(action, vehicle, job, entryId, flag)
    if g_client == nil then
        return false
    end
    g_client:getServerConnection():sendEvent(MHQueueRequestEvent.new(action, vehicle, job, entryId, flag))
    return true
end

function MH.requestAdd(vehicle, job, insertNext)
    return MH.sendRequest(MH.ACTION.ADD, vehicle, job, nil, insertNext == true)
end

function MH.requestEdit(vehicle, entryId, job)
    return MH.sendRequest(MH.ACTION.EDIT, vehicle, job, entryId, false)
end

function MH.requestMove(vehicle, entryId, up)
    return MH.sendRequest(MH.ACTION.MOVE, vehicle, nil, entryId, up == true)
end

function MH.requestRemove(vehicle, entryId)
    return MH.sendRequest(MH.ACTION.REMOVE, vehicle, nil, entryId, false)
end

function MH.requestClear(vehicle)
    return MH.sendRequest(MH.ACTION.CLEAR, vehicle, nil, nil, false)
end

function MH.requestStart(vehicle)
    return MH.sendRequest(MH.ACTION.START, vehicle, nil, nil, false)
end

function MH.handleRequest(action, vehicle, job, entryId, connection, flag)
    if not MH.getIsServer() or not MH.features.queue then
        return false
    end
    if not MH.getCanManage(vehicle, connection) then
        return false
    end
    if action == MH.ACTION.ADD then
        return MH.serverAdd(vehicle, job, flag == true)
    elseif action == MH.ACTION.EDIT then
        return MH.serverEdit(vehicle, entryId, job)
    elseif action == MH.ACTION.MOVE then
        return MH.serverMove(vehicle, entryId, flag == true)
    elseif action == MH.ACTION.REMOVE then
        return MH.serverRemove(vehicle, entryId)
    elseif action == MH.ACTION.CLEAR then
        return MH.serverClear(vehicle)
    elseif action == MH.ACTION.START then
        return MH.serverStart(vehicle)
    end
    return false
end

-- Server-side check of a job sent by a client, the same for new and edited entries:
-- it must be for this vehicle and pass the native validation for the vehicle's farm.
function MH.getIsValidRequestJob(vehicle, job, farmId)
    if job == nil or MH.getJobVehicle(job) ~= vehicle then
        return false
    end
    MH.useVehicleSettingsAtStart(job)
    job:setValues()
    return job:validate(farmId) == true
end

function MH.findEntry(queue, entryId)
    if queue ~= nil and entryId ~= nil then
        for index, entry in ipairs(queue.entries) do
            if entry.id == entryId then
                return index, entry
            end
        end
    end
    return nil, nil
end

function MH.serverAdd(vehicle, job, insertNext)
    local queue = MH.getQueue(vehicle, true)
    if #queue.entries >= MH.MAX_ENTRIES or not MH.getIsValidRequestJob(vehicle, job, queue.farmId) then
        MH.pruneQueue(queue)
        return false
    end
    local position = insertNext and 1 or #queue.entries + 1
    table.insert(queue.entries, position, {id = MH.allocateEntryId(), job = job})
    MH.setPause(queue, MH.PAUSE.NONE)
    -- Added while a worker drives: the queue follows that job and continues after it,
    -- whether it came from the queue or was started directly.
    if not queue.running and vehicle:getIsAIActive() and vehicle.getJob ~= nil then
        local current = vehicle:getJob()
        if current ~= nil then
            queue.running = true
            queue.runningJob = current
        end
    end
    MH.publish(queue)
    return true
end

-- Replaces the job of a waiting entry; the entry keeps its id and place. An entry that
-- started or was removed in the meantime can no longer be edited.
function MH.serverEdit(vehicle, entryId, job)
    local queue = MH.queues[vehicle]
    local _, entry = MH.findEntry(queue, entryId)
    if entry == nil or not MH.getIsValidRequestJob(vehicle, job, queue.farmId) then
        return false
    end
    entry.job = job
    MH.publish(queue)
    return true
end

function MH.serverMove(vehicle, entryId, up)
    local queue = MH.queues[vehicle]
    local index, entry = MH.findEntry(queue, entryId)
    if index == nil then
        return false
    end
    local target = up and index - 1 or index + 1
    if target < 1 or target > #queue.entries then
        return false
    end
    queue.entries[index] = queue.entries[target]
    queue.entries[target] = entry
    MH.publish(queue)
    return true
end

function MH.serverRemove(vehicle, entryId)
    local queue = MH.queues[vehicle]
    local index = MH.findEntry(queue, entryId)
    if index == nil then
        return false
    end
    table.remove(queue.entries, index)
    if #queue.entries == 0 then
        MH.setPause(queue, MH.PAUSE.NONE)
    end
    MH.publish(queue)
    return true
end

function MH.serverClear(vehicle)
    local queue = MH.queues[vehicle]
    if queue == nil then
        return false
    end
    -- A worker that is already driving keeps its job; the queue just forgets it.
    MH.clearEntries(queue)
    queue.delay = nil
    queue.running = false
    queue.runningJob = nil
    MH.setPause(queue, MH.PAUSE.NONE)
    MH.publish(queue)
    return true
end

function MH.serverStart(vehicle)
    local queue = MH.queues[vehicle]
    if queue == nil or #queue.entries == 0 or vehicle:getIsAIActive() then
        return false
    end
    queue.delay = nil
    return MH.startNext(queue)
end

-- Same connection the vanilla start request would use: whoever is sitting in the
-- vehicle, so Enterable:getIsInUse does not report the player's own seat as busy.
function MH.getStartConnection(vehicle)
    local enterable = vehicle.spec_enterable
    if enterable ~= nil and enterable.isControlled and vehicle.getOwnerConnection ~= nil then
        return vehicle:getOwnerConnection()
    end
    return nil
end

function MH.pauseQueue(queue, pause, startState, startJobTypeIndex)
    queue.running = false
    queue.delay = nil
    queue.runningJob = nil
    if #queue.entries == 0 then
        MH.setPause(queue, MH.PAUSE.NONE)
        MH.publish(queue)
        return
    end
    MH.setPause(queue, pause, startState, startJobTypeIndex)
    MH.publish(queue, MH.NOTIFY.PAUSED)
end

-- Server: start the first entry through the native AI system. The entry only
-- leaves the queue once the native start has been accepted.
function MH.startNext(queue)
    local entry = queue.entries[1]
    if entry == nil then
        queue.running = false
        MH.publish(queue)
        return false
    end
    local job = entry.job
    job:setValues()
    if not job:validate(queue.farmId) then
        MH.pauseQueue(queue, MH.PAUSE.INVALID)
        return false
    end
    local startable, state = job:getIsStartable(MH.getStartConnection(queue.vehicle))
    if not startable then
        MH.pauseQueue(queue, MH.PAUSE.START_FAILED, state, MH.getJobTypeIndex(job))
        return false
    end
    table.remove(queue.entries, 1)
    queue.running = true
    queue.runningJob = job
    MH.setPause(queue, MH.PAUSE.NONE)
    MH.useVehicleSettingsAtStart(job)
    g_currentMission.aiSystem:startJob(job, queue.farmId)
    MH.publish(queue)
    return true
end

-- AIJob:update stops a job that ran out of tasks with AIMessageSuccessFinishedJob;
-- AIJobLoadAndDeliver ends with AIMessageSuccessSiloEmpty. Everything else, including
-- AIMessageSuccessStoppedByUser and nil (vehicle deleted), pauses the queue.
function MH.getIsSuccessfulFinish(aiMessage)
    if aiMessage == nil or aiMessage.isa == nil then
        return false
    end
    if AIMessageSuccessFinishedJob ~= nil and aiMessage:isa(AIMessageSuccessFinishedJob) then
        return true
    end
    return AIMessageSuccessSiloEmpty ~= nil and aiMessage:isa(AIMessageSuccessSiloEmpty)
end

-- MessageType.AI_JOB_STOPPED, published by AISystem:stopJobInternal on server and clients.
-- Not while the mission is deleted: FSBaseMission:delete deletes the AI system, which stops
-- every active job and publishes AI_JOB_STOPPED (SDK ai/AISystem.lua:97, :587).
function MH:onAIJobStopped(job, aiMessage)
    if not MH.missionActive or not MH.getIsServer() or job == nil then
        return
    end
    for _, queue in pairs(MH.queues) do
        if queue.runningJob == job then
            queue.runningJob = nil
            if MH.getIsSuccessfulFinish(aiMessage) and #queue.entries > 0 then
                -- The native job is removed from AISystem in its next update; start later.
                queue.delay = MH.ADVANCE_DELAY
                MH.publish(queue)
            elseif MH.getIsSuccessfulFinish(aiMessage) then
                queue.running = false
                MH.publish(queue, MH.NOTIFY.FINISHED)
            else
                MH.pauseQueue(queue, MH.PAUSE.STOPPED)
            end
            return
        end
    end
end

function MH:update(dt)
    -- Undo a planning shadow left behind by an error while the job menu was built.
    if MHMapFrame ~= nil then
        MHMapFrame.restorePlanning()
    end
    local isServer = MH.getIsServer()
    for vehicle, queue in pairs(MH.queues) do
        if not MH.getVehicleExists(vehicle) then
            MH.deleteQueue(vehicle)
        elseif isServer then
            if vehicle:getOwnerFarmId() ~= queue.farmId then
                MH.clearEntries(queue)
                queue.running = false
                queue.runningJob = nil
                queue.delay = nil
                MH.setPause(queue, MH.PAUSE.NONE)
                MH.publish(queue)
            elseif queue.delay ~= nil then
                queue.delay = queue.delay - dt
                if queue.delay <= 0 then
                    queue.delay = nil
                    if vehicle:getIsAIActive() then
                        MH.pauseQueue(queue, MH.PAUSE.STOPPED)
                    else
                        MH.startNext(queue)
                    end
                end
            end
        end
    end
end

-- Join: like AISystem:onClientJoined, send every queue after the native initial state.
function MH.sendInitialState(connection)
    for vehicle, queue in pairs(MH.queues) do
        if MH.getVehicleExists(vehicle) then
            connection:sendEvent(MHQueueStateEvent.new(vehicle, queue, MH.NOTIFY.NONE))
        end
    end
end

-- Global hotkey ------------------------------------------------------------------
-- Defined in modDesc <actions>; registered for on foot and in vehicles together with the
-- game's own global actions (PlayerInputComponent:registerGlobalPlayerActionEvents).
MH.HOTKEY_ACTION = "MH_OPEN_MAP_HELPER"

function MH:onOpenMapHelperAction()
    if MH.missionActive and MHMapFrame ~= nil then
        MHMapFrame.openFromHotkey()
    end
end

-- Appended to PlayerInputComponent:registerGlobalPlayerActionEvents(context). Like the game's
-- function, it registers into the given context (VEHICLE from Enterable, else the current
-- one) and switches the registration back afterwards. Registering twice in one context is
-- refused by InputBinding:registerActionEvent, so repeated calls are harmless.
function MH.registerHotkey(component, context)
    local inputBinding = g_inputBinding
    local action = InputAction[MH.HOTKEY_ACTION]
    -- The player registers its actions while the mission loads, before onStartMission.
    if inputBinding == nil or action == nil or component == nil
        or component.player == nil or not component.player.isOwner then
        return
    end
    MH.inputComponent = component
    local currentContext = inputBinding:getContextName()
    local targetContext = context or currentContext
    if targetContext ~= currentContext then
        inputBinding:beginActionEventsModification(targetContext)
    end
    local _, eventId = inputBinding:registerActionEvent(action, MH, MH.onOpenMapHelperAction, false, true, false, true)
    if eventId ~= nil and eventId ~= "" then
        -- Listed in the key help (F1) with the action's text input_MH_OPEN_MAP_HELPER.
        inputBinding:setActionEventTextVisibility(eventId, true)
        inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_LOW)
    end
    if targetContext ~= currentContext then
        inputBinding:beginActionEventsModification(currentContext)
    end
end

-- Labels -------------------------------------------------------------------------
function MH.getJobTitle(job)
    local manager = MH.getJobTypeManager()
    local jobType = manager ~= nil and manager:getJobTypeByIndex(MH.getJobTypeIndex(job)) or nil
    return jobType ~= nil and jobType.title or "?"
end

-- "Field No. 12" for a position inside a field, nil elsewhere. Fields are keyed by their
-- farmland id (FieldManager:getFieldById), the farmland comes from the map position.
function MH.getFieldNameAt(x, z)
    if g_farmlandManager == nil or g_fieldManager == nil or x == nil or z == nil then
        return nil
    end
    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
    local field = farmland ~= nil and g_fieldManager:getFieldById(farmland.id) or nil
    if field ~= nil and field:getId() ~= nil then
        return string.format("%s %s", g_i18n:getText("ui_fieldNo"), tostring(field:getId()))
    end
    return nil
end

-- Every target the player picked, in the job menu's order: positions (as field name or
-- map coordinates) and stations, joined like "Silo > Mill".
function MH.getJobTargets(job)
    local targets = {}
    if job == nil or job.getGroupedParameters == nil then
        return ""
    end
    for _, group in ipairs(job:getGroupedParameters()) do
        for _, parameter in ipairs(group:getParameters()) do
            local parameterType = parameter:getType()
            if parameterType == AIParameterType.POSITION or parameterType == AIParameterType.POSITION_ANGLE then
                local x, z = parameter:getPosition()
                if x ~= nil and z ~= nil then
                    table.insert(targets, MH.getFieldNameAt(x, z)
                        or string.format("%d, %d", math.floor(x + 0.5), math.floor(z + 0.5)))
                end
            elseif parameterType == AIParameterType.UNLOADING_STATION or parameterType == AIParameterType.LOADING_STATION then
                local name = parameter:getString()
                if name ~= nil and name ~= "" then
                    table.insert(targets, name)
                end
            end
        end
    end
    return table.concat(targets, " > ")
end

-- Job type title plus its targets.
function MH.getJobLabel(job)
    local title = MH.getJobTitle(job)
    local targets = MH.getJobTargets(job)
    if targets == "" then
        return title
    end
    return string.format("%s - %s", title, targets)
end

function MH.getPauseReason(queue)
    if queue.pause == MH.PAUSE.STOPPED then
        return MH.text("mh_reasonStopped")
    elseif queue.pause == MH.PAUSE.INVALID then
        return MH.text("mh_reasonInvalid")
    elseif queue.pause == MH.PAUSE.START_FAILED then
        local manager = MH.getJobTypeManager()
        local jobType = manager ~= nil and manager:getJobTypeByIndex(queue.startJobTypeIndex) or nil
        local classObject = jobType ~= nil and jobType.classObject or nil
        if classObject ~= nil and classObject.getIsStartErrorText ~= nil and queue.startState ~= nil then
            return classObject.getIsStartErrorText(queue.startState)
        end
        return MH.text("mh_reasonStopped")
    end
    return nil
end

-- Savegame -----------------------------------------------------------------------
-- Same format as AIJobVehicle:saveToXMLFile uses for lastJob: job type name plus the
-- job's own AIJob:saveToXMLFile parameters. The vehicle parameter is restored from
-- the queue's vehicle because AIParameterVehicle has no loadFromXMLFile.
function MH.saveToXMLFile(filename)
    local manager = MH.getJobTypeManager()
    local xmlFile = XMLFile.create("mapHelperXML", filename, "mapHelper")
    if xmlFile == nil or manager == nil then
        return false
    end
    xmlFile:setInt("mapHelper#version", MH.SAVE_VERSION)
    local queues = {}
    for vehicle, queue in pairs(MH.queues) do
        local uniqueId = MH.getVehicleExists(vehicle) and vehicle:getUniqueId() or nil
        if uniqueId ~= nil and #queue.entries > 0 then
            table.insert(queues, {uniqueId = uniqueId, queue = queue})
        end
    end
    table.sort(queues, function(a, b) return a.uniqueId < b.uniqueId end)
    local usedModNames = {}
    for queueIndex, item in ipairs(queues) do
        local queueKey = string.format("mapHelper.queue(%d)", queueIndex - 1)
        xmlFile:setString(queueKey .. "#vehicleUniqueId", item.uniqueId)
        local jobIndex = 0
        for _, entry in ipairs(item.queue.entries) do
            local jobType = manager:getJobTypeByIndex(MH.getJobTypeIndex(entry.job))
            if jobType ~= nil then
                local jobKey = string.format("%s.job(%d)", queueKey, jobIndex)
                xmlFile:setString(jobKey .. "#type", jobType.name)
                entry.job:saveToXMLFile(xmlFile, jobKey, usedModNames)
                jobIndex = jobIndex + 1
            end
        end
    end
    xmlFile:save()
    xmlFile:delete()
    return true
end

function MH.loadFromXMLFile(filename)
    local mission = g_currentMission
    local manager = MH.getJobTypeManager()
    local xmlFile = XMLFile.loadIfExists("mapHelperXML", filename)
    if xmlFile == nil then
        return 0
    end
    local loaded, dropped = 0, 0
    if manager ~= nil and mission.vehicleSystem ~= nil then
        xmlFile:iterate("mapHelper.queue", function(_, queueKey)
            local uniqueId = xmlFile:getString(queueKey .. "#vehicleUniqueId")
            local vehicle = uniqueId ~= nil and mission.vehicleSystem:getVehicleByUniqueId(uniqueId) or nil
            local numJobs = 0
            xmlFile:iterate(queueKey .. ".job", function() numJobs = numJobs + 1 end)
            if not MH.getSupportsAI(vehicle) then
                dropped = dropped + numJobs
                return
            end
            local queue = MH.getQueue(vehicle, true)
            xmlFile:iterate(queueKey .. ".job", function(_, jobKey)
                local job = MH.createJob(manager:getJobTypeIndexByName(xmlFile:getString(jobKey .. "#type")))
                local parameter = job ~= nil and job:getNamedParameter("vehicle") or nil
                if parameter == nil or parameter.setVehicle == nil or #queue.entries >= MH.MAX_ENTRIES then
                            dropped = dropped + 1
                    return
                end
                job:loadFromXMLFile(xmlFile, jobKey)
                parameter:setVehicle(vehicle)
                job:setValues()
                table.insert(queue.entries, {id = MH.allocateEntryId(), job = job})
                loaded = loaded + 1
            end)
            MH.pruneQueue(queue)
        end)
    end
    xmlFile:delete()
    if dropped > 0 then
        Logging.info("%s Dropped %d saved queue jobs whose vehicle or job type no longer exists", MH.LOG_PREFIX, dropped)
    end
    return loaded
end

-- Mission lifecycle ---------------------------------------------------------------
function MH.onMissionStarted(mission)
    MH.missionActive = true
    if not MH.features.queue then
        return
    end
    g_messageCenter:subscribe(MessageType.AI_JOB_STOPPED, MH.onAIJobStopped, MH)
    mission:addUpdateable(MH)
    if mission:getIsServer() then
        local info = mission.missionInfo
        if info ~= nil and info.isValid and info.savegameDirectory ~= nil then
            MH.loadFromXMLFile(info.savegameDirectory .. "/" .. MH.SAVE_FILENAME)
        end
    end
end

-- Runs first in FSBaseMission:delete and only flips a flag, so nothing here can stop the
-- game's own teardown: every hook and callback of this Mod checks it and stays inert
-- while the mission is deleted (for example InGameMenuMapFrame:reset calling
-- setMapSelectionItem).
function MH.onMissionDeleting()
    MH.missionActive = false
end

-- Runs after FSBaseMission:delete. g_inGameMenu and its map frame are created once at
-- startup (main.lua) and reused by every mission; FSBaseMission:delete only resets them.
-- Remove everything this Mod added, so a later mission without the Mod gets the untouched
-- map page. Queued jobs are only dropped, never deleted (see MH.clearEntries).
function MH.onMissionDeleted(mission)
    MH.missionActive = false
    if MHMapFrame ~= nil then
        MHMapFrame.removeAll()
    end
    if g_inputBinding ~= nil then
        g_inputBinding:removeActionEventsByTarget(MH)
    end
    if g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(MH)
    end
    if mission ~= nil and mission.updateables ~= nil and mission.removeUpdateable ~= nil then
        mission:removeUpdateable(MH)
    end
    MH.queues = {}
    MH.listeners = {}
end

function MH.onSavegameSaved(missionInfo)
    if not MH.features.queue or not MH.getIsServer() or missionInfo == nil or not missionInfo.isValid
        or missionInfo.savegameDirectory == nil then
        return
    end
    MH.saveToXMLFile(missionInfo.savegameDirectory .. "/" .. MH.SAVE_FILENAME)
end
