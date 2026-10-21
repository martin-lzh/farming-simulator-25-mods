-- Lets an empty sprayer or spreader remember which spray fill type it will apply.
-- Added to every vehicle type with Sprayer by scripts/Register.lua.
FillTypeSelector = {}
FillTypeSelector.MOD_NAME = g_currentModName
FillTypeSelector.SPEC_NAME = g_currentModName .. ".fillTypeSelector"
FillTypeSelector.SPEC_TABLE_NAME = "spec_" .. FillTypeSelector.SPEC_NAME
FillTypeSelector.ACTION = "FTS_SELECT_FILL_TYPE"

local function getSpec(vehicle)
    return vehicle[FillTypeSelector.SPEC_TABLE_NAME]
end

local function text(key)
    return g_i18n:getText(key, FillTypeSelector.MOD_NAME)
end

function FillTypeSelector.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(FillUnit, specializations)
        and SpecializationUtil.hasSpecialization(Sprayer, specializations)
end

function FillTypeSelector.initSpecialization()
    Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING,
        "vehicles.vehicle(?)." .. FillTypeSelector.SPEC_NAME .. "#fillType", "Selected spray fill type")
end

function FillTypeSelector.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getExternalFill", FillTypeSelector.getExternalFill)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsSprayerExternallyFilled",
        FillTypeSelector.getIsSprayerExternallyFilled)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsSprayTypeActive", FillTypeSelector.getIsSprayTypeActive)
end

function FillTypeSelector.registerEventListeners(vehicleType)
    for _, name in ipairs({"onLoad", "onPostLoad", "onReadStream", "onWriteStream", "onRegisterActionEvents",
        "onFillUnitFillLevelChanged", "onChangedFillType"}) do
        SpecializationUtil.registerEventListener(vehicleType, name, FillTypeSelector)
    end
end

-- Slurry tankers: the game refills an empty tank itself, always with slurry first
-- (Sprayer:getExternalFill), so a choice only decides between slurry and digestate.
function FillTypeSelector.isSlurry(fillType)
    return fillType == FillType.LIQUIDMANURE or fillType == FillType.DIGESTATE
end

-- Fill types that Sprayer:getExternalFill buys under "AI Worker Refill - Fertilizer".
function FillTypeSelector.isBoughtAsFertilizer(fillType)
    return fillType == FillType.FERTILIZER or fillType == FillType.LIQUIDFERTILIZER
        or fillType == FillType.HERBICIDE or fillType == FillType.LIME
end

-- Fill types that Sprayer:getExternalFill already picks for an empty tank when nothing else fits.
function FillTypeSelector.isChosenByGame(fillType)
    return fillType == FillType.MANURE or fillType == FillType.LIQUIDFERTILIZER
        or fillType == FillType.FERTILIZER or fillType == FillType.HERBICIDE
        or FillTypeSelector.isSlurry(fillType)
end

-- Fill types the implement is built to spread, or nil when every spray type of its tank
-- counts. Spray setups (vehicle.sprayer.sprayTypes.sprayType#fillTypes, read by
-- Sprayer:loadSprayTypeFromXML) name them, e.g. Bredal K105 "fertilizer unknown" and
-- "lime". A setup without fill types covers everything. Without setups a manure spreader
-- spreads manure only: universal trailers such as the Annaburger AW2217 take any bulk
-- good, lime included, into the same tank.
local function getSpreadFillTypes(vehicle)
    local sprayer = vehicle.spec_sprayer
    if sprayer == nil then
        return nil
    end
    local declared = nil
    for _, sprayType in ipairs(sprayer.sprayTypes or {}) do
        if sprayType.fillTypes == nil then
            return nil
        end
        for _, name in ipairs(sprayType.fillTypes) do
            local fillType = g_fillTypeManager:getFillTypeIndexByName(name)
            if fillType ~= nil then
                declared = declared or {}
                declared[fillType] = true
            end
        end
    end
    if declared == nil and sprayer.isManureSpreader and FillType.MANURE ~= nil then
        declared = {[FillType.MANURE] = true}
    end
    return declared
end

-- Spray fill types of the sprayer's own tank that it is built to spread, sorted by index.
function FillTypeSelector.findCandidates(vehicle, fillUnitIndex)
    local candidates = {}
    local supported = vehicle:getFillUnitSupportedFillTypes(fillUnitIndex)
    local spreads = getSpreadFillTypes(vehicle)
    if supported ~= nil then
        for fillType, isSupported in pairs(supported) do
            if isSupported and fillType ~= FillType.UNKNOWN
                and (spreads == nil or spreads[fillType])
                and g_sprayTypeManager:getSprayTypeByFillTypeIndex(fillType) ~= nil then
                table.insert(candidates, fillType)
            end
        end
    end
    table.sort(candidates)
    return candidates
end

function FillTypeSelector.isCandidate(vehicle, fillType)
    local spec = getSpec(vehicle)
    if spec == nil or spec.candidates == nil then
        return false
    end
    for _, candidate in ipairs(spec.candidates) do
        if candidate == fillType then
            return true
        end
    end
    return false
end

function FillTypeSelector.getSelectedFillType(vehicle)
    local spec = getSpec(vehicle)
    if spec ~= nil then
        return spec.selectedFillType
    end
    return nil
end

function FillTypeSelector.isTankEmpty(vehicle)
    local spec = getSpec(vehicle)
    return (vehicle:getFillUnitFillLevel(spec.fillUnitIndex) or 0) <= 0
end

-- The player's choice, or the only possible fill type when the game would not pick it (lime).
function FillTypeSelector.getTargetFillType(vehicle)
    local spec = getSpec(vehicle)
    if spec == nil then
        return nil
    end
    return spec.selectedFillType or spec.defaultFillType
end

-- The target applies while the own tank is empty and no attached tank (fill type source)
-- holds a spray fill type, because the game uses that content first.
function FillTypeSelector.getEffectiveFillType(vehicle)
    local target = FillTypeSelector.getTargetFillType(vehicle)
    if target == nil or not FillTypeSelector.isTankEmpty(vehicle) then
        return nil
    end
    local sprayer = vehicle.spec_sprayer
    if sprayer.fillTypeSources ~= nil and sprayer.supportedSprayTypes ~= nil then
        for _, fillType in ipairs(sprayer.supportedSprayTypes) do
            for _, source in ipairs(sprayer.fillTypeSources[fillType] or {}) do
                local other = source.vehicle
                if other:getFillUnitFillType(source.fillUnitIndex) == fillType
                    and other:getFillUnitFillLevel(source.fillUnitIndex) > 0 then
                    return nil
                end
            end
        end
    end
    return target
end

-- Returns false when the fill type is not a choice for this vehicle; nil clears the choice.
function FillTypeSelector.setSelectedFillType(vehicle, fillType, noEventSend)
    local spec = getSpec(vehicle)
    if spec == nil or (fillType ~= nil and not FillTypeSelector.isCandidate(vehicle, fillType)) then
        return false
    end
    FTSSelectFillTypeEvent.sendEvent(vehicle, fillType, noEventSend)
    spec.selectedFillType = fillType
    FillTypeSelector.refresh(vehicle)
    return true
end

-- The choice is locked while the tank holds something or an AI worker uses the implement.
function FillTypeSelector.isUnlocked(vehicle)
    return getSpec(vehicle) ~= nil and FillTypeSelector.isTankEmpty(vehicle) and not vehicle:getIsAIActive()
end

-- Server check for a client's request: unlocked, and the player's farm may use the vehicle
-- (the same access rule the game uses for entering vehicles and emptying fill units).
function FillTypeSelector.mayRequestChange(vehicle, connection)
    if not FillTypeSelector.isUnlocked(vehicle) then
        return false
    end
    local farmId = g_currentMission:getFarmId(connection)
    return farmId ~= nil and g_currentMission.accessHandler:canFarmAccess(farmId, vehicle)
end

function FillTypeSelector.cycle(vehicle, direction)
    local spec = getSpec(vehicle)
    if spec == nil or #spec.candidates < 2 or not FillTypeSelector.isUnlocked(vehicle) then
        return
    end
    local position = 0
    for index, candidate in ipairs(spec.candidates) do
        if candidate == spec.selectedFillType then
            position = index
        end
    end
    if position == 0 then
        position = direction > 0 and 1 or #spec.candidates
    else
        position = (position - 1 + direction) % #spec.candidates + 1
    end
    FillTypeSelector.setSelectedFillType(vehicle, spec.candidates[position])
end

-- Shows the selection on the empty tank and prepares the AI ground requirements for it.
function FillTypeSelector.refresh(vehicle)
    local spec = getSpec(vehicle)
    if spec == nil or spec.fillUnitIndex == nil then
        return
    end
    local selected = spec.selectedFillType
    local isEmpty = FillTypeSelector.isTankEmpty(vehicle)
    -- Fill level changes arrive every tick while spraying; only state changes matter.
    if spec.lastSelected == selected and spec.lastIsEmpty == isEmpty then
        return
    end
    spec.lastSelected, spec.lastIsEmpty = selected, isEmpty
    local target = selected or spec.defaultFillType
    if target ~= nil and isEmpty then
        -- A tank with a single fill type already shows it when empty (FillUnit:getFillLevelInformation).
        if selected ~= nil and not spec.sharesSeedFillUnit then
            vehicle:setFillUnitFillTypeToDisplay(spec.fillUnitIndex, selected, true)
            spec.displayActive = true
        end
        if vehicle.isServer and spec.aiFillType ~= target then
            vehicle:setSprayerAITerrainDetailProhibitedRange(target)
            spec.aiFillType = target
        end
    else
        if spec.displayActive then
            vehicle:setFillUnitFillTypeToDisplay(spec.fillUnitIndex, FillType.UNKNOWN, false)
            spec.displayActive = false
        end
        -- With content in the tank the game sets the AI requirements from that content.
        spec.aiFillType = nil
    end
    FillTypeSelector.updateActionEvents(vehicle)
end

function FillTypeSelector:onLoad(savegame)
    local spec = getSpec(self)
    spec.fillUnitIndex = self.spec_sprayer.fillUnitIndex
    spec.selectedFillType = nil
    spec.displayActive = false
    spec.aiFillType = nil
    spec.lastSelected, spec.lastIsEmpty = nil, nil
    spec.unrestricted = setmetatable({}, {__mode = "k"})
    local sowingMachine = self.spec_sowingMachine
    spec.sharesSeedFillUnit = sowingMachine ~= nil and sowingMachine.fillUnitIndex == spec.fillUnitIndex
    spec.candidates = FillTypeSelector.findCandidates(self, spec.fillUnitIndex)
    spec.defaultFillType = nil
    if #spec.candidates == 1 and not FillTypeSelector.isChosenByGame(spec.candidates[1]) then
        spec.defaultFillType = spec.candidates[1]
    end
end

function FillTypeSelector:onPostLoad(savegame)
    local spec = getSpec(self)
    if savegame ~= nil and #spec.candidates > 1 then
        local name = savegame.xmlFile:getValue(savegame.key .. "." .. FillTypeSelector.SPEC_NAME .. "#fillType")
        local fillType = name ~= nil and g_fillTypeManager:getFillTypeIndexByName(name) or nil
        if fillType ~= nil and FillTypeSelector.isCandidate(self, fillType) then
            spec.selectedFillType = fillType
        end
    end
    FillTypeSelector.refresh(self)
end

function FillTypeSelector:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = getSpec(self)
    if spec.selectedFillType ~= nil then
        xmlFile:setValue(key .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(spec.selectedFillType))
    end
end

function FillTypeSelector:onReadStream(streamId, connection)
    if connection:getIsServer() then
        local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        if fillType == FillType.UNKNOWN or not FillTypeSelector.isCandidate(self, fillType) then
            fillType = nil
        end
        getSpec(self).selectedFillType = fillType
        FillTypeSelector.refresh(self)
    end
end

function FillTypeSelector:onWriteStream(streamId, connection)
    if not connection:getIsServer() then
        streamWriteUIntN(streamId, getSpec(self).selectedFillType or FillType.UNKNOWN, FillTypeManager.SEND_NUM_BITS)
    end
end

function FillTypeSelector:onFillUnitFillLevelChanged(fillUnitIndex)
    if fillUnitIndex == getSpec(self).fillUnitIndex then
        FillTypeSelector.refresh(self)
    end
end

function FillTypeSelector:onChangedFillType(fillUnitIndex)
    if fillUnitIndex == getSpec(self).fillUnitIndex then
        FillTypeSelector.refresh(self)
    end
end

-- Y (Change Seeds) is used unless something in the combination already listens to it:
-- a sowing machine with more than one seed, or the Precision Farming sprayer controls.
function FillTypeSelector.isSeedKeyTaken(rootVehicle)
    for _, vehicle in ipairs(rootVehicle.childVehicles or {rootVehicle}) do
        local sowingMachine = vehicle.spec_sowingMachine
        if sowingMachine ~= nil and sowingMachine.seeds ~= nil and #sowingMachine.seeds > 1 then
            return true
        end
        for _, name in ipairs(vehicle.specializationNames or {}) do
            if name == "extendedSprayer" or string.sub(name, -16) == ".extendedSprayer" then
                return true
            end
        end
    end
    return false
end

function FillTypeSelector.countSelectable(rootVehicle)
    local count = 0
    for _, vehicle in ipairs(rootVehicle.childVehicles or {rootVehicle}) do
        local spec = getSpec(vehicle)
        if spec ~= nil and spec.candidates ~= nil and #spec.candidates > 1 then
            count = count + 1
        end
    end
    return count
end

function FillTypeSelector:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end
    local spec = getSpec(self)
    self:clearActionEventsTable(spec.actionEvents)
    spec.inputAction, spec.backInputAction = nil, nil
    if #spec.candidates < 2 then
        return
    end
    -- Two selectable implements in one combination: only the selected one listens.
    local isActive = isActiveForInputIgnoreSelection
    if FillTypeSelector.countSelectable(self.rootVehicle) > 1 then
        isActive = isActiveForInput
    end
    if not isActive then
        return
    end
    local _, actionEventId
    if FillTypeSelector.isSeedKeyTaken(self.rootVehicle) then
        spec.inputAction = InputAction[FillTypeSelector.ACTION]
        if spec.inputAction == nil then
            return
        end
        _, actionEventId = self:addActionEvent(spec.actionEvents, spec.inputAction, self,
            FillTypeSelector.actionEventSelect, false, true, false, true, 1)
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
    else
        spec.inputAction, spec.backInputAction = InputAction.TOGGLE_SEEDS, InputAction.TOGGLE_SEEDS_BACK
        _, actionEventId = self:addActionEvent(spec.actionEvents, spec.inputAction, self,
            FillTypeSelector.actionEventSelect, false, true, false, true, 1)
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
        _, actionEventId = self:addActionEvent(spec.actionEvents, spec.backInputAction, self,
            FillTypeSelector.actionEventSelect, false, true, false, true, -1)
        g_inputBinding:setActionEventTextVisibility(actionEventId, false)
    end
    FillTypeSelector.updateActionEvents(self)
end

function FillTypeSelector.actionEventSelect(self, actionName, inputValue, callbackState, isAnalog)
    FillTypeSelector.cycle(self, callbackState or 1)
end

function FillTypeSelector.getActionText(vehicle)
    local selected = getSpec(vehicle).selectedFillType
    local label = text("fts_selectFillType")
    if selected ~= nil then
        return string.format("%s (%s)", label, g_fillTypeManager:getFillTypeTitleByIndex(selected))
    end
    return label
end

-- The action is offered only while the tank is empty; with content the choice is locked.
function FillTypeSelector.updateActionEvents(vehicle)
    local spec = getSpec(vehicle)
    if not vehicle.isClient or spec.actionEvents == nil or spec.inputAction == nil then
        return
    end
    local isEmpty = FillTypeSelector.isTankEmpty(vehicle)
    local event = spec.actionEvents[spec.inputAction]
    if event ~= nil then
        g_inputBinding:setActionEventText(event.actionEventId, FillTypeSelector.getActionText(vehicle))
        g_inputBinding:setActionEventActive(event.actionEventId, isEmpty)
    end
    event = spec.backInputAction and spec.actionEvents[spec.backInputAction]
    if event ~= nil then
        g_inputBinding:setActionEventActive(event.actionEventId, isEmpty)
    end
end

-- Sprayer:getExternalFill picks liquid fertilizer, fertilizer or herbicide for an empty tank
-- (never lime). Ask it for the selected fill type instead; its buy settings still apply.
function FillTypeSelector:getExternalFill(superFunc, fillType, dt)
    if fillType == FillType.UNKNOWN then
        local selected = FillTypeSelector.getEffectiveFillType(self)
        if selected ~= nil and FillTypeSelector.isSlurry(selected) then
            return FillTypeSelector.getExternalSlurry(self, superFunc, selected, dt)
        elseif selected ~= nil then
            return superFunc(self, selected, dt)
        end
    end
    return superFunc(self, fillType, dt)
end

-- The slurry branch of Sprayer:getExternalFill (GS Sprayer.lua:505-530) for the selected type:
-- under "AI Worker Refill - Slurry" it buys that type at the game's price, or takes it from the
-- chosen slurry pit before the other type, like the game does with slurry before digestate.
-- When the selected type can't be bought, or the setting is off, the game decides.
function FillTypeSelector:getExternalSlurry(superFunc, selected, dt)
    local mission = g_currentMission
    local source = mission.missionInfo.helperSlurrySource
    local farmId = self:getActiveFarm()
    if source == 2 then
        local cost = mission.economyManager:getCostPerLiter(selected, false)
        if not cost then
            return superFunc(self, FillType.UNKNOWN, dt)
        end
        local usage = self:getSprayerUsage(selected, dt)
        if self.isServer then
            local price = usage * cost * 1.5
            g_farmManager:updateFarmStats(self:getLastTouchedFarmlandFarmId(), "expenses", price)
            mission:addMoney(-price, farmId, MoneyType.PURCHASE_FERTILIZER)
        end
        return selected, usage
    elseif source ~= nil and source > 2 then
        local loadingStation = mission.liquidManureLoadingStations ~= nil and mission.liquidManureLoadingStations[source - 2] or nil
        if self.isServer and loadingStation ~= nil then
            local other = selected == FillType.LIQUIDMANURE and FillType.DIGESTATE or FillType.LIQUIDMANURE
            for _, fillType in ipairs({selected, other}) do
                local usage = self:getSprayerUsage(fillType, dt)
                local remainingDelta = loadingStation:removeFillLevel(fillType, usage, farmId or self:getOwnerFarmId())
                if usage - remainingDelta > 0.000001 then
                    return fillType, usage
                end
            end
        end
        return FillType.UNKNOWN, 0
    end
    return superFunc(self, FillType.UNKNOWN, dt)
end

-- A manure spreader that also spreads lime is only externally filled under the manure setting.
-- For a selected fertilizer type, judge it with the fertilizer setting like a fertilizer spreader.
function FillTypeSelector:getIsSprayerExternallyFilled(superFunc)
    local selected = FillTypeSelector.getEffectiveFillType(self)
    local sprayer = self.spec_sprayer
    if selected == nil or sprayer.isFertilizerSprayer or not FillTypeSelector.isBoughtAsFertilizer(selected) then
        return superFunc(self)
    end
    local isSlurryTanker, isManureSpreader = sprayer.isSlurryTanker, sprayer.isManureSpreader
    sprayer.isSlurryTanker, sprayer.isManureSpreader, sprayer.isFertilizerSprayer = false, false, true
    local result = superFunc(self)
    sprayer.isSlurryTanker, sprayer.isManureSpreader, sprayer.isFertilizerSprayer = isSlurryTanker, isManureSpreader, false
    return result
end

local function listsFillType(sprayType, fillType)
    for _, name in ipairs(sprayType.fillTypes) do
        if g_fillTypeManager:getFillTypeIndexByName(name) == fillType then
            return true
        end
    end
    return false
end

-- Spray types limited to certain fill types (e.g. a lime setup with its own work areas) follow the
-- selection while the tank is empty. Other checks in the chain (folding) still run on a view of the
-- spray type that accepts the empty tank.
function FillTypeSelector:getIsSprayTypeActive(superFunc, sprayType)
    local spec = getSpec(self)
    if sprayType.fillTypes ~= nil and spec ~= nil and FillTypeSelector.getTargetFillType(self) ~= nil
        and (sprayType.fillUnitIndex or self.spec_sprayer.fillUnitIndex) == spec.fillUnitIndex then
        local selected = FillTypeSelector.getEffectiveFillType(self)
        if selected ~= nil then
            if not listsFillType(sprayType, selected) then
                return false
            end
            local view = spec.unrestricted[sprayType]
            if view == nil then
                view = setmetatable({fillTypes = {"UNKNOWN"}}, {__index = sprayType})
                spec.unrestricted[sprayType] = view
            end
            return superFunc(self, view)
        end
    end
    return superFunc(self, sprayType)
end
