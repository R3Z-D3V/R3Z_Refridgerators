local QBCore = exports['qb-core']:GetCoreObject()
local lib = exports.ox_lib

-- Adds ox_target options to fridge models
CreateThread(function()
    for _, model in ipairs(Config.FridgeModels) do
        exports.ox_target:addModel(model, {
            {
                name = 'open_fridge',
                icon = 'fa-solid fa-box-open',
                label = 'Open Fridge',
                distance = Config.TargetDistance,
                onSelect = function(data)
                    local coords = data.coords or GetEntityCoords(PlayerPedId())
                    local fridgeId = tostring(math.floor(coords.x*100)..":"..math.floor(coords.y*100)..":"..math.floor(coords.z*100))
                    -- Try to open a configured stash; if it fails, notify the player.
                    lib.callback('fridge:openStash', false, function(ok)
                        if not ok then
                            QBCore.Functions.Notify('Cannot open fridge stash', 'error')
                        end
                    end, fridgeId)
                end
            },
            {
                name = 'maintain_fridge',
                icon = 'fa-solid fa-screwdriver-wrench',
                label = 'Maintain Fridge',
                distance = Config.TargetDistance,
                onSelect = function(data)
                    local coords = data.coords or GetEntityCoords(PlayerPedId())
                    local fridgeId = tostring(math.floor(coords.x*100)..":"..math.floor(coords.y*100)..":"..math.floor(coords.z*100))
                    -- Open a simple menu using ox_lib to pick maintenance action
                    lib.inputDialog('Maintenance Action', {
                        { type = 'select', label = 'Action', name = 'action', options = {
                            { value = 'deice', label = 'De-ice' },
                            { value = 'filter', label = 'Replace Air Filter' },
                            { value = 'waterfilter', label = 'Replace Water Filter' },
                            { value = 'refrigerant', label = 'Replace Refrigerant' },
                            { value = 'condenser', label = 'Fix Condenser' },
                            { value = 'water', label = 'Hook Water Line' },
                            { value = 'electrical', label = 'Electrical Repair' }
                        }}
                    }, function(submitted)
                        if not submitted then return end
                        local action = submitted.action
                        TriggerServerEvent('fridge:startMaintenance', fridgeId, action)
                    end)
                end
            }
        })
    end
end)



-- Update notifications when server sends fridge state change
RegisterNetEvent('fridge:updateClient', function(fridge)
    -- placeholder: could update UI if you implement one
end)

-- Run maintenance minigame (client)
RegisterNetEvent('fridge:runMaintenanceMinigame', function(fridgeId, action, minigameConfig)
    -- Use ox_lib.skillCheck based minigame sequence
    if not minigameConfig or not minigameConfig.difficulties then
        minigameConfig = Config.Maintenance.Minigame[action]
    end
    local difficulties = (minigameConfig and minigameConfig.difficulties) or {'easy'}
    -- run sequence
    CreateThread(function()
        local success = true
        for _, diff in ipairs(difficulties) do
            local ok = false
            local did = lib.skillCheck({diff})
            if did then ok = true end
            if not ok then success = false break end
            Citizen.Wait(150)
        end
        -- send result to server
        TriggerServerEvent('fridge:maintenanceResult', fridgeId, action, success)
    end)
end)

-- Handlers to open inventory stashes for ox_inventory / qb-inventory
RegisterNetEvent('fridge:openOxStash', function(stashName)
    -- ox_inventory commonly exposes a client event to open stash; adjust if your install differs
    -- best-effort: try known events/exports
    pcall(function()
        -- some ox_inventory installs use an event
        TriggerEvent('ox_inventory:openStash', stashName)
    end)
end)

RegisterNetEvent('fridge:openQbStash', function(stashName)
    pcall(function()
        -- qb-inventory uses the context of identifier + owner; many servers implement custom events
        -- Best-effort: fire a client event that many forks listen to
        TriggerEvent('qb-inventory:client:OpenInventory', 'stash', stashName)
    end)
end)