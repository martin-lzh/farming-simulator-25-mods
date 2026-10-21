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

MH.ACTION = {ADD = 1, REMOVE = 2, CLEAR = 3, START = 4}
MH.ACTION_NUM_BITS = 3
MH.PAUSE = {NONE = 0, STOPPED = 1, START_FAILED = 2, INVALID = 3}
MH.PAUSE_NUM_BITS = 2
MH.NOTIFY = {NONE = 0, PAUSED = 1, FINISHED = 2}
MH.NOTIFY_NUM_BITS = 2

-- Engine class tables survive map changes, this table does not: start every mission clean.
MH.queues = {}
MH.nextEntryId = 1
MH.features = {drawer = false, queue = false}
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

function MH.deleteJob(job)
    if job ~= nil and job.delete ~= nil then
        job:delete()
    end
end

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

function MH.getSupportsAI(vehicle)
    return MH.getVehicleExists(vehicle) and vehicle.spec_aiJobVehicle ~= nil
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

function MH.clearEntries(queue)
    for _, entry in ipairs(queue.entries) do
        MH.deleteJob(entry.job)
    end
    queue.entries = {}
end

function MH.deleteQueue(vehicle)
    local queue = MH.queues[vehicle]
    if queue ~= nil then
        MH.clearEntries(queue)
        MH.queues[vehicle] = nil
    end
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
        for _, entry in ipairs(state.entries) do
            MH.deleteJob(entry.job)
        end
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
function MH.sendRequest(action, vehicle, job, entryId)
    if g_client == nil then
        return false
    end
    g_client:getServerConnection():sendEvent(MHQueueRequestEvent.new(action, vehicle, job, entryId))
    return true
end

function MH.requestAdd(vehicle, job)
    return MH.sendRequest(MH.ACTION.ADD, vehicle, job, nil)
end

function MH.requestRemove(vehicle, entryId)
    return MH.sendRequest(MH.ACTION.REMOVE, vehicle, nil, entryId)
end

function MH.requestClear(vehicle)
    return MH.sendRequest(MH.ACTION.CLEAR, vehicle, nil, nil)
end

function MH.requestStart(vehicle)
    return MH.sendRequest(MH.ACTION.START, vehicle, nil, nil)
end

function MH.handleRequest(action, vehicle, job, entryId, connection)
    if not MH.getIsServer() or not MH.features.queue then
        MH.deleteJob(job)
        return false
    end
    if not MH.getCanManage(vehicle, connection) then
        MH.deleteJob(job)
        return false
    end
    if action == MH.ACTION.ADD then
        return MH.serverAdd(vehicle, job)
    elseif action == MH.ACTION.REMOVE then
        return MH.serverRemove(vehicle, entryId)
    elseif action == MH.ACTION.CLEAR then
        return MH.serverClear(vehicle)
    elseif action == MH.ACTION.START then
        return MH.serverStart(vehicle)
    end
    MH.deleteJob(job)
    return false
end

function MH.serverAdd(vehicle, job)
    if job == nil or MH.getJobVehicle(job) ~= vehicle then
        MH.deleteJob(job)
        return false
    end
    local queue = MH.getQueue(vehicle, true)
    if #queue.entries >= MH.MAX_ENTRIES then
        MH.deleteJob(job)
        MH.pruneQueue(queue)
        return false
    end
    MH.useVehicleSettingsAtStart(job)
    job:setValues()
    if not job:validate(queue.farmId) then
        MH.deleteJob(job)
        MH.pruneQueue(queue)
        return false
    end
    table.insert(queue.entries, {id = MH.allocateEntryId(), job = job})
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

function MH.serverRemove(vehicle, entryId)
    local queue = MH.queues[vehicle]
    if queue == nil then
        return false
    end
    for index, entry in ipairs(queue.entries) do
        if entry.id == entryId then
            table.remove(queue.entries, index)
            MH.deleteJob(entry.job)
            if #queue.entries == 0 then
                MH.setPause(queue, MH.PAUSE.NONE)
            end
            MH.publish(queue)
            return true
        end
    end
    return false
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
function MH:onAIJobStopped(job, aiMessage)
    if not MH.getIsServer() or job == nil then
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

-- Labels -------------------------------------------------------------------------
function MH.getJobTitle(job)
    local manager = MH.getJobTypeManager()
    local jobType = manager ~= nil and manager:getJobTypeByIndex(MH.getJobTypeIndex(job)) or nil
    return jobType ~= nil and jobType.title or "?"
end

-- Job type title plus the first target the player picked (position or station).
function MH.getJobLabel(job)
    local title = MH.getJobTitle(job)
    if job.getGroupedParameters == nil then
        return title
    end
    for _, group in ipairs(job:getGroupedParameters()) do
        for _, parameter in ipairs(group:getParameters()) do
            local parameterType = parameter:getType()
            if parameterType == AIParameterType.POSITION or parameterType == AIParameterType.POSITION_ANGLE then
                local x, z = parameter:getPosition()
                if x ~= nil and z ~= nil then
                    return string.format("%s - %d, %d", title, math.floor(x + 0.5), math.floor(z + 0.5))
                end
            elseif parameterType == AIParameterType.UNLOADING_STATION or parameterType == AIParameterType.LOADING_STATION then
                local name = parameter:getString()
                if name ~= nil and name ~= "" then
                    return string.format("%s - %s", title, name)
                end
            end
        end
    end
    return title
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
                    MH.deleteJob(job)
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

-- g_inGameMenu and its map frame are created once at startup (main.lua) and reused by
-- every mission; FSBaseMission:delete only resets them. Remove everything this Mod added,
-- so a later mission without the Mod gets the untouched map page.
function MH.onMissionDeleted(mission)
    MH.missionActive = false
    if MHMapFrame ~= nil then
        MHMapFrame.removeAll()
    end
    if MHDrawerDialog ~= nil then
        MHDrawerDialog.release()
    end
    if g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(MH)
    end
    if mission ~= nil and mission.removeUpdateable ~= nil then
        mission:removeUpdateable(MH)
    end
    for vehicle in pairs(MH.queues) do
        MH.deleteQueue(vehicle)
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
