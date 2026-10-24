-- Which field work a vehicle combination does, and whether a field needs it.
--
-- The field state is read at one point per field (its name marker), the same way the map's
-- field info box reads the point under the cursor: FieldState.new() + FieldState:update(x, z)
-- (1.25 decompiled gui/InGameMenuMapFrame.lua:674-677). The conditions follow that box
-- (:710-780) and the requirements the implements give the AI (SDK vehicles/specializations).
-- Unknown or missing data never hides a field: it just gets no need.
MHFieldNeeds = {}
local FN = MHFieldNeeds

FN.WORK = {
    PLOW = "PLOW", CULTIVATE = "CULTIVATE", SOW = "SOW", ROLL = "ROLL", FERTILIZE = "FERTILIZE",
    LIME = "LIME", HERBICIDE = "HERBICIDE", WEED = "WEED", MULCH = "MULCH", MOW = "MOW",
    HARVEST = "HARVEST", PREPARE = "PREPARE", STONES = "STONES"
}

-- Display text per work: the game's own contract titles and field info texts where they exist.
FN.WORK_TEXT = {
    PLOW = "contract_field_plow_title", CULTIVATE = "contract_field_cultivate_title", SOW = "contract_field_sow_title",
    ROLL = "ui_growthMapNeedsRolling", FERTILIZE = "contract_field_fertilize_title", LIME = "ui_growthMapNeedsLime",
    HERBICIDE = "contract_field_herbicide_title", WEED = "contract_field_weed_title", MOW = "contract_field_mow_title",
    HARVEST = "contract_field_harvest_title", PREPARE = "ui_growthMapReadyToPrepareForHarvest",
    STONES = "contract_field_stonePick_title"
}

-- Spec table of the Fill Type Selector Mod from this repository, when it is installed.
FN.FILL_TYPE_SELECTOR_SPEC = "spec_FS25_FillTypeSelector.fillTypeSelector"

function FN.getWorkText(work)
    if work == FN.WORK.MULCH then
        return MapHelper.text("mh_workMulch")
    end
    return g_i18n:getText(FN.WORK_TEXT[work])
end

local function toSet(list)
    local set = {}
    for _, value in ipairs(list or {}) do
        set[value] = true
    end
    return set
end

-- The work the root vehicle and its attached implements do (Vehicle:getRootVehicle,
-- getChildVehicles, SDK vehicles/Vehicle.lua:3010/3022), from each implement's own settings:
-- - sowing machine: direct planting (useDirectPlanting, SowingMachine.lua:168) or a cultivator
--   in the combination also sow on harvested and grass ground (AI_OUTPUT_GROUND_TYPES,
--   SowingMachine.lua:1224-1247);
-- - roller: only soil rollers (isSoilRoller, Roller.lua:112-123); grass rolling has no need;
-- - weeder: hoe or weeder (isHoeWeeder, Weeder.lua:87) with its own weed replacement table;
-- - fruit preparer: its crops (spec.fruitTypes, FruitPreparer.lua:99-110);
-- - mower: its converter crops (Mower.lua:156-162); cutter: its crops and whether it takes
--   forage growth states (fruitTypeIndices, allowsForageGrowthState, Cutter.lua:179/331);
-- - sprayer: only with work areas (hasWorkAreas, Sprayer.lua:299); a fertilizing sowing machine
--   or cultivator sows or cultivates; the spray work follows what it sprays (FN.getSprayFillType).
function FN.getWorks(vehicle)
    local works = {}
    local list = {}
    local function add(work, data)
        if works[work] == nil then
            works[work] = data or {}
            table.insert(list, work)
        end
        return works[work]
    end
    if vehicle == nil then
        return works, list
    end
    local root = vehicle.getRootVehicle ~= nil and vehicle:getRootVehicle() or vehicle
    local children = root.getChildVehicles ~= nil and root:getChildVehicles() or {root}
    for _, child in ipairs(children) do
        if child.spec_plow ~= nil then
            add(FN.WORK.PLOW)
        end
        if child.spec_cultivator ~= nil then
            add(FN.WORK.CULTIVATE)
        end
        if child.spec_sowingMachine ~= nil then
            local sow = add(FN.WORK.SOW)
            sow.direct = sow.direct or child.spec_sowingMachine.useDirectPlanting == true
        end
        if child.spec_roller ~= nil and child.spec_roller.isSoilRoller then
            add(FN.WORK.ROLL)
        end
        if child.spec_weeder ~= nil then
            local weed = add(FN.WORK.WEED)
            if child.spec_weeder.isHoeWeeder then
                weed.hoe = true
            else
                weed.weeder = true
            end
        end
        if child.spec_mulcher ~= nil then
            add(FN.WORK.MULCH)
        end
        if child.spec_stonePicker ~= nil then
            add(FN.WORK.STONES)
        end
        if child.spec_fruitPreparer ~= nil and child.spec_fruitPreparer.fruitTypes ~= nil and #child.spec_fruitPreparer.fruitTypes > 0 then
            local prepare = add(FN.WORK.PREPARE, {fruits = {}})
            for fruitTypeIndex in pairs(toSet(child.spec_fruitPreparer.fruitTypes)) do
                prepare.fruits[fruitTypeIndex] = true
            end
        end
        if child.spec_mower ~= nil and child.spec_mower.fruitTypeConverters ~= nil then
            -- The MOWER converter also lists wheat, barley, oat, canola and soybean -> straw
            -- (maps_fruitTypes.xml:59-67): a mower can cut straw from grain, but that isn't a
            -- mowing job. Like the game's mowing contracts (MowMission.lua:98-105, grass only),
            -- only crops the mower turns into something other than straw count.
            local mow = add(FN.WORK.MOW, {fruits = {}})
            for fruitTypeIndex, converted in pairs(child.spec_mower.fruitTypeConverters) do
                local fillTypeIndex = type(converted) == "table" and converted.fillTypeIndex or nil
                if FillType.STRAW == nil or fillTypeIndex ~= FillType.STRAW then
                    mow.fruits[fruitTypeIndex] = true
                end
            end
        end
        if child.spec_cutter ~= nil and child.spec_cutter.fruitTypeIndices ~= nil then
            local harvest = add(FN.WORK.HARVEST, {fruits = {}})
            for _, fruitTypeIndex in ipairs(child.spec_cutter.fruitTypeIndices) do
                harvest.fruits[fruitTypeIndex] = harvest.fruits[fruitTypeIndex] == true
                    or child.spec_cutter.allowsForageGrowthState == true
            end
        end
        local sprayer = child.spec_sprayer
        if sprayer ~= nil and sprayer.hasWorkAreas ~= false and child.spec_sowingMachine == nil and child.spec_cultivator == nil then
            local work, sprayType = FN.getSprayWork(child)
            add(work, {sprayType = sprayType})
        end
    end
    if works[FN.WORK.SOW] ~= nil and works[FN.WORK.CULTIVATE] ~= nil then
        -- With a cultivator in the combination the seeder takes direct seeding ground too.
        works[FN.WORK.SOW].direct = true
    end
    return works, list
end

-- What a sprayer would spray, resolved like Sprayer:onStartWorkAreaProcessing
-- (SDK Sprayer.lua:1206-1226): its own tank when it has content, else an attached fill type
-- source (front tank) that holds a supported spray type. With both empty, the choice made in
-- the Fill Type Selector Mod is used when that Mod is installed.
function FN.getSprayFillType(sprayer)
    if sprayer.getSprayerFillUnitIndex == nil or sprayer.getFillUnitFillType == nil then
        return nil
    end
    local fillUnitIndex = sprayer:getSprayerFillUnitIndex()
    local level = sprayer.getFillUnitFillLevel ~= nil and sprayer:getFillUnitFillLevel(fillUnitIndex) or 0
    if level > 0 then
        return sprayer:getFillUnitFillType(fillUnitIndex)
    end
    local spec = sprayer.spec_sprayer
    for _, sprayFillType in ipairs(spec.supportedSprayTypes or {}) do
        local sources = spec.fillTypeSources ~= nil and spec.fillTypeSources[sprayFillType] or nil
        for _, source in ipairs(sources or {}) do
            local other = source.vehicle
            if other ~= nil and other:getFillUnitFillLevel(source.fillUnitIndex) > 0
                and other:getFillUnitFillType(source.fillUnitIndex) == sprayFillType then
                return sprayFillType
            end
        end
    end
    local selector = sprayer[FN.FILL_TYPE_SELECTOR_SPEC]
    if type(selector) == "table" then
        return selector.selectedFillType or selector.defaultFillType
    end
    return nil
end

-- The spray work for a sprayer and the spray type it uses (SprayTypeManager:
-- getSprayTypeByFillTypeIndex, SDK misc/SprayTypeManager.lua:228; isLime / isHerbicide /
-- sprayGroundType). Without a known fill type it counts as fertilizer.
function FN.getSprayWork(sprayer)
    local fillTypeIndex = FN.getSprayFillType(sprayer)
    local sprayType = nil
    if fillTypeIndex ~= nil and g_sprayTypeManager ~= nil then
        sprayType = g_sprayTypeManager:getSprayTypeByFillTypeIndex(fillTypeIndex)
    end
    if sprayType ~= nil and sprayType.isLime then
        return FN.WORK.LIME, sprayType
    elseif sprayType ~= nil and sprayType.isHerbicide then
        return FN.WORK.HERBICIDE, sprayType
    end
    return FN.WORK.FERTILIZE, sprayType
end

-- The field state at a point, copied out of a FieldState so the caller can keep it.
function FN.readState(x, z)
    if not MapHelper.features.fieldNeeds or x == nil or z == nil then
        return nil
    end
    local fieldState = FieldState.new()
    fieldState:update(x, z)
    if not fieldState.isValid or fieldState.groundType == FieldGroundType.NONE then
        return nil
    end
    local state = {}
    for _, key in ipairs({"fruitTypeIndex", "growthState", "groundType", "sprayType", "sprayLevel", "limeLevel",
        "plowLevel", "rollerLevel", "weedState", "stoneLevel"}) do
        state[key] = fieldState[key]
    end
    if state.fruitTypeIndex ~= nil and state.fruitTypeIndex ~= FruitType.UNKNOWN then
        state.fruit = g_fruitTypeManager:getFruitTypeByIndex(state.fruitTypeIndex)
    end
    return state
end

-- The crop's state in the map info box's order (MF:716-726): cut, withered, growing,
-- preparable, harvestable. Forage states count as growing there.
function FN.getGrowthStatus(state)
    local fruit, growthState = state.fruit, state.growthState or 0
    if fruit == nil or growthState == 0 then
        return nil
    elseif fruit:getIsCut(growthState) then
        return "cut"
    elseif fruit:getIsWithered(growthState) then
        return "withered"
    elseif fruit:getIsGrowing(growthState) then
        return "growing"
    elseif fruit:getIsPreparable(growthState) then
        return "preparable"
    elseif fruit:getIsHarvestable(growthState) then
        return "harvestable"
    end
    return nil
end

-- Ground already prepared for sowing (SowingMachine.AI_REQUIRED_GROUND_TYPES minus stubble).
local function getIsPrepared(groundType)
    return groundType == FieldGroundType.CULTIVATED or groundType == FieldGroundType.SEEDBED
        or groundType == FieldGroundType.PLOWED or groundType == FieldGroundType.ROLLED_SEEDBED
        or groundType == FieldGroundType.RIDGE
end

-- No crop that would be destroyed: nothing planted, harvested (cut) or withered.
local function getIsBare(state)
    local status = FN.getGrowthStatus(state)
    return status == nil or status == "cut" or status == "withered"
end

local function getHasGroundType(list, groundType)
    for _, value in ipairs(list or {}) do
        if value == groundType then
            return true
        end
    end
    return false
end

-- Weed states a tool can treat: the source states of its weed replacement table
-- (WeedSystem:getWeederReplacements(isHoe) / getHerbicideReplacements, as the implements give
-- them to the AI: SDK Weeder.lua:209-229, Sprayer.lua:722-741).
local function getTreatsWeedState(replacementData, weedState)
    local weed = replacementData ~= nil and replacementData.weed or nil
    return weed ~= nil and weed.replacements ~= nil and weed.replacements[weedState] ~= nil
end

-- Whether a field in this state needs one work, with the combination's data for that work.
-- Field info box conditions: lime (useLimeCounter, limeRequired, limeLevel == 0), plowing
-- (plowingRequiredEnabled, plowLevel == 0), rolling (useRolling, rollerLevel > 0), weeds
-- (weedsEnabled, weedState > 0).
function FN.getNeedsWork(state, work, data)
    local mission = g_currentMission
    local info = mission ~= nil and mission.missionInfo or {}
    local gameplay = Platform ~= nil and Platform.gameplay or {}
    data = type(data) == "table" and data or {}
    local fruit, growthState = state.fruit, state.growthState or 0
    local status = FN.getGrowthStatus(state)
    local bare = getIsBare(state)
    local groundType = state.groundType
    local weedSystem = mission ~= nil and mission.weedSystem or nil
    if work == FN.WORK.PLOW then
        return bare and groundType ~= FieldGroundType.PLOWED
            and (not getIsPrepared(groundType) or (info.plowingRequiredEnabled and state.plowLevel == 0))
    elseif work == FN.WORK.CULTIVATE then
        return bare and groundType ~= FieldGroundType.CULTIVATED and groundType ~= FieldGroundType.SEEDBED
            and groundType ~= FieldGroundType.ROLLED_SEEDBED
    elseif work == FN.WORK.SOW then
        if not bare or SowingMachine == nil then
            return false
        end
        return getHasGroundType(SowingMachine.AI_REQUIRED_GROUND_TYPES, groundType)
            or (data.direct == true and getHasGroundType(SowingMachine.AI_OUTPUT_GROUND_TYPES, groundType))
    elseif work == FN.WORK.ROLL then
        -- Soil rolling only before the crop's second growth state (Roller.lua:210-219).
        return gameplay.useRolling == true and (state.rollerLevel or 0) > 0 and (fruit == nil or growthState <= 1)
    elseif work == FN.WORK.LIME then
        -- The AI skips ground that already has this spray type (Sprayer.lua:753-758).
        local sprayType = data.sprayType
        return gameplay.useLimeCounter == true and info.limeRequired == true and state.limeLevel == 0
            and not (sprayType ~= nil and state.sprayType == sprayType.sprayGroundType)
    elseif work == FN.WORK.FERTILIZE then
        -- The AI skips the maximum spray level and ground that already has this fertilizer's
        -- spray type (Sprayer.lua:744-751).
        local maxLevel = mission.fieldGroundSystem ~= nil and mission.fieldGroundSystem:getMaxValue(FieldDensityMap.SPRAY_LEVEL) or 0
        local sprayType = data.sprayType
        return (state.sprayLevel or 0) < maxLevel and status ~= "withered" and status ~= "harvestable"
            and not (sprayType ~= nil and state.sprayType == sprayType.sprayGroundType)
    elseif work == FN.WORK.HERBICIDE then
        return info.weedsEnabled == true and (state.weedState or 0) > 0 and (fruit == nil or status == "growing")
            and weedSystem ~= nil and getTreatsWeedState(weedSystem:getHerbicideReplacements(), state.weedState)
    elseif work == FN.WORK.WEED then
        if info.weedsEnabled ~= true or (state.weedState or 0) <= 0 or weedSystem == nil then
            return false
        end
        local byWeeder = data.weeder == true and (fruit == nil or fruit:getIsWeedable(growthState))
            and getTreatsWeedState(weedSystem:getWeederReplacements(false), state.weedState)
        local byHoe = data.hoe == true and (fruit == nil or fruit:getIsHoeable(growthState))
            and getTreatsWeedState(weedSystem:getWeederReplacements(true), state.weedState)
        return byWeeder or byHoe
    elseif work == FN.WORK.MULCH then
        return fruit ~= nil and fruit.mulchedState ~= nil and fruit.mulchedState ~= 0 and status == "cut"
    elseif work == FN.WORK.PREPARE then
        return fruit ~= nil and data.fruits ~= nil and data.fruits[state.fruitTypeIndex] ~= nil and status == "preparable"
    elseif work == FN.WORK.MOW then
        -- Mower AI requirement: minHarvestingGrowthState..maxHarvestingGrowthState (Mower.lua:224-227).
        return fruit ~= nil and data.fruits ~= nil and data.fruits[state.fruitTypeIndex] ~= nil
            and growthState >= fruit.minHarvestingGrowthState and growthState <= fruit.maxHarvestingGrowthState
    elseif work == FN.WORK.HARVEST then
        -- Cutter AI requirement: from minForageGrowthState only for headers that allow forage
        -- states, else from minHarvestingGrowthState, up to maxHarvestingGrowthState (Cutter.lua:1537-1538).
        local allowsForage = nil
        if data.fruits ~= nil then
            allowsForage = data.fruits[state.fruitTypeIndex]
        end
        if fruit == nil or allowsForage == nil then
            return false
        end
        local minState = fruit.minHarvestingGrowthState
        if allowsForage and (fruit.minForageGrowthState or 0) > 0 then
            minState = fruit.minForageGrowthState
        end
        return growthState >= minState and growthState <= fruit.maxHarvestingGrowthState
    elseif work == FN.WORK.STONES then
        local stones = mission.stoneSystem
        if not info.stonesEnabled or stones == nil or not bare then
            return false
        end
        -- StoneSystem:getStoneLevelAtWorldPos returns the map value minus the mask value; the
        -- picker works on values minValue..maxValue (StonePicker AI requirement).
        local minValue, maxValue = stones:getMinMaxValues()
        local level = (state.stoneLevel or 0) + stones:getMaskValue()
        return (state.stoneLevel or 0) > 0 and level >= minValue and level <= maxValue
    end
    return false
end

-- The works of the combination the field needs, in the combination's order.
function FN.getNeeds(state, works, workList)
    local needs = {}
    if state == nil then
        return needs
    end
    for _, work in ipairs(workList) do
        if FN.getNeedsWork(state, work, works[work]) then
            table.insert(needs, work)
        end
    end
    return needs
end

FN.GROUND_TEXT = {
    STUBBLE_TILLAGE = "ui_growthMapStubbleTillage", CULTIVATED = "ui_growthMapCultivated", SEEDBED = "ui_growthMapSeedbed",
    ROLLED_SEEDBED = "ui_growthMapSeedbed", PLOWED = "ui_growthMapPlowed", SOWN = "ui_growthMapSown",
    DIRECT_SOWN = "ui_growthMapSown", PLANTED = "ui_growthMapSown", RIDGE_SOWN = "ui_growthMapSown"
}
FN.GROWTH_TEXT = {
    cut = "ui_growthMapCut", withered = "ui_growthMapWithered", growing = "ui_growthMapGrowing",
    preparable = "ui_growthMapReadyToPrepareForHarvest", harvestable = "ui_growthMapReadyToHarvest"
}

-- A short state for the "My fields" list, with the game's own field info texts. The crop
-- state follows the info box's order (FN.getGrowthStatus); ready to harvest, remove foliage
-- and withered come before the soil warnings (lime, plowing, rolling), growing and harvested
-- after them, then the ground type.
function FN.getStateText(state)
    if state == nil then
        return ""
    end
    local status = FN.getGrowthStatus(state)
    if status == "harvestable" or status == "preparable" or status == "withered" then
        return g_i18n:getText(FN.GROWTH_TEXT[status])
    end
    if FN.getNeedsWork(state, FN.WORK.LIME) then
        return g_i18n:getText("ui_growthMapNeedsLime")
    end
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or {}
    if getIsBare(state) and info.plowingRequiredEnabled and state.plowLevel == 0 then
        return g_i18n:getText("ui_growthMapNeedsPlowing")
    end
    if FN.getNeedsWork(state, FN.WORK.ROLL) then
        return g_i18n:getText("ui_growthMapNeedsRolling")
    end
    if status ~= nil then
        return g_i18n:getText(FN.GROWTH_TEXT[status])
    end
    for name, key in pairs(FN.GROUND_TEXT) do
        if FieldGroundType[name] == state.groundType then
            return g_i18n:getText(key)
        end
    end
    return ""
end
