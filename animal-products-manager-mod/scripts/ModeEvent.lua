APDModeEvent = {}
local APDModeEvent_mt = Class(APDModeEvent, Event)
InitEventClass(APDModeEvent, "APDModeEvent")

function APDModeEvent.emptyNew()
    return Event.new(APDModeEvent_mt)
end

function APDModeEvent.new(placeable, fillType, mode)
    local self = APDModeEvent.emptyNew()
    self.placeable, self.fillType, self.mode = placeable, fillType, mode
    return self
end

function APDModeEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUIntN(streamId, self.fillType, FillTypeManager.SEND_NUM_BITS)
    streamWriteUIntN(streamId, self.mode, 2)
end

function APDModeEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.mode = streamReadUIntN(streamId, 2)
    self:run(connection)
end

function APDModeEvent:run(connection)
    local APD = AnimalProductDistribution
    if connection:getIsServer() then
        APD.applyMode(self.placeable, self.fillType, self.mode)
    elseif APD.canManage(self.placeable, connection)
        and APD.applyMode(self.placeable, self.fillType, self.mode) then
        g_server:broadcastEvent(self, nil, nil, self.placeable)
    end
end
