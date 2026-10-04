-- Wagon Speed Variants for Transport Fever 3.
-- New metadata only: all geometry, animations, icons and sounds stay in their
-- source packages. No optional package is imported or required by this script.
local mod = {}
local MOD_ID = "jean_luc_picard_wagon_speed_variants"
local PREFIX = MOD_ID .. "::/generated/"
local SOURCES = {
    [""] = true,
    ug_legacy_waggon_1850 = true,
    urbangames_preorder_pack = true,
    urbangames_deluxe_upgrade_pack = true,
}
local CLASSES = {
    { key = "economy", label = "Economy", delta = -20 },
    { key = "standard", label = "Standard", delta = 0 },
    { key = "rapid", label = "Rapid", delta = 20 },
    { key = "express", label = "Express", delta = 40 },
    { key = "limited_express", label = "Limited Express", delta = 60 },
}
local ICON_FIELDS = {
    "iconSmall", "iconSmallCblend", "icon3d", "icon20", "icon20cblend",
    "icon", "previewIcon", "lockedIcon", "smallIcon", "smallIconCblend",
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function splitResource(name)
    local owner, path = name:match("^(.-)::(/.*)$")
    return owner, path
end

local function wagonFolder(path)
    -- Standalone Mark 3 and DPZ coaches live beside their locomotives.
    -- The metadata checks below still reject powered stock and trainset parts.
    return path:match("^/vehicle/waggon/.*%.mdl$")
        or path:match("^/vehicle/train/.*%.mdl$")
end

local function classLabel(class)
    local key = "WSV_Class_" .. class.key
    -- In resource-loading contexts _() may only mark a key for later lookup.
    -- Resolve before concatenating, using TF3's base/mod.lua helper.
    local translated = type(getTextRes) == "function" and getTextRes(key) or _(key)
    if type(translated) ~= "string" or translated == key then return class.label end
    return translated
end

local function eligible(name, model)
    local owner, path = splitResource(name)
    if not owner or not SOURCES[owner] then return false end
    if not wagonFolder(path) then return false end
    local metadata = model.metadata or {}
    local tv, lv = metadata.transportVehicle, metadata.landVehicle
    if not tv or not lv or not metadata.railVehicle then return false end
    if tv.carrier ~= "RAIL" then return false end
    if type(lv.topSpeed) ~= "number" or lv.topSpeed <= 1 / 3.6
        or lv.topSpeed ~= lv.topSpeed or lv.topSpeed == math.huge then return false end
    if tv.multipleUnitOnly then return false end
    if tv.filterTags and next(tv.filterTags) == nil then return false end
    for _, engine in pairs(lv.engines or {}) do
        if (engine.power or 0) > 0 or (engine.tractiveEffort or 0) > 0 then return false end
    end
    local hasCapacity = false
    for _, compartment in pairs(tv.compartments or {}) do
        for _, config in pairs(compartment.loadConfigs or {}) do
            if config.cargoEntry and (config.cargoEntry.capacity or 0) > 0 then
                hasCapacity = true
            end
        end
    end
    return hasCapacity and metadata.description ~= nil
end

local function generatedName(source, suffix)
    local owner, path = splitResource(source)
    return PREFIX .. (owner == "" and "base" or owner)
        .. path:gsub("%.mdl$", "_wsv_" .. suffix .. ".mdl")
end

local function costRatio(oldSpeed, newSpeed)
    -- Matches calcVehicleAverageSpeed for rail vehicles in TF3's
    -- base/model_metadata_util.lua. Capacity and all other properties are equal
    -- across a wagon's variants, so the other cost factors cancel out.
    return ((newSpeed * 3.6) ^ 0.86 + 10) / ((oldSpeed * 3.6) ^ 0.86 + 10)
end

local function scaleResolvedCost(container, field, ratio)
    if container and type(container[field]) == "number" and container[field] > 0 then
        container[field] = math.max(1, math.floor(container[field] * ratio + 0.5))
    end
    -- Zero remains free. Negative values retain TF3's automatic calculation:
    -- the changed topSpeed already affects it; applying ratio again doubles it.
end

local function visualClone(sourceName, original)
    local result = copy(original)
    -- getAsTable returns metadata, not new render geometry. Reuse the loaded
    -- source model explicitly, including its already resolved resource paths.
    if not result.modelPath or result.modelPath == "" then
        result.modelPath = sourceName
    end
    -- Description icons remain relative in getAsTable. Moving those strings
    -- under our generated resource would resolve them in the wrong package.
    -- Pin every supplied UI icon to its source context, including color masks.
    local sourceOwner, sourcePath = splitResource(sourceName)
    local sourceFolder = sourcePath:match("^(.*)/[^/]+$")
    local description = result.metadata.description
    for _, field in ipairs(ICON_FIELDS) do
        local reference = description[field]
        if type(reference) == "string" and reference ~= "" then
            local owner, path = reference:match("^(.-)::(.*)$")
            if owner == nil then owner, path = sourceOwner, reference end
            if path:sub(1, 1) ~= "/" then path = sourceFolder .. "/" .. path end
            description[field] = owner .. "::" .. path
        end
    end
    return result
end

function mod.postRunFn()
    local rep = api.res.modelRep
    local candidates = {}
    -- Snapshot first. Never iterate a repository while adding entries to it.
    for id, name in pairs(rep.getAll()) do
        local owner, path = splitResource(name)
        if owner and SOURCES[owner] and wagonFolder(path)
            and rep.isVisible(id) then
            candidates[#candidates + 1] = { id = id, name = name }
        end
    end
    table.sort(candidates, function(a, b) return a.name < b.name end)

    local counts = { base = 0, early = 0, dlc = 0 }
    local added = 0
    for _, candidate in ipairs(candidates) do
        local sourceName = candidate.name
        local parentName = generatedName(sourceName, "group")
        -- Deterministic resource names survive load-order changes and saves.
        -- An already registered group also makes a repeated hook a no-op.
        if rep.find(parentName) == -1 then
            local original = rep.getAsTable(candidate.id)
            if eligible(sourceName, original) then
                -- getAsTable serializes localized strings as tables. Use the
                -- typed native accessor for display text, and leave the other
                -- serialized localization values untouched for round-tripping.
                local originalName = rep.get(candidate.id).metadata.description.name
                assert(type(originalName) == "string",
                    "WSV: native display name is not a string for " .. sourceName)
                local originalSpeed = original.metadata.landVehicle.topSpeed
                local parent = visualClone(sourceName, original)
                parent.metadata.transportVehicle.groupFileName = ""
                -- Empty filter tags prevent this menu-only parent being bought.
                parent.metadata.transportVehicle.filterTags = {}
                local parentId = rep.addAsTable(parentName, parent)
                assert(parentId and parentId >= 0, "WSV: cannot add group for " .. sourceName)

                for _, class in ipairs(CLASSES) do
                    if class.delta ~= 0 then
                        local variant = visualClone(sourceName, original)
                        local newSpeed = math.max(1 / 3.6, originalSpeed + class.delta / 3.6)
                        variant.metadata.landVehicle.topSpeed = newSpeed
                        variant.metadata.description.name = originalName .. " - " .. classLabel(class)
                        variant.metadata.transportVehicle.groupFileName = parentName
                        local ratio = costRatio(originalSpeed, newSpeed)
                        scaleResolvedCost(variant.metadata.cost, "price", ratio)
                        scaleResolvedCost(variant.metadata.maintenance, "runningCosts", ratio)
                        local variantName = generatedName(sourceName, class.key)
                        assert(rep.find(variantName) == -1, "WSV: resource collision " .. variantName)
                        local variantId = rep.addAsTable(variantName, variant)
                        assert(variantId and variantId >= 0, "WSV: cannot add " .. variantName)
                        added = added + 1
                    end
                end

                -- Only edit the two UI fields on the existing native object.
                -- Avoid reloading the complete original through setAsTable:
                -- its falsy return caused r3 to abort even without a Lua error.
                -- No original resource is replaced, hidden, removed or re-added.
                local nativeOriginal = rep.get(candidate.id)
                local standardName = originalName .. " - " .. classLabel(CLASSES[2])
                nativeOriginal.metadata.description.name = standardName
                nativeOriginal.metadata.transportVehicle.groupFileName = parentName
                local verified = rep.get(candidate.id)
                assert(rep.find(sourceName) == candidate.id
                    and verified.metadata.description.name == standardName
                    and verified.metadata.transportVehicle.groupFileName == parentName,
                    "WSV: original wagon UI update did not persist for " .. sourceName)
                local owner = splitResource(sourceName)
                local bucket = owner == "" and "base"
                    or (owner == "ug_legacy_waggon_1850" and "early" or "dlc")
                counts[bucket] = counts[bucket] + 1
            end
        end
    end
    debugPrint(string.format(
        "[Wagon Speed Variants r9] %d base + %d Early Wagons + %d DLC wagons; %d additional variants. Original wagon IDs and UI updates verified; localized classes; icons reference source packages. Early Wagons is optional.",
        counts.base, counts.early, counts.dlc, added))
end

-- .script.lua is a TF3 resource, not an ug_require module: the resource loader
-- calls data() and then resolves @postRunFn from the returned table.
function data()
    return mod
end
