-- Based on the game's SetSeedIndexEvent: the sender applies its choice at once, the server checks access,
-- the lock (empty tank, no AI worker) and the fill type,
-- and applies it, then sends it to every client. The sender gets it back too, so two players
-- choosing at the same time end up with the server's order instead of different results.
FTSSelectFillTypeEvent = {}
local FTSSelectFillTypeEvent_mt = Class(FTSSelectFillTypeEvent, Event)
InitEventClass(FTSSelectFillTypeEvent, "FTSSelectFillTypeEvent")

function FTSSelectFillTypeEvent.emptyNew()
    return Event.new(FTSSelectFillTypeEvent_mt)
end

function FTSSelectFillTypeEvent.new(object, fillType)
    local self = FTSSelectFillTypeEvent.emptyNew()
    self.object, self.fillType = object, fillType
    return self
end

function FTSSelectFillTypeEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteUIntN(streamId, self.fillType or FillType.UNKNOWN, FillTypeManager.SEND_NUM_BITS)
end

function FTSSelectFillTypeEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    if self.fillType == FillType.UNKNOWN then
        self.fillType = nil
    end
    self:run(connection)
end

function FTSSelectFillTypeEvent:run(connection)
    local object = self.object
    if object == nil or not object:getIsSynchronized() then
        return
    end
    if connection:getIsServer() then
        -- Authoritative value from the server, including corrections of a rejected request.
        FillTypeSelector.setSelectedFillType(object, self.fillType, true)
        return
    end
    if FillTypeSelector.mayRequestChange(object, connection)
        and FillTypeSelector.setSelectedFillType(object, self.fillType, true) then
        g_server:broadcastEvent(FTSSelectFillTypeEvent.new(object, self.fillType), false, nil, object)
    else
        -- The requesting client already applied its choice; send the current value back.
        connection:sendEvent(FTSSelectFillTypeEvent.new(object, FillTypeSelector.getSelectedFillType(object)))
    end
end

function FTSSelectFillTypeEvent.sendEvent(object, fillType, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(FTSSelectFillTypeEvent.new(object, fillType), nil, nil, object)
        else
            g_client:getServerConnection():sendEvent(FTSSelectFillTypeEvent.new(object, fillType))
        end
    end
end
