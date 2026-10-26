-- Which field work a vehicle combination does, and whether a field needs it.
--
-- The field state is read at one point per field (the field's own position, where the game
-- keeps the field's state), the same way the map's field info box reads the point under the
-- cursor: FieldState.new() + FieldState:update(x, z) (1.25 decompiled
-- gui/InGameMenuMapFrame.lua:674-677). A field needs a work when the work would change it now:
-- the conditions follow the game's own work areas (1.25 decompiled utils/FSDensityMapUtil.lua,
-- DMU below) and the requirements the implements give the AI (SDK vehicles/specializations).
-- "My fields" keeps the info box's own wording (:710-780). Unknown or missing data never hides
-- a field.
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
            -- The crops it can sow (spec.seeds, SDK SowingMachine.lua:176-190), for sowing contracts.
            for _, fruitTypeIndex in ipairs(child.spec_sowingMachine.seeds or {}) do
                sow.fruits = sow.fruits or {}
                sow.fruits[fruitTypeIndex] = true
            end
            -- The seed it sows now (spec.seeds[spec.currentSeed], SDK SowingMachine.lua:228/331/405-407)
            -- and whether it may sow outside the season (getCanPlantOutsideSeason, :725-727, false for
            -- the game's own machines), for the field needs. The first seeder of the combination counts.
            local seeds, currentSeed = child.spec_sowingMachine.seeds, child.spec_sowingMachine.currentSeed
            local seed = seeds ~= nil and currentSeed ~= nil and seeds[currentSeed] or nil
            if sow.seed == nil and seed ~= nil then
                sow.seed = seed
                sow.outsideSeason = child.getCanPlantOutsideSeason ~= nil and child:getCanPlantOutsideSeason() == true
            end
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

-- Merged fields: the game keeps one Field per field number, also after the player worked the
-- strip between two fields into one area. Two fields count as merged when the ground is field
-- ground in every density map cell along the straight line between their points (the ground type layer, read like
-- FieldState:update, decompiled field/FieldState.lua:110-111). A concave field whose line
-- leaves it just stays separate.
FN.MERGE_MAX_DISTANCE = 800
-- A merge only changes when a strip is worked, so each pair's result is kept for a minute
-- (the field list refreshes every 10 s).
FN.MERGE_CACHE_TIME = 60000
FN.mergeCache = {}

-- Fields whose outlines' bounding boxes are further apart than this can't touch.
FN.MERGE_BOUNDS_GAP = 30
FN.boundsCache = {}

-- Bounding box of a field's outline (Field:getDensityMapPolygon, DensityMapPolygon:
-- getVerticesList, decompiled densityMaps/DensityMapPolygon.lua:67-77), or nil.
function FN.getFieldBounds(field)
    if field == nil then
        return nil
    end
    local cached = FN.boundsCache[field]
    if cached ~= nil then
        return cached or nil
    end
    local bounds = false
    local polygon = field.getDensityMapPolygon ~= nil and field:getDensityMapPolygon() or nil
    local vertices = polygon ~= nil and polygon.getVerticesList ~= nil and polygon:getVerticesList() or nil
    if vertices ~= nil and #vertices >= 2 then
        bounds = {minX = math.huge, minZ = math.huge, maxX = -math.huge, maxZ = -math.huge}
        for i = 1, #vertices - 1, 2 do
            bounds.minX, bounds.maxX = math.min(bounds.minX, vertices[i]), math.max(bounds.maxX, vertices[i])
            bounds.minZ, bounds.maxZ = math.min(bounds.minZ, vertices[i + 1]), math.max(bounds.maxZ, vertices[i + 1])
        end
    end
    FN.boundsCache[field] = bounds
    return bounds or nil
end

-- Sampling step: one density map cell (terrain size / map size), so no strip is stepped over.
function FN.getSampleStep(system)
    local terrainSize = g_currentMission ~= nil and g_currentMission.terrainSize or nil
    local map = system.getDensityMapData ~= nil and system:getDensityMapData(FieldDensityMap.GROUND_TYPE) or nil
    if map ~= nil and terrainSize ~= nil and getDensityMapSize ~= nil then
        local size = getDensityMapSize(map)
        if size ~= nil and size > 0 then
            return terrainSize / size * 0.9
        end
    end
    return 0.5
end

function FN.getIsGroundConnected(x1, z1, x2, z2, bounds1, bounds2)
    if bounds1 ~= nil and bounds2 ~= nil then
        local gapX = math.max(bounds1.minX - bounds2.maxX, bounds2.minX - bounds1.maxX, 0)
        local gapZ = math.max(bounds1.minZ - bounds2.maxZ, bounds2.minZ - bounds1.maxZ, 0)
        if gapX > FN.MERGE_BOUNDS_GAP or gapZ > FN.MERGE_BOUNDS_GAP then
            return false
        end
    end
    local now = g_time or 0
    local key = string.format("%.1f,%.1f,%.1f,%.1f", x1 or 0, z1 or 0, x2 or 0, z2 or 0)
    local cached = FN.mergeCache[key]
    if cached ~= nil and now - cached.time < FN.MERGE_CACHE_TIME then
        return cached.connected
    end
    local connected = FN.readIsGroundConnected(x1, z1, x2, z2)
    FN.mergeCache[key] = {connected = connected, time = now}
    return connected
end

function FN.readIsGroundConnected(x1, z1, x2, z2)
    local system = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil
    if system == nil or system.getValueAtWorldPos == nil or x1 == nil or x2 == nil then
        return false
    end
    local dx, dz = x2 - x1, z2 - z1
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance > FN.MERGE_MAX_DISTANCE then
        return false
    end
    local steps = math.max(1, math.ceil(distance / FN.getSampleStep(system)))
    for i = 0, steps do
        local t = i / steps
        local value = system:getValueAtWorldPos(FieldDensityMap.GROUND_TYPE, x1 + dx * t, 0, z1 + dz * t)
        if FieldGroundType.getTypeByValue(value) == FieldGroundType.NONE then
            return false
        end
    end
    return true
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
    -- stubbleShredLevel: SDK field/FieldState.lua:49, read by FieldState:update (1.24 decompiled :118).
    for _, key in ipairs({"fruitTypeIndex", "growthState", "groundType", "sprayType", "sprayLevel", "limeLevel",
        "plowLevel", "rollerLevel", "weedState", "stoneLevel", "stubbleShredLevel"}) do
        state[key] = fieldState[key]
    end
    if state.fruitTypeIndex ~= nil and state.fruitTypeIndex ~= FruitType.UNKNOWN then
        state.fruit = g_fruitTypeManager:getFruitTypeByIndex(state.fruitTypeIndex)
    end
    state.fieldType = FN.readFieldType(x, z)
    return state
end

-- The field type (default or rice field) at a point: FSDensityMapUtil.getFieldTypeAtWorldPos
-- (DMU:2888-2895), the check the sowing machine makes (SDK SowingMachine.lua:541-555). It reads
-- the FIELD_TYPE layer without a nil check, so it is only asked when the map has that layer
-- (FieldGroundSystem:getDensityMapData returns nil otherwise, 1.24 decompiled
-- field/FieldGroundSystem.lua:500-507).
function FN.readFieldType(x, z)
    local system = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil
    if FSDensityMapUtil == nil or FSDensityMapUtil.getFieldTypeAtWorldPos == nil or FieldDensityMap.FIELD_TYPE == nil
        or system == nil or system.getDensityMapData == nil or system:getDensityMapData(FieldDensityMap.FIELD_TYPE) == nil then
        return nil
    end
    return FSDensityMapUtil.getFieldTypeAtWorldPos(x, z)
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

-- Whether a ground type's density map value lies in one of the field ground system's ranges;
-- nil when the range or the value can't be read.
local function getIsInGroundRange(groundType, first, last)
    if groundType == nil or first == nil or last == nil or FieldGroundType.getValueByType == nil then
        return nil
    end
    local value = FieldGroundType.getValueByType(groundType)
    if value == nil then
        return nil
    end
    return value >= first and value <= last
end

-- Sowable ground: worked soil ready for a seeder, stubble tillage to ridge
-- (FieldGroundSystem:getSowableRange, 1.24 decompiled field/FieldGroundSystem.lua:195-196/485-487;
-- FieldGroundType.getValueByType, field/FieldGroundType.lua:19-21). The game's work areas test
-- this range for lime, rolling, herbicide, weeding and stones. Without the range: the seeder's
-- AI ground types, the same list (SowingMachine.AI_REQUIRED_GROUND_TYPES).
function FN.getIsSowableGround(groundType)
    local system = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil
    if system ~= nil and system.getSowableRange ~= nil then
        local result = getIsInGroundRange(groundType, system:getSowableRange())
        if result ~= nil then
            return result
        end
    end
    return SowingMachine ~= nil and getHasGroundType(SowingMachine.AI_REQUIRED_GROUND_TYPES, groundType)
end

-- Sown ground: sown, direct sown, planted or ridge sown (FieldGroundSystem:getSowingRange,
-- 1.24 decompiled field/FieldGroundSystem.lua:197-198/488-490); the same four types without it.
function FN.getIsSowingGround(groundType)
    local system = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil
    if system ~= nil and system.getSowingRange ~= nil then
        local result = getIsInGroundRange(groundType, system:getSowingRange())
        if result ~= nil then
            return result
        end
    end
    return groundType ~= nil and (groundType == FieldGroundType.SOWN or groundType == FieldGroundType.DIRECT_SOWN
        or groundType == FieldGroundType.PLANTED or groundType == FieldGroundType.RIDGE_SOWN)
end

-- Whether the combination's seeder can sow its selected seed here now. The sowing machine plants
-- nothing outside the seed's planting periods (FruitTypeDesc:getIsPlantableInPeriod with the
-- save's growth mode and the current period, 1.25 decompiled fruits/FruitTypeDesc.lua:707-709;
-- SDK SowingMachine.lua:1017-1036) and its AI stops with "wrong season" (:851-866); a seed that
-- needs a field type (rice) is not planted elsewhere and the AI stops there (:541-555).
function FN.getCanSowSeed(state, data)
    local desc = data.seed ~= nil and g_fruitTypeManager:getFruitTypeByIndex(data.seed) or nil
    if desc == nil then
        return true
    end
    local mission = g_currentMission
    local info = mission ~= nil and mission.missionInfo or nil
    local environment = mission ~= nil and mission.environment or nil
    if not data.outsideSeason and desc.getIsPlantableInPeriod ~= nil and info ~= nil and info.growthMode ~= nil
        and environment ~= nil and environment.currentPeriod ~= nil
        and not desc:getIsPlantableInPeriod(info.growthMode, environment.currentPeriod) then
        return false
    end
    if desc.seedRequiredFieldType ~= nil and state.fieldType ~= nil and state.fieldType ~= desc.seedRequiredFieldType then
        return false
    end
    return true
end

-- Weed states a tool can treat: the source states of its weed replacement table
-- (WeedSystem:getWeederReplacements(isHoe) / getHerbicideReplacements, as the implements give
-- them to the AI: SDK Weeder.lua:209-229, Sprayer.lua:722-741).
local function getTreatsWeedState(replacementData, weedState)
    local weed = replacementData ~= nil and replacementData.weed or nil
    return weed ~= nil and weed.replacements ~= nil and weed.replacements[weedState] ~= nil
end

-- Whether the field already carries this spray type's ground marker, which is what makes the
-- game's AI skip it (Sprayer.lua:744-758): fertilizer once until the marker is cleared. The
-- field state keeps a FieldSprayType type (FieldState:update, FieldSprayType.getTypeByValue,
-- decompiled field/FieldState.lua:112-113), the spray type a density map value
-- (SprayTypeManager:loadSprayTypes, FieldSprayType.getValueByName, decompiled
-- misc/SprayTypeManager.lua:55), so the value is turned into its type before comparing.
local function getHasSprayMarker(state, sprayType)
    if sprayType == nil or sprayType.sprayGroundType == nil or state.sprayType == nil or FieldSprayType == nil then
        return false
    end
    return FieldSprayType.getTypeByValue(sprayType.sprayGroundType) == state.sprayType
end

-- Whether a field in this state needs one work and the work can be done now, with the
-- combination's data for that work. The settings come from the field info box (lime:
-- useLimeCounter, limeRequired, limeLevel == 0; plowing: plowingRequiredEnabled, plowLevel == 0;
-- rolling: useRolling, rollerLevel > 0; weeds: weedsEnabled, weedState > 0, MF:744-772); the crop
-- and ground conditions from the game's work areas (DMU), so a field is only listed when the work
-- would change it (no lime on a growing crop, for example).
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
        local ground = getHasGroundType(SowingMachine.AI_REQUIRED_GROUND_TYPES, groundType)
            or (data.direct == true and getHasGroundType(SowingMachine.AI_OUTPUT_GROUND_TYPES, groundType))
        return ground and FN.getCanSowSeed(state, data)
    elseif work == FN.WORK.ROLL then
        -- Soil rolling (DMU:250-325): sowable ground with or without a crop, or sown ground while
        -- the crop is in its first growth state; the roller AI keeps off crops from the second state
        -- on (SDK Roller.lua:205-216). Crops that need no rolling (needsRolling, SDK
        -- FruitTypeDesc.lua:533) get no roller level when sown (DMU:2081) and are skipped.
        if gameplay.useRolling ~= true or (state.rollerLevel or 0) <= 0 or (fruit ~= nil and fruit.needsRolling == false) then
            return false
        end
        return FN.getIsSowableGround(groundType) or (fruit ~= nil and growthState == 1 and FN.getIsSowingGround(groundType))
    elseif work == FN.WORK.LIME then
        -- Lime takes on field ground without a crop, with a crop in its first growth state or past
        -- harvest (withered, harvested), and on sowable ground (DMU:1398-1466: 1417, 1440, 1443,
        -- 1446); the straw/maize chopper ground of :1421 is left out. The AI skips ground that
        -- already has this spray type (Sprayer.lua:753-758).
        local sprayType = data.sprayType
        return gameplay.useLimeCounter == true and info.limeRequired == true and state.limeLevel == 0
            and not getHasSprayMarker(state, sprayType)
            and (fruit == nil or growthState <= 1 or growthState > fruit.maxHarvestingGrowthState
                or FN.getIsSowableGround(groundType))
    elseif work == FN.WORK.FERTILIZE then
        -- Fertilizer takes on field ground except crops from their first to their last harvest
        -- state (DMU:1336-1397, 1354); withered crops are left out too. The AI skips the maximum
        -- spray level and ground that already has this fertilizer's spray type (Sprayer.lua:744-751).
        local maxLevel = mission.fieldGroundSystem ~= nil and mission.fieldGroundSystem:getMaxValue(FieldDensityMap.SPRAY_LEVEL) or 0
        local sprayType = data.sprayType
        return (state.sprayLevel or 0) < maxLevel and status ~= "withered" and not getHasSprayMarker(state, sprayType)
            and (fruit == nil or growthState < fruit.minHarvestingGrowthState or growthState > fruit.maxHarvestingGrowthState)
    elseif work == FN.WORK.HERBICIDE then
        -- Herbicide takes on sowable ground, on crops before their first harvest state and on the
        -- state wheels leave (DMU:1467-1545: 1508, 1515, 1522-1524); the cutState + 1 case of
        -- :1519 is left out.
        if info.weedsEnabled ~= true or (state.weedState or 0) <= 0 or weedSystem == nil
            or not getTreatsWeedState(weedSystem:getHerbicideReplacements(), state.weedState) then
            return false
        end
        return FN.getIsSowableGround(groundType)
            or (fruit ~= nil and growthState >= 1 and growthState < fruit.minHarvestingGrowthState)
            or (fruit ~= nil and fruit.wheelDestructionState ~= nil and growthState == fruit.wheelDestructionState)
    elseif work == FN.WORK.WEED then
        -- Weeder and hoe: crops in their weeder states (stricter than the game's 0..max, which also
        -- takes the cut state, DMU:1587-1589), or sowable ground (:1573).
        if info.weedsEnabled ~= true or (state.weedState or 0) <= 0 or weedSystem == nil then
            return false
        end
        local sowable = FN.getIsSowableGround(groundType)
        local byWeeder = data.weeder == true and (fruit == nil or fruit:getIsWeedable(growthState) or sowable)
            and getTreatsWeedState(weedSystem:getWeederReplacements(false), state.weedState)
        local byHoe = data.hoe == true and (fruit == nil or fruit:getIsHoeable(growthState) or sowable)
            and getTreatsWeedState(weedSystem:getWeederReplacements(true), state.weedState)
        return byWeeder or byHoe
    elseif work == FN.WORK.MULCH then
        -- The mulcher works crops that allow cultivation in states 2..cutState other than their
        -- mulched state (DMU:1761-1814, 1786-1788) and, with stubble shredding
        -- (Platform.gameplay.useStubbleShred, true on PC, 1.25 decompiled platform/Platform.lua:181),
        -- raises the stubble shred level by one (:1796), which the harvest rewards at level 1
        -- (DMU:141, 171-176). Listed: harvested or withered crops not shredded yet; the mulcher
        -- would also destroy a growing crop.
        if fruit == nil or fruit.isCultivationAllowed == false or (status ~= "cut" and status ~= "withered") then
            return false
        end
        if growthState < 2 or growthState > (fruit.cutState or 0) or growthState == fruit.mulchedState then
            return false
        end
        return gameplay.useStubbleShred ~= true or (state.stubbleShredLevel or 0) == 0
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
        -- The stone picker works sowable ground only (DMU:535-591, 558; AI: SDK StonePicker.lua:139-145).
        local stones = mission.stoneSystem
        if not info.stonesEnabled or stones == nil or not FN.getIsSowableGround(groundType) then
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
-- and withered come before the soil warnings, growing and harvested after them, then the ground
-- type. The soil warnings are the info box's own (MF:744-753): needs lime and needs rolling
-- whatever the crop, unlike the needs list, which only lists what can be done now.
function FN.getStateText(state)
    if state == nil then
        return ""
    end
    local status = FN.getGrowthStatus(state)
    if status == "harvestable" or status == "preparable" or status == "withered" then
        return g_i18n:getText(FN.GROWTH_TEXT[status])
    end
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or {}
    local gameplay = Platform ~= nil and Platform.gameplay or {}
    if gameplay.useLimeCounter == true and info.limeRequired == true and state.limeLevel == 0 then
        return g_i18n:getText("ui_growthMapNeedsLime")
    end
    if getIsBare(state) and info.plowingRequiredEnabled and state.plowLevel == 0 then
        return g_i18n:getText("ui_growthMapNeedsPlowing")
    end
    if gameplay.useRolling == true and (state.rollerLevel or 0) > 0 then
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
