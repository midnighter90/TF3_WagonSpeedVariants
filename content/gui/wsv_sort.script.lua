-- Installed at the game's UI bootstrap, after the store module is loaded.
-- The store sorts group children by getPrimaryBucket before its user-selected
-- secondary sort. Refine that bucket for our five classes only. No recipes or
-- original GUI files need to be copied; original vehicle categories stay intact.
local PREFIX = "jean_luc_picard_wagon_speed_variants::/generated/"
local RANK = { economy = 1, standard = 2, rapid = 3, express = 4, limited_express = 5 }
local installed = false

local function install()
    if installed then return end
    local store = ug_require("::/gui/line_vehicle_mgmt/vehicle_store_util.tl")
    if type(store) ~= "table" or type(store.getPrimaryBucket) ~= "function" then
        debugPrint("[Wagon Speed Variants r9] Depot sorting unavailable: store API changed.")
        return
    end
    local originalBucket = store.getPrimaryBucket
    store.getPrimaryBucket = function(elem)
        local bucket = originalBucket(elem)
        local rank = 0
        local group = elem.vehicleData and elem.vehicleData.variantGroup
        if type(group) == "string" and group:sub(1, #PREFIX) == PREFIX then
            local path = elem.path or ""
            if path:sub(1, #PREFIX) == PREFIX then
                rank = RANK[path:match("_wsv_(.-)%.mdl$")] or 0
            else
                -- Standard is the unchanged original resource, not a clone.
                rank = RANK.standard
            end
        end
        -- Keep the integer return type and category ordering of the native API.
        return bucket * 10 + rank
    end
    installed = true
    debugPrint("[Wagon Speed Variants r9] Depot class order installed.")
end

function data()
    return { install = install }
end
