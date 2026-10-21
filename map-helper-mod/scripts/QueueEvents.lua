-- Client -> server: add, edit, move, remove, clear or start the command queue of one vehicle.
-- Queued jobs travel with the native AIJob:writeStream/readStream, the same way
-- AIJobStartRequestEvent sends a job the player created in the job menu.
--
-- Stream: action (UIntN 3), vehicle (node object), then per action
--   ADD:    insertNext (bool), job type index (UInt16), job stream
--   EDIT:   entry id (Int32), job type index (UInt16), job stream
--   MOVE:   entry id (Int32), up (bool)
--   REMOVE: entry id (Int32)
--   CLEAR, START: nothing
MHQueueRequestEvent = {}
local MHQueueRequestEvent_mt = Class(MHQueueRequestEvent, Event)
InitEventClass(MHQueueRequestEvent, "MHQueueRequestEvent")

function MHQueueRequestEvent.emptyNew()
    return Event.new(MHQueueRequestEvent_mt)
end

-- flag: ADD = insert as the next entry; MOVE = move up. Ignored by the other actions.
function MHQueueRequestEvent.new(action, vehicle, job, entryId, flag)
    local self = MHQueueRequestEvent.emptyNew()
    self.action, self.vehicle, self.job, self.entryId, self.flag = action, vehicle, job, entryId, flag == true
    return self
end

function MHQueueRequestEvent:writeStream(streamId, connection)
    local MH = MapHelper
    local action = self.action
    streamWriteUIntN(streamId, action, MH.ACTION_NUM_BITS)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    if action == MH.ACTION.ADD then
        streamWriteBool(streamId, self.flag)
    elseif action == MH.ACTION.EDIT or action == MH.ACTION.MOVE or action == MH.ACTION.REMOVE then
        streamWriteInt32(streamId, self.entryId)
    end
    if action == MH.ACTION.ADD or action == MH.ACTION.EDIT then
        streamWriteUInt16(streamId, MH.getJobTypeIndex(self.job))
        self.job:writeStream(streamId, connection)
    elseif action == MH.ACTION.MOVE then
        streamWriteBool(streamId, self.flag)
    end
end

function MHQueueRequestEvent:readStream(streamId, connection)
    local MH = MapHelper
    local action = streamReadUIntN(streamId, MH.ACTION_NUM_BITS)
    self.action = action
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    if action == MH.ACTION.ADD then
        self.flag = streamReadBool(streamId)
    elseif action == MH.ACTION.EDIT or action == MH.ACTION.MOVE or action == MH.ACTION.REMOVE then
        self.entryId = streamReadInt32(streamId)
    end
    if action == MH.ACTION.ADD or action == MH.ACTION.EDIT then
        self.job = MH.createJob(streamReadUInt16(streamId))
        if self.job == nil then
            -- Same assumption as AIJobStartRequestEvent: both sides share the job types.
            MH.warnOnce("unknownJobType", "Received a queued job of an unknown type")
            return
        end
        self.job:readStream(streamId, connection)
    elseif action == MH.ACTION.MOVE then
        self.flag = streamReadBool(streamId)
    end
    self:run(connection)
end

function MHQueueRequestEvent:run(connection)
    if connection:getIsServer() then
        -- Requests are only handled by the server.
        return
    end
    MapHelper.handleRequest(self.action, self.vehicle, self.job, self.entryId, connection, self.flag)
end

-- Server -> clients: the complete queue of one vehicle, sent after every change
-- and to joining players. The job a worker is driving right now is not part of it:
-- clients read it from the vehicle (AIJobVehicle:getJob), like the native worker list.
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
