local QBCore = exports['qb-core']:GetCoreObject()

-- In-memory store for fridge data
local fridges = {} -- fridgeId -> {slots = { {itemName, amount, metadata, storedAt = timestamp} }}

-- Config aliases
local storageFile = Config.StorageFile
local decayFactor = Config.DecayFactor
local maxSlots = Config.MaxSlots
local perishable = Config.PerishableItems

local enableOx = Config.EnableOxInventory
local enableQb = Config.EnableQbInventory
local stashProvider = Config.StashProvider or 'ox'
local stashPrefix = Config.StashPrefix or 'fridge_'

local useOxmysql = Config.UseOxmysql

-- Metrics (simple counters)
local metrics = {
    stores = 0,
    retrieves = 0,
    swaps = 0,
    backups = 0,
}

-- Audit/logging helpers
local function auditLog(line)
    -- Timestamped line
    local tsline = string.format("[%s] %s", os.date('%Y-%m-%d %H:%M:%S'), line)
    if Config.EnableAuditFileLog then
        local file = io.open(GetResourcePath(GetCurrentResourceName())..'/'..Config.AuditLogFile, 'a')
        if file then
            file:write(tsline.."\n")
            file:close()
        end
    end
    if Config.EnableAuditWebhook and Config.AuditWebhookURL and Config.AuditWebhookURL ~= '' then
        -- send minimal webhook payload (pcall to avoid errors)
        pcall(function()
            PerformHttpRequest(Config.AuditWebhookURL, function() end, 'POST', json.encode({embeds = {{title = 'Fridge Audit', description = tsline}}}), {['Content-Type']='application/json'})
        end)
    end
end

-- Simple metric reporting command for admins/devs (no permission enforcement by request)
QBCore.Commands.Add('fridgemetrics', 'Show fridge metrics', {}, false, function(source, args)
    local msg = string.format('Stores:%d Retrieves:%d Swaps:%d Backups:%d', metrics.stores, metrics.retrieves, metrics.swaps, metrics.backups)
    if source == 0 then
        print(msg)
    else
        TriggerClientEvent('QBCore:Notify', source, msg, 'primary')
    end
end)


-- Helper wrappers: try integration then fallback to QBCore (atomic attempt)
local function tryRemoveItem(player, itemName, amount, metadata)
    -- basic validation
    if amount <= 0 then return false end
    -- try qb-inventory server event
    if enableQb then
        local ok, err = pcall(function()
            TriggerEvent('qb-inventory:server:RemoveItem', player.PlayerData.source, itemName, amount, metadata)
        end)
        if ok then return true end
    end
    if enableOx then
        local ok, err = pcall(function()
            TriggerEvent('ox_inventory:removeItem', player.PlayerData.source, itemName, amount, metadata)
        end)
        if ok then return true end
    end
    -- Fallback to QBCore Functions
    return player.Functions.RemoveItem(itemName, amount, metadata)
end

local function tryAddItem(player, itemName, amount, metadata)
    if amount <= 0 then return false end
    if enableQb then
        local ok, err = pcall(function()
            TriggerEvent('qb-inventory:server:AddItem', player.PlayerData.source, itemName, amount, metadata)
        end)
        if ok then return true end
    end
    if enableOx then
        local ok, err = pcall(function()
            TriggerEvent('ox_inventory:addItem', player.PlayerData.source, itemName, amount, metadata)
        end)
        if ok then return true end
    end
    return player.Functions.AddItem(itemName, amount, false, metadata)
end

-- Helper to open stash (creates a persistent key for fridge contents). Server-side triggers client to open the specific stash.
local function openStashForPlayer(src, fridgeId)
    local stashName = stashPrefix .. tostring(fridgeId)
    if stashProvider == 'ox' and enableOx then
        TriggerClientEvent('fridge:openOxStash', src, stashName)
        return true
    elseif stashProvider == 'qb' and enableQb then
        TriggerClientEvent('fridge:openQbStash', src, stashName)
        return true
    else
        return false
    end
end

-- Utility: DB-backed load/save with oxmysql (falls back to file if oxmysql missing)
local hasOxmysql = false
local ok, _ = pcall(function() hasOxmysql = (exports.oxmysql ~= nil) end)
if useOxmysql and hasOxmysql then hasOxmysql = true else hasOxmysql = false end

local function createFridgesTableIfNotExists()
    if not hasOxmysql then return end
    local sql = [[
    CREATE TABLE IF NOT EXISTS fridges (
        id VARCHAR(64) PRIMARY KEY,
        name VARCHAR(64) DEFAULT NULL,
        coords_x DOUBLE DEFAULT 0,
        coords_y DOUBLE DEFAULT 0,
        coords_z DOUBLE DEFAULT 0,
        data LONGTEXT NOT NULL,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    );
    ]]
    exports.oxmysql:execute(sql, {})
end

local function saveFridgeToDB(id, tbl)
    if not hasOxmysql then
        local encoded = json.encode(fridges)
        SaveResourceFile(GetCurrentResourceName(), storageFile, encoded, -1)
        return
    end
    local jsonData = json.encode(tbl)
    local sql = [[
    INSERT INTO fridges (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = ? , updated_at = NOW();
    ]]
    exports.oxmysql:execute(sql, { tostring(id), jsonData, jsonData })
end

local function saveFridges()
    if hasOxmysql then
        for id, tbl in pairs(fridges) do
            saveFridgeToDB(id, tbl)
        end
    else
        local encoded = json.encode(fridges)
        SaveResourceFile(GetCurrentResourceName(), storageFile, encoded, -1)
    end
end

local function loadFridges()
    if hasOxmysql then
        createFridgesTableIfNotExists()
        local rows = exports.oxmysql:fetchSync('SELECT id, data FROM fridges', {})
        if rows and type(rows) == 'table' then
            for _, row in ipairs(rows) do
                if row.id and row.data then
                    local ok, data = pcall(json.decode, row.data)
                    if ok and type(data) == 'table' then
                        fridges[tostring(row.id)] = data
                    end
                end
            end
        end
    else
        local content = LoadResourceFile(GetCurrentResourceName(), storageFile)
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == 'table' then
                fridges = data
            end
        end
    end
end

-- On start: load from DB or file
AddEventHandler('onResourceStart', function(resName)
    if resName == GetCurrentResourceName() then
        loadFridges()
    end
end)

-- Helper: ensure fridge object exists
local function ensureFridge(id)
    if not fridges[id] then
        fridges[id] = { slots = {}, maintenance = {
            temperature = 4.0, -- degrees Celsius
            ice_level = 0, -- 0-100
            filter_condition = 100, -- 0-100
            refrigerant_level = 100, -- 0-100
            condenser_health = 100, -- 0-100
            water_hooked = false,
            electrical_health = 100,
            last_maintenance = os.time()
        } }
    else
        -- ensure maintenance table exists for older data
        fridges[id].maintenance = fridges[id].maintenance or {
            temperature = 4.0,
            ice_level = 0,
            filter_condition = 100,
            refrigerant_level = 100,
            condenser_health = 100,
            water_hooked = false,
            electrical_health = 100,
            last_maintenance = os.time()
        }
    end
end

-- Validation helper
local function validateStoreRequest(itemName, amount)
    if type(itemName) ~= 'string' or itemName == '' then return false, 'invalid_item' end
    amount = tonumber(amount) or 0
    if amount <= 0 or amount > Config.MaxStorePerAction then return false, 'invalid_amount' end
    if not perishable[itemName] then return false, 'not_perishable' end
    return true
end

-- Server event: store item in fridge (atomic: remove then persist)
RegisterNetEvent('fridge:storeItem', function(fridgeId, itemName, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    amount = tonumber(amount) or 0

    local ok, err = validateStoreRequest(itemName, amount)
    if not ok then return TriggerClientEvent('QBCore:Notify', src, Config.Locale.invalid_amount, 'error') end

    -- Validate player has item
    if not Player.Functions.GetItemByName(itemName) then
        return TriggerClientEvent('QBCore:Notify', src, Config.Locale.no_item, 'error')
    end

    -- Remove from player first (server-side validation)
    local removed = tryRemoveItem(Player, itemName, amount)
    if not removed then
        return TriggerClientEvent('QBCore:Notify', src, 'Failed to remove item', 'error')
    end

    ensureFridge(tostring(fridgeId))
    local fridge = fridges[tostring(fridgeId)]

    -- Find same item stack to merge, else add new slot
    local remaining = amount
    for i, slot in ipairs(fridge.slots) do
        if slot.itemName == itemName and slot.metadata == nil and remaining > 0 then
            slot.amount = slot.amount + remaining
            slot.storedAt = os.time()
            remaining = 0
            break
        end
    end
    if remaining > 0 then
        if #fridge.slots >= maxSlots then
            -- rollback: give item back
            Player.Functions.AddItem(itemName, amount)
            return TriggerClientEvent('QBCore:Notify', src, Config.Locale.fridge_full, 'error')
        end
        table.insert(fridge.slots, { itemName = itemName, amount = remaining, metadata = nil, storedAt = os.time() })
    end

    saveFridges()
    TriggerClientEvent('QBCore:Notify', src, Config.Locale.stored..' '..amount..' '..itemName, 'success')
    TriggerClientEvent('fridge:updateClient', src, fridge)

    -- Audit
    metrics.stores = metrics.stores + 1
    auditLog(string.format('%s stored %d %s into fridge %s', Player.PlayerData.citizenid or tostring(src), amount, itemName, tostring(fridgeId)))
end)

-- Server event: retrieve item from fridge
RegisterNetEvent('fridge:retrieveItem', function(fridgeId, slotIndex, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    amount = tonumber(amount) or 0
    slotIndex = tonumber(slotIndex) or 0
    if amount <= 0 or slotIndex < 1 then return TriggerClientEvent('QBCore:Notify', src, Config.Locale.invalid_request, 'error') end

    ensureFridge(tostring(fridgeId))
    local fridge = fridges[tostring(fridgeId)]
    local slot = fridge.slots[slotIndex]
    if not slot then return TriggerClientEvent('QBCore:Notify', src, Config.Locale.invalid_request, 'error') end
    if amount > slot.amount then amount = slot.amount end

    -- Calculate spoilage adjustment: time spent in fridge counts for less
    local now = os.time()
    local storedAt = slot.storedAt or now
    local elapsed = now - storedAt
    local effectiveElapsed = math.floor(elapsed * decayFactor)

    local newMeta = slot.metadata or {}
    if type(newMeta) == 'table' and newMeta.spoilage then
        local originalSpoilage = newMeta.spoilage or 0
        newMeta.spoilage = originalSpoilage + effectiveElapsed
    else
        newMeta._refrigerated = true
    end

    -- Give item back to player with adjusted metadata (try integrations then fallback)
    local added = tryAddItem(Player, slot.itemName, amount, newMeta)
    if not added then
        Player.Functions.AddItem(slot.itemName, amount, false, newMeta)
    end

    -- Deduct from fridge
    slot.amount = slot.amount - amount
    if slot.amount <= 0 then
        table.remove(fridge.slots, slotIndex)
    end

    saveFridges()
    TriggerClientEvent('QBCore:Notify', src, Config.Locale.retrieved..' '..amount..' '..slot.itemName, 'success')
    TriggerClientEvent('fridge:updateClient', src, fridge)

    -- Audit
    metrics.retrieves = metrics.retrieves + 1
    auditLog(string.format('%s retrieved %d %s from fridge %s', Player.PlayerData.citizenid or tostring(src), amount, slot.itemName, tostring(fridgeId)))
end)

-- Provide an RPC to fetch fridge contents for client UI
QBCore.Functions.CreateCallback('fridge:getContents', function(source, cb, fridgeId)
    ensureFridge(tostring(fridgeId))
    cb(fridges[tostring(fridgeId)])
end)

-- Server event: swap two fridge slots (reorder)
RegisterNetEvent('fridge:swapSlots', function(fridgeId, fromIndex, toIndex)
    local src = source
    ensureFridge(tostring(fridgeId))
    local fridge = fridges[tostring(fridgeId)]
    fromIndex = tonumber(fromIndex) or 0
    toIndex = tonumber(toIndex) or 0
    if fromIndex < 1 or toIndex < 1 then return end
    if fromIndex > #fridge.slots and toIndex > #fridge.slots then return end
    fridge.slots[fromIndex], fridge.slots[toIndex] = fridge.slots[toIndex], fridge.slots[fromIndex]
    saveFridges()
    TriggerClientEvent('fridge:updateClient', src, fridge)

    -- Audit
    metrics.swaps = metrics.swaps + 1
    auditLog(string.format('fridge %s swapped slots %d and %d', tostring(fridgeId), fromIndex, toIndex))
end)

-- Server event: store item into a specific slot index (drag store)
RegisterNetEvent('fridge:storeItemToSlot', function(fridgeId, slotIndex, itemName, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    amount = tonumber(amount) or 0
    slotIndex = tonumber(slotIndex) or 0
    if amount <= 0 or slotIndex < 1 then return TriggerClientEvent('QBCore:Notify', src, Config.Locale.invalid_request, 'error') end
    if not perishable[itemName] then return TriggerClientEvent('QBCore:Notify', src, Config.Locale.cannot_store, 'error') end
    if not Player.Functions.GetItemByName(itemName) then return TriggerClientEvent('QBCore:Notify', src, Config.Locale.no_item, 'error') end

    local removed = tryRemoveItem(Player, itemName, amount)
    if not removed then return TriggerClientEvent('QBCore:Notify', src, 'Failed to remove item', 'error') end

    ensureFridge(tostring(fridgeId))
    local fridge = fridges[tostring(fridgeId)]

    if slotIndex <= #fridge.slots and fridge.slots[slotIndex] ~= nil then
        local slot = fridge.slots[slotIndex]
        if slot.itemName == itemName then
            slot.amount = slot.amount + amount
            slot.storedAt = os.time()
        else
            table.insert(fridge.slots, slotIndex, { itemName = itemName, amount = amount, metadata = nil, storedAt = os.time() })
        end
    else
        if #fridge.slots >= maxSlots then
            Player.Functions.AddItem(itemName, amount)
            return TriggerClientEvent('QBCore:Notify', src, Config.Locale.fridge_full, 'error')
        end
        table.insert(fridge.slots, slotIndex, { itemName = itemName, amount = amount, metadata = nil, storedAt = os.time() })
    end

    while #fridge.slots > maxSlots do table.remove(fridge.slots) end

    saveFridges()
    TriggerClientEvent('QBCore:Notify', src, Config.Locale.stored..' '..amount..' '..itemName, 'success')
    TriggerClientEvent('fridge:updateClient', src, fridge)

    auditLog(string.format('%s drag-stored %d %s into fridge %s slot %d', Player.PlayerData.citizenid or tostring(src), amount, itemName, tostring(fridgeId), slotIndex))
end)

-- RPC to open stash/inventory for a fridge
QBCore.Functions.CreateCallback('fridge:openStash', function(source, cb, fridgeId)
    local ok = openStashForPlayer(source, fridgeId)
    cb(ok)
end)

-- RPC: return player's perishable items for client-side store menu
QBCore.Functions.CreateCallback('fridge:getPlayerPerishables', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    local items = {}
    for _, item in pairs(Player.PlayerData.items or {}) do
        if item and item.name and perishable[item.name] then
            table.insert(items, { name = item.name, amount = item.amount or item.count or 1, metadata = item.info or item.metadata or {} })
        end
    end
    cb(items)
end)

-- Maintenance: server-side handler to start maintenance (validates item and triggers client minigame)
RegisterNetEvent('fridge:startMaintenance', function(fridgeId, action)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    if not Config.Maintenance.Enabled then return TriggerClientEvent('QBCore:Notify', src, Config.Locale.maintenance_not_allowed, 'error') end

    -- optional job check
    if Config.Maintenance.Jobs and next(Config.Maintenance.Jobs) ~= nil then
        local jobname = Player.PlayerData.job and Player.PlayerData.job.name or ''
        local allowed = false
        for _, j in ipairs(Config.Maintenance.Jobs) do if j == jobname then allowed = true break end end
        if not allowed then return TriggerClientEvent('QBCore:Notify', src, Config.Locale.maintenance_not_allowed, 'error') end
    end

    local itemsMap = Config.Maintenance.Items
    local requiredItem = nil
    if action == 'deice' then requiredItem = itemsMap.deicing_kit
    elseif action == 'filter' then requiredItem = itemsMap.air_filter
    elseif action == 'waterfilter' then requiredItem = itemsMap.water_filter
    elseif action == 'refrigerant' then requiredItem = itemsMap.refrigerant_can
    elseif action == 'condenser' then requiredItem = itemsMap.condenser_patch
    elseif action == 'water' then requiredItem = itemsMap.water_connector
    elseif action == 'electrical' then requiredItem = itemsMap.electrical_kit
    else return end

    -- Check player has item
    if not Player.Functions.GetItemByName(requiredItem) then
        return TriggerClientEvent('QBCore:Notify', src, Config.Locale.maintenance_no_item, 'error')
    end

    -- Trigger client minigame; client will return result via 'fridge:maintenanceResult'
    TriggerClientEvent('fridge:runMaintenanceMinigame', src, fridgeId, action, Config.Maintenance.Minigame[action])
end)

-- Maintenance result listener: client sends success boolean
RegisterNetEvent('fridge:maintenanceResult', function(fridgeId, action, success)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    ensureFridge(tostring(fridgeId))
    local fridge = fridges[tostring(fridgeId)]
    local itemsMap = Config.Maintenance.Items
    local requiredItem = nil
    if action == 'deice' then requiredItem = itemsMap.deicing_kit
    elseif action == 'filter' then requiredItem = itemsMap.air_filter
    elseif action == 'waterfilter' then requiredItem = itemsMap.water_filter
    elseif action == 'refrigerant' then requiredItem = itemsMap.refrigerant_can
    elseif action == 'condenser' then requiredItem = itemsMap.condenser_patch
    elseif action == 'water' then requiredItem = itemsMap.water_connector
    elseif action == 'electrical' then requiredItem = itemsMap.electrical_kit
    else return end

    -- Consume item with some chance if failure
    local consumed = true
    if not success then
        local roll = math.random(1,100)
        consumed = roll <= Config.Maintenance.FailureConsume
    end

    if consumed then
        -- remove from player
        local removed = tryRemoveItem(Player, requiredItem, 1)
        if not removed then
            -- failed to consume (maybe race), notify and return
            return TriggerClientEvent('QBCore:Notify', src, 'Failed to use item', 'error')
        end
    end

    if not success then
        TriggerClientEvent('QBCore:Notify', src, Config.Locale.maintenance_failed, 'error')
        auditLog(string.format('%s failed maintenance %s on fridge %s (consumed=%s)', Player.PlayerData.citizenid or tostring(src), action, tostring(fridgeId), tostring(consumed)))
        return
    end

    -- Apply effects
    local effects = Config.Maintenance.Effects[action]
    if effects then
        for k,v in pairs(effects) do
            if k == 'water_hooked' then
                fridge.maintenance.water_hooked = v
            else
                fridge.maintenance[k] = v
            end
        end
    end
    fridge.maintenance.last_maintenance = os.time()
    saveFridges()

    TriggerClientEvent('QBCore:Notify', src, Config.Locale.maintenance_success, 'success')
    auditLog(string.format('%s performed maintenance %s on fridge %s', Player.PlayerData.citizenid or tostring(src), action, tostring(fridgeId)))
end)

-- Simple cleanup command (kept minimal; permissions not enforced per request)
QBCore.Commands.Add('fridgeclear', 'Clear all fridges (dev)', {{name='confirm', help='type yes'}}, false, function(source, args)
    if source == 0 then
        fridges = {}
        saveFridges()
        print('All fridges cleared')
    else
        TriggerClientEvent('QBCore:Notify', source, 'No permission', 'error')
    end
end)

-- Autosave and backup routines
Citizen.CreateThread(function()
    local autosave = Config.AutosaveInterval or 300000
    local backupInterval = Config.BackupInterval or (6 * 60 * 60 * 1000)
    local nextBackup = GetGameTimer() + backupInterval
    while true do
        Citizen.Wait(autosave)
        saveFridges()
        -- degrade fridge maintenance slowly each autosave
        for id, f in pairs(fridges) do
            if f and f.maintenance then
                -- simple degradation model
                f.maintenance.ice_level = math.min(100, (f.maintenance.ice_level or 0) + 1)
                f.maintenance.filter_condition = math.max(0, (f.maintenance.filter_condition or 100) - 0.2)
                f.maintenance.refrigerant_level = math.max(0, (f.maintenance.refrigerant_level or 100) - 0.05)
                f.maintenance.condenser_health = math.max(0, (f.maintenance.condenser_health or 100) - 0.01)
                f.maintenance.electrical_health = math.max(0, (f.maintenance.electrical_health or 100) - 0.005)
            end
        end
        -- backup if time
        if GetGameTimer() >= nextBackup then
            -- write backup file
            local ts = os.date('%Y%m%d%H%M%S')
            local fname = Config.BackupFilePrefix .. ts .. '.json'
            local encoded = json.encode(fridges)
            SaveResourceFile(GetCurrentResourceName(), fname, encoded, -1)
            metrics.backups = metrics.backups + 1
            auditLog('Backup saved: ' .. fname)
            nextBackup = GetGameTimer() + backupInterval
        end
    end
end)

-- Periodic autosave (defensive older timer kept)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000)
        saveFridges()
    end
end)

-- Admin/dev helper: give maintenance items to a player
QBCore.Commands.Add('givefridgemaint', 'Give fridge maintenance items (dev)', {{name='item', help='item name'}, {name='amount', help='amount', optional=true}}, false, function(source, args)
    local src = source
    local target = src
    local item = args[1]
    local amt = tonumber(args[2]) or 1
    if src == 0 then
        print('Server console: specify player id')
        return
    end
    local Player = QBCore.Functions.GetPlayer(target)
    if not Player then return end
    -- Add item via integration helpers (tryAddItem falls back)
    local added = tryAddItem(Player, item, amt)
    if added then
        TriggerClientEvent('QBCore:Notify', target, 'Given '..amt..' '..item, 'success')
    else
        TriggerClientEvent('QBCore:Notify', target, 'Failed to give item '..item, 'error')
    end
end)

-- Simple /giveitem admin command that supports QBCore and ox_inventory
QBCore.Commands.Add('giveitem', 'Give an item to player (admin)', {{name='item', help='item name'}, {name='amount', help='amount', optional=true}, {name='target', help='player id (optional)', optional=true}}, 'admin', function(source, args)
    local src = source
    local item = args[1]
    if not item or item == '' then
        if src == 0 then print('Usage: /giveitem item amount [playerId]') return end
        TriggerClientEvent('QBCore:Notify', src, 'Usage: /giveitem item amount [playerId]', 'error')
        return
    end
    local amt = tonumber(args[2]) or 1
    local targetId = tonumber(args[3]) or src
    if targetId == 0 then
        if src == 0 then print('Cannot give to console without specifying player id') end
        return
    end
    local Player = QBCore.Functions.GetPlayer(targetId)
    if not Player then
        if src == 0 then print('Player not found: '..tostring(targetId)) end
        return
    end
    local ok = tryAddItem(Player, item, amt)
    if ok then
        TriggerClientEvent('QBCore:Notify', targetId, 'Received '..amt..' x '..item, 'success')
        if src ~= targetId then TriggerClientEvent('QBCore:Notify', src, 'Gave '..amt..' x '..item..' to '..tostring(targetId), 'success') end
    else
        TriggerClientEvent('QBCore:Notify', src, 'Failed to give item', 'error')
    end
end)

-- Admin/dev helper: list maintenance config and fridge state
QBCore.Commands.Add('fridgestatus', 'Show fridge maintenance status (dev)', {}, false, function(source, args)
    if source == 0 then
        print('Maintenance Jobs:', json.encode(Config.Maintenance.Jobs))
        print('Maintenance Items:', json.encode(Config.Maintenance.Items))
        print('Number of fridges:', #fridges)
    else
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        TriggerClientEvent('QBCore:Notify', source, 'Maintenance Jobs: '..json.encode(Config.Maintenance.Jobs), 'primary')
        TriggerClientEvent('QBCore:Notify', source, 'Maintenance Items: '..json.encode(Config.Maintenance.Items), 'primary')
    end
end)

-- Small helper command to give all sample items (dev)
QBCore.Commands.Add('giveallfridgitems', 'Give all maintenance items', {}, false, function(source, args)
    local src = source
    if src == 0 then print('Console cannot receive items') return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    for k,v in pairs(Config.Maintenance.Items) do
        tryAddItem(Player, v, 1)
    end
    TriggerClientEvent('QBCore:Notify', src, 'Given maintenance items', 'success')
end)

