-- Placeable specialization for every placeable with a native production point. It gives
-- the production point its Mod state and saves and streams the Mod modes.
ProductionOverflowPlaceable = {}
local Spec = ProductionOverflowPlaceable

function Spec.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PlaceableProductionPoint, specializations)
end

function Spec.registerEventListeners(placeableType)
    for _, name in ipairs({"onLoad", "onDelete", "onLoadFinished", "onPostFinalizePlacement", "onReadStream", "onWriteStream"}) do
        SpecializationUtil.registerEventListener(placeableType, name, Spec)
    end
end

function Spec.registerSavegameXMLPaths(schema, key)
    schema:register(XMLValueType.STRING, key .. ".output(?)#fillType", "Output fill type")
    schema:register(XMLValueType.STRING, key .. ".output(?)#mode", "storeRest or sellRest: native distributing, then store or sell the rest")
    schema:register(XMLValueType.FLOAT, key .. ".output(?)#releasedLiters", "Stock left after the last hourly distribution that may still become pallets", 0)
end

function Spec.point(placeable)
    local spec = placeable.spec_productionPoint
    return spec ~= nil and spec.productionPoint or nil
end

-- Runs after PlaceableProductionPoint:onLoad, which creates the production point.
function Spec:onLoad()
    local point = Spec.point(self)
    if point ~= nil then
        point.poState = ProductionOverflow.newState()
    end
end

function Spec:onDelete()
    local point = Spec.point(self)
    if point ~= nil and point.poState ~= nil then
        point.poState.deleted = true
    end
end

-- PlaceableProductionPoint:onFinalizePlacement has given the production point its owner.
function Spec:onPostFinalizePlacement()
    ProductionOverflow.onPlaced(Spec.point(self))
end

function Spec:saveToXMLFile(xmlFile, key)
    local PO = ProductionOverflow
    local point = Spec.point(self)
    if PO.state(point) == nil then
        return
    end
    PO.restoreExposed(point)
    for index, entry in ipairs(PO.restEntries(point)) do
        local path = string.format("%s.output(%d)", key, index - 1)
        xmlFile:setValue(path .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(entry.fillType))
        xmlFile:setValue(path .. "#mode", PO.SAVE_NAMES[entry.mode])
        local released = PO.released(point, entry.fillType)
        if released > 0 then
            xmlFile:setValue(path .. "#releasedLiters", released)
        end
    end
end

-- The native modes and storage are loaded by PlaceableProductionPoint, which may run in
-- either order with this; the Mod modes are applied in onLoadFinished.
function Spec:loadFromXMLFile(xmlFile, key, reset)
    local point = Spec.point(self)
    local state = ProductionOverflow.state(point)
    if state == nil or reset then
        return
    end
    state.loaded = {}
    for _, path in xmlFile:iterator(key .. ".output") do
        local name = xmlFile:getValue(path .. "#fillType")
        local fillType = name ~= nil and g_fillTypeManager:getFillTypeIndexByName(name) or nil
        local mode = ProductionOverflow.SAVE_MODES[xmlFile:getValue(path .. "#mode")]
        if fillType ~= nil and mode ~= nil then
            table.insert(state.loaded, {fillType = fillType, mode = mode,
                released = xmlFile:getValue(path .. "#releasedLiters", 0)})
        end
    end
end

function Spec:onLoadFinished()
    local PO = ProductionOverflow
    local point = Spec.point(self)
    local state = PO.state(point)
    if state == nil or state.loaded == nil then
        return
    end
    for _, entry in ipairs(state.loaded) do
        -- A Mod mode only exists on top of native Distributing; anything else in the save wins.
        if point:getOutputDistributionMode(entry.fillType) == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER
            and PO.canUse(point, entry.fillType, entry.mode) then
            state.rest[entry.fillType] = entry.mode
            local released = entry.released
            if entry.mode == PO.DISTRIBUTE_STORE and type(released) == "number" and released > 0
                and released < math.huge then
                state.released[entry.fillType] = released
            end
        end
    end
    state.loaded = nil
end

-- Runs after PlaceableProductionPoint:onReadStream/onWriteStream, which stream the native
-- modes. Joining clients get the Mod modes; released output stays on the server.
function Spec:onWriteStream(streamId, connection)
    local entries = ProductionOverflow.restEntries(Spec.point(self))
    streamWriteUInt8(streamId, #entries)
    for _, entry in ipairs(entries) do
        streamWriteUIntN(streamId, entry.fillType, FillTypeManager.SEND_NUM_BITS)
        streamWriteUIntN(streamId, entry.mode, ProductionOverflow.MODE_NUM_BITS)
    end
end

function Spec:onReadStream(streamId, connection)
    local PO = ProductionOverflow
    local point = Spec.point(self)
    local state = PO.state(point)
    for _ = 1, streamReadUInt8(streamId) do
        local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        local mode = streamReadUIntN(streamId, PO.MODE_NUM_BITS)
        if state ~= nil and PO.isRestMode(mode) and PO.canUse(point, fillType, mode)
            and point:getOutputDistributionMode(fillType) == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then
            state.rest[fillType] = mode
        end
    end
end
