APMModeEvent = {}
local APMModeEvent_mt = Class(APMModeEvent, Event)
InitEventClass(APMModeEvent, "APMModeEvent")

function APMModeEvent.emptyNew()
    return Event.new(APMModeEvent_mt)
end

function APMModeEvent.new(placeable, fillType, mode)
    local self = APMModeEvent.emptyNew()
    self.placeable, self.fillType, self.mode = placeable, fillType, mode
    return self
end

function APMModeEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUIntN(streamId, self.fillType, FillTypeManager.SEND_NUM_BITS)
    streamWriteUIntN(streamId, self.mode, 2)
end

function APMModeEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.mode = streamReadUIntN(streamId, 2)
    self:run(connection)
end

function APMModeEvent:run(connection)
    local APM = AnimalProductsManager
    if connection:getIsServer() then
        APM.applyMode(self.placeable, self.fillType, self.mode)
    elseif APM.canManage(self.placeable, connection)
        and APM.applyMode(self.placeable, self.fillType, self.mode) then
        g_server:broadcastEvent(self, nil, nil, self.placeable)
    end
end
