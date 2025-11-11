-- QBCore item definitions for fridge maintenance items
-- Place this in your QBCore shared items (or require/import it)
return {
    ['deicing_kit'] = {
        name = 'deicing_kit',
        label = 'De-icing Kit',
        weight = 100,
        type = 'item',
        image = 'deicing_kit.png',
        unique = false,
        useable = true,
        shouldClose = true,
        combinable = nil,
        description = 'Used to remove ice buildup from fridges.'
    },

    ['water_filter'] = {
        name = 'water_filter',
        label = 'Water Filter',
        weight = 150,
        type = 'item',
        image = 'water_filter.png',
        unique = false,
        useable = true,
        shouldClose = true,
        combinable = nil,
        description = 'Replacement water filter for fridge water lines.'
    },

    ['air_filter'] = {
        name = 'air_filter',
        label = 'Air Filter',
        weight = 120,
        type = 'item',
        image = 'air_filter.png',
        unique = false,
        useable = true,
        shouldClose = true,
        combinable = nil,
        description = 'Replacement air filter for fridge airflow.'
    },

    ['refrigerant_can'] = {
        name = 'refrigerant_can',
        label = 'Refrigerant Can',
        weight = 400,
        type = 'item',
        image = 'refrigerant_can.png',
        unique = false,
        useable = true,
        shouldClose = true,
        combinable = nil,
        description = 'Used to top up refrigerant in the cooling system.'
    },

    ['condenser_patch'] = {
        name = 'condenser_patch',
        label = 'Condenser Patch Kit',
        weight = 250,
        type = 'item',
        image = 'condenser_patch.png',
        unique = false,
        useable = true,
        shouldClose = true,
        combinable = nil,
        description = 'Repair kit for condenser components.'
    },

    ['water_connector'] = {
        name = 'water_connector',
        label = 'Water Line Connector',
        weight = 80,
        type = 'item',
        image = 'water_connector.png',
        unique = false,
        useable = true,
        shouldClose = true,
        combinable = nil,
        description = 'Used to hook up or repair fridge water lines.'
    },

    ['electrical_kit'] = {
        name = 'electrical_kit',
        label = 'Electrical Repair Kit',
        weight = 300,
        type = 'item',
        image = 'electrical_kit.png',
        unique = false,
        useable = true,
        shouldClose = true,
        combinable = nil,
        description = 'Basic electrical repair kit for fridge wiring and components.'
    }
}
