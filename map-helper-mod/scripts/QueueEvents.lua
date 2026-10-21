-- Client -> server: add, remove, clear or start the command queue of one vehicle.
-- Queued jobs travel with the native AIJob:writeStream/readStream, the same way
-- AIJobStartRequestEvent sends a job the player created in the job menu.
MHQueueRequestEvent = {}
local MHQueueRequestEvent_mt = Class(MHQueueRequestEvent, Event)
InitEventClass(MHQueueRequestEvent, "MHQueueRequestEvent")

function MHQueueRequestEvent.emptyNew()
    return Event.new(MHQueueRequestEvent_mt)
end

function MHQueueRequestEvent.new(action, vehicle, job, entryId)
    local self = MHQueueRequestEvent.emptyNew()
    self.action, self.vehicle, self.job, self.entryId = action, vehicle, job, entryId
    return self
end

function MHQueueRequestEvent:writeStream(streamId, connection)
    local MH = MapHelper
    streamWriteUIntN(streamId, self.action, MH.ACTION_NUM_BITS)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    if self.action == MH.ACTION.ADD then
        streamWriteUInt16(streamId, MH.getJobTypeIndex(self.job))
        self.job:writeStream(streamId, connection)
    elseif self.action == MH.ACTION.REMOVE then
        streamWriteInt32(streamId, self.entryId)
    end
end

function MHQueueRequestEvent:readStream(streamId, connection)
    local MH = MapHelper
    self.action = streamReadUIntN(streamId, MH.ACTION_NUM_BITS)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    if self.action == MH.ACTION.ADD then
        self.job = MH.createJob(streamReadUInt16(streamId))
        if self.job == nil then
            -- Same assumption as AIJobStartRequestEvent: both sides share the job types.
            MH.warnOnce("unknownJobType", "Received a queued job of an unknown type")
            return
        end
        self.job:readStream(streamId, connection)
    elseif self.action == MH.ACTION.REMOVE then
        self.entryId = streamReadInt32(streamId)
    end
    self:run(connection)
end

function MHQueueRequestEvent:run(connection)
    if connection:getIsServer() then
        -- Requests are only handled by the server.
        MapHelper.deleteJob(self.job)
        return
    end
    MapHelper.handleRequest(self.action, self.vehicle, self.job, self.entryId, connection)
end

-- Server -> clients: the complete queue of one vehicle, sent after every change
-- and to joining players.
MHQueueStateEvent = {}
local MHQueueStateEvent_mt = Class(MHQueueStateEvent, Event)
InitEventClass(MHQueueStateEvent, "MHQueueStateEvent")

function MHQueueStateEvent.emptyNew()
    return Event.new(MHQueueStateEvent_mt)
end

function MHQueueStateEvent.new(vehicle, queue, notify)
    local self = MHQueueStateEvent.emptyNew()
    self.vehicle, self.queue, self.notify = vehicle, queue, notify
    return self
end

function MHQueueStateEvent:writeStream(streamId, connection)
    local MH = MapHelper
    local queue = self.queue
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUIntN(streamId, self.notify or MH.NOTIFY.NONE, MH.NOTIFY_NUM_BITS)
    streamWriteUIntN(streamId, queue.farmId or 0, FarmManager.FARM_ID_SEND_NUM_BITS)
    streamWriteBool(streamId, queue.running)
    streamWriteUIntN(streamId, queue.pause, MH.PAUSE_NUM_BITS)
    if queue.pause == MH.PAUSE.START_FAILED then
        streamWriteUInt8(streamId, queue.startState or 0)
        streamWriteUInt16(streamId, queue.startJobTypeIndex or 0)
    end
    streamWriteUInt8(streamId, #queue.entries)
    for _, entry in ipairs(queue.entries) do
        streamWriteInt32(streamId, entry.id)
        streamWriteUInt16(streamId, MH.getJobTypeIndex(entry.job))
        entry.job:writeStream(streamId, connection)
    end
end

function MHQueueStateEvent:readStream(streamId, connection)
    local MH = MapHelper
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.notify = streamReadUIntN(streamId, MH.NOTIFY_NUM_BITS)
    local state = {entries = {}}
    state.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    state.running = streamReadBool(streamId)
    state.pause = streamReadUIntN(streamId, MH.PAUSE_NUM_BITS)
    if state.pause == MH.PAUSE.START_FAILED then
        state.startState = streamReadUInt8(streamId)
        state.startJobTypeIndex = streamReadUInt16(streamId)
    end
    local count = streamReadUInt8(streamId)
    for _ = 1, count do
        local id = streamReadInt32(streamId)
        local job = MH.createJob(streamReadUInt16(streamId))
        if job == nil then
            MH.warnOnce("unknownJobType", "Received a queued job of an unknown type")
            for _, entry in ipairs(state.entries) do
                MH.deleteJob(entry.job)
            end
            return
        end
        job:readStream(streamId, connection)
        MH.useVehicleSettingsAtStart(job)
        table.insert(state.entries, {id = id, job = job})
    end
    self.state = state
    self:run(connection)
end

function MHQueueStateEvent:run(connection)
    if not connection:getIsServer() or self.state == nil then
        return
    end
    MapHelper.applyState(self.vehicle, self.state, self.notify)
end
