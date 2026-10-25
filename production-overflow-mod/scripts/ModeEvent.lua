-- One output mode change. Clients send requests; the server checks, applies and sends
-- the result to every client, the sender included, so all machines change in one order.
POModeEvent = {}
local POModeEvent_mt = Class(POModeEvent, Event)
InitEventClass(POModeEvent, "POModeEvent")

function POModeEvent.emptyNew()
    return Event.new(POModeEvent_mt)
end

function POModeEvent.new(productionPoint, fillType, mode)
    local self = POModeEvent.emptyNew()
    self.productionPoint, self.fillType, self.mode = productionPoint, fillType, mode
    return self
end

function POModeEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.productionPoint)
    streamWriteUIntN(streamId, self.fillType, FillTypeManager.SEND_NUM_BITS)
    streamWriteUIntN(streamId, self.mode, ProductionOverflow.MODE_NUM_BITS)
end

function POModeEvent:readStream(streamId, connection)
    self.productionPoint = NetworkUtil.readNodeObject(streamId)
    self.fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.mode = streamReadUIntN(streamId, ProductionOverflow.MODE_NUM_BITS)
    self:run(connection)
end

function POModeEvent:run(connection)
    local PO = ProductionOverflow
    if self.productionPoint == nil then
        return
    end
    if connection:getIsServer() then
        PO.applyMode(self.productionPoint, self.fillType, self.mode)
    elseif PO.canManage(self.productionPoint, connection)
        and PO.applyMode(self.productionPoint, self.fillType, self.mode) then
        g_server:broadcastEvent(self)
    end
end
