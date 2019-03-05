data:extend{
    {
        type = "recipe",
        name = "time-series",
        enabled = "true",
        ingredients = {
            {"electronic-circuit", 5},
            {"copper-cable", 5},
        },
        result = "time-series",
    },
    {
        type = "recipe",
        name = "time-series-rate",
        enabled = "true",
        ingredients = {
            {"electronic-circuit", 5},
            {"copper-cable", 5},
        },
        result = "time-series-rate",
    },
    {
        type = "item",
        name = "time-series",
        icon = "__base__/graphics/icons/computer.png",
        icon_size = 32,
        subgroup = "circuit-network",
        order = "d[other]-c[time-series]",
        place_result = "time-series",
        stack_size = 10
    },
    {
        type = "item",
        name = "time-series-rate",
        icon = "__base__/graphics/icons/computer.png",
        icon_size = 32,
        subgroup = "circuit-network",
        order = "d[other]-d[time-series-rate]",
        place_result = "time-series-rate",
        stack_size = 10
    },
    {
        type = "technology",
        name = "time-series",
        icon_size = 128,
        icon = "__base__/graphics/technology/circuit-network.png",
        effects = {
            {
                type = "unlock-recipe",
                recipe = "time-series"
            },
            {
                type = "unlock-recipe",
                recipe = "time-series-rate"
            }
        },
        prerequisites = {"circuit-network"},
        unit = {
            count = 100,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1}
            },
            time = 15
        },
        order = "a-d-e"
    }
}

local time_series_entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])

time_series_entity.name = "time-series"
time_series_entity.icon = "__base__/graphics/icons/computer.png"
time_series_entity.item_slot_count = 0

local time_series_rate_entity = table.deepcopy(time_series_entity)
time_series_rate_entity.name = "time-series-rate"

data:extend{time_series_entity, time_series_rate_entity}
