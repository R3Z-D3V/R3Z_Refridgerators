Config = {}
-- Inventory integration toggles
Config.EnableOxInventory = false --- set to true to enable ox-inventory support
Config.EnableQbInventory = false --- set to true to enable qb-inventory support
-- When opening a fridge we can open an inventory stash. Set stash provider preference: 'ox'|'qb'|'none'
Config.StashProvider = 'ox' -- change to 'qb' or 'none' to control which inventory system to open as a stash
Config.TargetDistance = 2.5 -- Distance for target interaction
Config.UseOxmysql = true -- use oxmysql if available; falls back to json file if not

-- Models for fridges to add ox_target interactions
Config.FridgeModels = {
    -- common fridge/refrigerator models
    'prop_fridge_01',
    'prop_fridge_02',
    'prop_fridge_03',
    'v_ilev_fridge01',
    'prop_fridge_03_l1',
    'prop_fridge_01_l1'
}


-- How much slower decay is inside fridge (0 < factor <= 1). 0.2 = 5x slower
Config.DecayFactor = 0.2

-- Which item names should be considered perishable (simple example)
Config.PerishableItems = {
    ['water_bottle'] = true,
    ['sandwich'] = true,
    ['toastie'] = true,
    ['apple'] = true,
    ['milk'] = true
}

-- Storage Settings
Config.MaxSlots = 30
Config.StashPrefix = 'fridge_' -- Optional prefix for stash names (storage keys)
Config.MaxStorePerAction = 50 -- max items stored per action

-- Persistence settings
Config.AutosaveInterval = 5 * 60 * 1000 -- 5 minutes Autosave interval
Config.BackupInterval = 6 * 60 * 60 * 1000 -- 6 hours Backup interval
Config.BackupFilePrefix = 'fridges_backup_' -- Where backups are saved (resource writeable path)

-- logging/webhook
Config.EnableAuditWebhook = false
Config.AuditWebhookURL = '' -- paste your webhook URL here
Config.EnableAuditFileLog = true
Config.AuditLogFile = 'fridge_audit.log'
Config.StorageFile = 'fridges.json' -- Filename for persistent storage (fallback when no DB)

-- Localization (strings can be extended)
    Config.Locale = {
        invalid_amount = 'Invalid amount',
        cannot_store = 'This item cannot be stored',
        no_item = 'You do not have that item',
        fridge_full = 'Fridge is full',
        stored = 'Stored',
        retrieved = 'Retrieved',
        invalid_request = 'Invalid request',
        maintenance_not_allowed = 'You cannot perform maintenance',
        maintenance_no_item = 'You lack the required item',
        maintenance_failed = 'Maintenance failed',
        maintenance_success = 'Maintenance successful',

        -- Maintenance UI / feedback
        maintenance_menu_title = 'Fridge Maintenance',
        maintenance_action_deice = 'De-ice Fridge',
        maintenance_action_filter = 'Replace Air Filter',
        maintenance_action_waterfilter = 'Replace Water Filter',
        maintenance_action_refrigerant = 'Replace Refrigerant',
        maintenance_action_condenser = 'Repair Condenser',
        maintenance_action_water = 'Hook Water Line',
        maintenance_action_electrical = 'Perform Electrical Repair',

        maintenance_starting = 'Starting maintenance: %s',
        maintenance_need_item = 'You need a %s to do that',
        maintenance_using_item = 'Using %s...',
        maintenance_success_detail = 'Maintenance completed: %s',
        maintenance_fail_detail = 'Maintenance failed: %s'
    }

    -- Maintenance config (items, degradation, minigame settings)
    Config.Maintenance = {
        Enabled = true,
        -- Optional: restrict to job names, empty = all players
        Jobs = {},

        -- Item names (change to match your economy)
        Items = {
            deicing_kit = 'deicing_kit',
            water_filter = 'water_filter',
            air_filter = 'air_filter',
            refrigerant_can = 'refrigerant_can',
            condenser_patch = 'condenser_patch',
            water_connector = 'water_connector',
            electrical_kit = 'electrical_kit'
        },

        -- Minigame settings (ox_lib.skillCheck difficulties)
        Minigame = {
            deice = { difficulties = {'easy','easy','medium'} },
            filter = { difficulties = {'easy','medium'} },
            refrigerant = { difficulties = {'medium','hard'} },
            condenser = { difficulties = {'medium','hard','hard'} },
            water = { difficulties = {'easy'} },
            electrical = { difficulties = {'medium','hard'} }
        },

        -- Effects: how much each action restores (0-100)
        Effects = {
            deice = { ice_level = -60 }, -- reduces ice by 60
            filter = { filter_condition = 100 }, -- set filter to 100
            refrigerant = { refrigerant_level = 100 },
            condenser = { condenser_health = 100 },
            water = { water_hooked = true },
            electrical = { electrical_health = 100 }
        },

        -- Failure penalties (percent chance to consume item without effect)
        FailureConsume = 80 -- percent chance item is consumed on failure
    }
   
