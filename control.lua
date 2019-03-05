-- ticks = number of ticks represented by each datapoint
-- steps = number of datapoints from this interval which correspond to
--         one datapoint in the next interval
-- length = number of datapoints in this interval
local interval_defs = {
    {name=   "5s", caption={"time-symbol-seconds-short",  5}, ticks =      1, steps=  6, length=300},
    {name=   "1m", caption={"time-symbol-minutes-short",  1}, ticks =      6, steps= 10, length=600},
    {name=  "10m", caption={"time-symbol-minutes-short", 10}, ticks =     60, steps=  6, length=600},
    {name=   "1h", caption={"time-symbol-hours-short",    1}, ticks =    360, steps= 10, length=600},
    {name=  "10h", caption={"time-symbol-hours-short",   10}, ticks =   3600, steps=  5, length=600},
    {name=  "50h", caption={"time-symbol-hours-short",   50}, ticks =  18000, steps=  5, length=600},
    {name= "250h", caption={"time-symbol-hours-short",  250}, ticks =  90000, steps=  4, length=600},
    {name="1000h", caption={"time-symbol-hours-short", 1000}, ticks = 360000, steps=nil, length=600},
}

local interval_map = {
    ["5s"] = 1,
    ["1m"] = 2,
    ["10m"] = 3,
    ["1h"] = 4,
    ["10h"] = 5,
    ["50h"] = 6,
    ["250h"] = 7,
    ["1000h"] = 8,
}

local ENTITY_NAMES = {
    ["time-series"] = true,
    ["time-series-rate"] = true,
}

local VIEWPORT_WIDTH = 1000
local VIEWPORT_HEIGHT = 500

local function new_registry_entry(entity)
    local intervals = {}
    for i, def in ipairs(interval_defs) do
        local data = {}
        -- Don't actually need to prepopulate this.
        --for j = 1, def.length do
        --    data[j] = {}
        --end
        intervals[i] = {
            name = def.name,
            caption = def.caption,
            data = data,
            index = 0,
            sum = {},
            counts = {},
            ticks = def.ticks,
            steps = def.steps,
            length = def.length,
            viewer_count = 0,
            guis = {},
            chunk = nil,
            last_rendered_tick = nil,
        }
    end
    return {
        type="gauge",
        entity=entity,
        intervals=intervals,
    }
end

local function new_registry_entry_counter(entity)
    local entry = new_registry_entry(entity)
    entry.type = "rate"
    entry.counters = {}
    entry.counter_index = 0
    -- 10s moving average.
    entry.counter_length = 600
    return entry
end

-- taken from data/core/prototypes/style.lua:5724
local colors = {
    {r = 0.22, g = 0.41, b = 0.69},
    {r = 0.85, g = 0.48, b = 0.18},
    {r = 0.24, g = 0.58, b = 0.31},
    {r = 0.8, g = 0.1, b = 0.16},
    {r = 0.553, g = 0.365, b = 0.675},
    {r = 0.87, g = 0.72, b = 0},
    {r = 0, g = 0.667, b = 0.7},
    {r = 0.47, g = 0.47, b = 0.47},
    {r = 0.816, g = 0.533, b = 0.72},
    {r = 0.565, g = 0.33, b = 0.22},
    {r = 0.49, g = 0.7, b = 0},
    {r = 0.58, g = 0.69, b = 0.898},
    {r = 0.937, g = 0.714, b = 0.604},
    {r = 0.518, g = 0.753, b = 0.592},
    {r = 1, g = 0.57, b = 0.565},
    {r = 0.78, g = 0.682, b = 0.87},
    {r = 0.945, g = 0.86, b = 0.467},
    {r = 0.514, g = 0.843, b = 0.81},
    {r = 0.733, g = 0.733, b = 0.733},
    {r = 0.906, g = 0.733, b = 0.84},
    {r = 0.67, g = 0.855, b = 0.486},
    {r = 0.72, g = 0.604, b = 0.553},
}

local MAX_LINES = #colors

-- Assume gui.legend has already been cleared.
local function render_gui(interval, gui, datasets, ordered_sums, min_y, max_y)
    local split = math.ceil(datasets / 2)
    local columns = {
        {start = 1, stop = split},
        {start = split + 1, stop = datasets},
    }
    for col, range in ipairs(columns) do
        local table = gui.legend.add{
            type = "table",
            name = "table" .. col,
            column_count = 3,
        }
        table.style.column_alignments[1] = "left"
        table.style.column_alignments[2] = "center"
        table.style.column_alignments[3] = "right"
        for i = range.start, range.stop do
            local row = ordered_sums[i]
            local value = row.sum / interval.length
            local ratio = (value - min_y) / (max_y - min_y)
            table.add{
                type = "sprite",
                name = "sprite" .. i,
                sprite = row.name,
            }
            local bar = table.add{
                type = "progressbar",
                name = "bar" .. i,
                value = ratio,
            }
            local caption = string.format("%.2f", value)
            if gui.entry.type == "rate" then
                caption = caption .. "/s"
            end
            table.add{
                type = "label",
                name = "label" .. i,
                caption = caption,
            }
            if i <= MAX_LINES then
                bar.style.color = colors[i]
            else
                bar.style.color = {r = 0, g = 0, b = 0}
            end
        end
    end
end

local function render_interval(interval)
    for player_index, gui in pairs(interval.guis) do
        gui.legend.clear()
    end
    local surface = global.surface
    local ttl = interval.ticks + 1
    local entity = interval.chunk.render_entity
    local dx = VIEWPORT_WIDTH / (interval.length - 1) / 32
    local x = -0.5
    -- The number of distinct signals stored in the interval.
    local datasets = 0
    local ordered_sums = {}
    for name, count in pairs(interval.counts) do
        datasets = datasets + 1
        ordered_sums[datasets] = {name = name, sum = interval.sum[name]}
    end
    local to_draw = datasets
    if to_draw > MAX_LINES then
        to_draw = MAX_LINES
    end
    if to_draw == 0 then
        return
    end
    table.sort(ordered_sums, function(a, b)
        if a.sum ~= b.sum then
            -- sort in reverse
            return a.sum > b.sum
        else
            return a.name < b.name
        end
    end)
    -- XXX: There are more efficient ways of computing min and max (e.g. using
    -- a deque), but this will do for now.
    local min_y = 0
    local max_y = 0
    for i = 1, interval.length do
        local datum = interval.data[i]
        if datum ~= nil then
            for j = 1, to_draw do
                local name = ordered_sums[j].name
                local val = datum[name] or 0
                if val < min_y then
                    min_y = val
                end
                if val > max_y then
                    max_y = val
                end
            end
        end
    end
    if min_y == 0 and max_y == 0 then
        return
    end
    for player_index, gui in pairs(interval.guis) do
        render_gui(interval, gui, datasets, ordered_sums, min_y, max_y)
    end
    -- Avoid double-rendering when an entity is opened on the same tick that
    -- we would perform a regular update. (For the 5s interval, this is every
    -- tick.)
    if interval.last_rendered_tick == game.tick then
        return
    end
    interval.last_rendered_tick = game.tick
    local y_offset = (VIEWPORT_HEIGHT - 1) / 32 + 1.5 - min_y -- - 1/32
    local dy = (VIEWPORT_HEIGHT - 1) / (max_y - min_y) / 32
    local prev = {}
    local first = interval.data[interval.index + 1] or {}
    for j = 1, to_draw do
        local name = ordered_sums[j].name
        local n = first[name] or 0
        local y = y_offset - (n * dy)
        prev[name] = {x, y}
    end
    local ranges = {
        {start = interval.index + 2, stop = interval.length},
        {start = 1, stop = interval.index},
    }
    for _, range in ipairs(ranges) do
        for i = range.start, range.stop do
            local datum = interval.data[i] or {}
            local next_points = {}
            for j = to_draw, 1, -1 do
                local name = ordered_sums[j].name
                local point = prev[name]
                local n = datum[name] or 0
                local y = y_offset - (n * dy)
                local to = {x, y}
                next_points[name] = to
                rendering.draw_line{
                    surface = surface,
                    color = colors[j],
                    width = 0.5,
                    from = entity,
                    from_offset = prev[name],
                    to = entity,
                    to_offset = to,
                    time_to_live = ttl,
                }
            end
            prev = next_points
            x = x + dx
        end
    end
end

local function add_datapoint(intervals, value)
    for interval_index, interval in ipairs(intervals) do
        local index = interval.index
        local steps = interval.steps
        -- Remove the oldest value from sum and counts.
        for k, v in pairs(interval.data[index+1] or {}) do
            interval.counts[k] = interval.counts[k] - 1
            if interval.counts[k] == 0 then
                interval.sum[k] = nil
                interval.counts[k] = nil
            else
                interval.sum[k] = interval.sum[k] - v
            end
        end
        -- Insert the new value.
        interval.data[index+1] = value
        -- Update sum and counts.
        for k, v in pairs(value) do
            interval.sum[k] = (interval.sum[k] or 0) + v
            interval.counts[k] = (interval.counts[k] or 0) + 1
        end
        -- Advance the index.
        interval.index = (index + 1) % interval.length
        -- Render if being viewed.
        if interval.viewer_count > 0 then
            render_interval(interval)
        end
        if steps ~= nil and interval.index % steps == 0 then
            -- compute consolidation to move into next interval
            index = (interval.index - steps) % interval.length
            local value = {}
            for i = 1, steps do
                -- no modulus here; these spans will never wrap around
                local datum = interval.data[index+i]
                for k, v in pairs(datum) do
                    value[k] = (value[k] or 0) + v
                end
            end
            for k, v in pairs(value) do
                value[k] = v / steps
            end
        else
            break
        end
    end
end

-- 2^50, more than enough to store the sum of 600 int32s.
local MAX_COUNTER = 1125899906842624

local function add_counter_datapoint(entry, value)
    local counters = entry.counters
    local index = entry.counter_index
    local prev_index = index
    if prev_index == 0 then
        prev_index = entry.counter_length
    end
    local prev = counters[prev_index] or {}
    local current = {}
    for k, v in pairs(prev) do
        current[k] = v
    end
    for k, v in pairs(value) do
        -- Ignore negative values; this counter is monotonic.
        if v >= 0 then
            local sum = (current[k] or 0) + v
            if sum > MAX_COUNTER then
                sum = sum - MAX_COUNTER
            end
            current[k] = sum
        end
    end
    -- Insert the new value.
    counters[index+1] = current
    -- Advance the index.
    entry.counter_index = (index + 1) % entry.counter_length
    -- Compute 10 second moving average rate.
    local rate = {}
    local oldest_value = counters[entry.counter_index + 1] or {}
    for k, v in pairs(current) do
        local old = oldest_value[k] or 0
        local delta = v - old
        if delta < 0 then
            delta = delta + MAX_COUNTER
        end
        rate[k] = delta / 10  -- convert per-10-second rate to per-second
    end
    add_datapoint(entry.intervals, rate)
end

--interval = {
--    name = "5s",
--    data = {...},
--    index = 0,
--    sum = {},
--    counts = {},
--    steps = 6,
--    length = 300,
--    viewer_count = 0,
--    guis = {[player_index] = gui},
--    chunk = {render_entity = LuaEntity, coord = {x=x, y=y}} or nil,
--    last_rendered_tick = nil,
--}
-- index is of next datapoint to replace; that is, it points to the "oldest"
-- datapoint. index is 0-indexed; it is corrected to 1-indexing upon use.

--global.registry = {
--    [entity_number] = {
--        type="gauge" or "rate"
--        entity=LuaEntity,
--        intervals={interval...},
--        -- these are used for type="rate"
--        counters={...},
--        counter_index=0,
--        counter_length-600,
--    }
--}

--global.gui = {
--    [player_index] = {
--        element=LuaGuiElement,
--        entry=entry,
--        legend=LuaGuiElement,
--        camera=LuaGuiElement,
--        interval_index=1,
--    }
--}

local function on_tick(event)
    for entity_number, entry in pairs(global.registry) do
        local entity = entry.entity
        local signals = entity.get_merged_signals()
        local value = {}
        if signals then
            for _, signal in ipairs(signals) do
                value[signal.signal.type .. "/" .. signal.signal.name] = signal.count
            end
        end
        if entry.type == "rate" then
            add_counter_datapoint(entry, value)
        else
            add_datapoint(entry.intervals, value)
        end
    end
end

local function on_place_entity(event)
    local entity = event.created_entity
    if not entity.valid or not ENTITY_NAMES[entity.name] then
        return
    end

    entity.get_control_behavior().enabled = false
    local entry
    if entity.name == "time-series" then
        entry = new_registry_entry(entity)
    else
        entry = new_registry_entry_counter(entity)
    end
    global.registry[entity.unit_number] = entry
end

local function on_remove_entity(event)
    local entity = event.entity
    if not entity.valid or not ENTITY_NAMES[entity.name] then
        return
    end

    global.registry[entity.unit_number] = nil
end

script.on_init(function()
    global.registry = {}
    global.gui = {}
    -- List of unused graph-rendering chunks.
    global.chunk_freelist = {}
    -- Next chunk coordinate to assign.
    global.next_chunk_x = 0
    global.next_chunk_y = 0
    global.surface = game.create_surface("timeseries_surface", {width = 2, height = 2})
    global.surface.daytime = 0.5
    global.surface.freeze_daytime = true
    global.data_version = 1
end)

script.on_event(defines.events.on_built_entity, on_place_entity)
script.on_event(defines.events.on_robot_built_entity, on_place_entity)

script.on_event(defines.events.on_pre_player_mined_item, on_remove_entity)
script.on_event(defines.events.on_robot_pre_mined, on_remove_entity)
script.on_event(defines.events.on_entity_died, on_remove_entity)

script.on_event(defines.events.on_tick, on_tick)

-- We assign chunks in a pattern like:
--  1 2 4 7
--  3 5 8
--  6 9
-- 10
-- This allows is to fill the plane with a minimum of coordinate-wrangling.
-- (In practice we will rarely need more than one chunk.)

local function get_chunk()
    local chunk_coord
    local length = #global.chunk_freelist
    if length > 0 then
        chunk_coord = global.chunk_freelist[length]
        global.chunk_freelist[length] = nil
    else
        chunk_coord = {
            x = global.next_chunk_x * 32,
            y = global.next_chunk_y * 32
        }
        --[[local s = string.format("(%d, %d)", global.next_chunk_x, global.next_chunk_y)
        rendering.draw_text{
            text = s,
            surface = global.surface,
            target = {x = chunk_coord.x, y = chunk_coord.y + 2},
            color = {r = 1, g = 1, b = 1},
        }]]
        if global.next_chunk_x == 0 then
            global.next_chunk_x = global.next_chunk_y + 1
            global.next_chunk_y = 0
        else
            global.next_chunk_x = global.next_chunk_x - 1
            global.next_chunk_y = global.next_chunk_y + 1
        end
        local tiles = {}
        local i = 1
        local tile_name = "lab-dark-1"
        --local tile_name = "tutorial-grid"
        for x = chunk_coord.x, chunk_coord.x + 31 do
            for y = chunk_coord.y, chunk_coord.y + 31 do
                tiles[i] = {name = tile_name, position = {x = x, y = y}}
                i = i + 1
            end
        end
        global.surface.set_tiles(tiles)
    end
    local render_entity = global.surface.create_entity{
        name = "pipe",
        position = chunk_coord,
    }
    return {render_entity = render_entity, coord = chunk_coord}
end

local function free_chunk(chunk)
    chunk.render_entity.destroy()
    table.insert(global.chunk_freelist, chunk.coord)
end

local function interval_register_gui(interval, player, gui)
    interval.guis[player.index] = gui
    interval.viewer_count = interval.viewer_count + 1

    if interval.chunk then
        return interval.chunk
    end
    local chunk = get_chunk()
    interval.chunk = chunk
    --[[rendering.draw_text{
        text = interval.name,
        surface = global.surface,
        target = chunk.render_entity,
        target_offset = {0, 3},
        color = {r = 1, g = 0, b = 0},
    }]]
    return chunk
end

local function interval_unregister_gui(interval, player)
    interval.guis[player.index] = nil
    interval.viewer_count = interval.viewer_count - 1
    if interval.viewer_count == 0 then
        local chunk = interval.chunk
        interval.chunk = nil
        free_chunk(chunk)
    end
end

script.on_event(defines.events.on_gui_opened, function(event)
    local entity = event.entity
    if event.gui_type ~= defines.gui_type.entity or not entity or not ENTITY_NAMES[entity.name] then
        return
    end

    local entry = global.registry[entity.unit_number]
    local player = game.players[event.player_index]

    local caption
    if entry.type == "rate" then
        caption = {"entity-name.time-series-rate"}
    else
        caption = {"entity-name.time-series"}
    end
    local frame = player.gui.center.add{
        type = "frame",
        name = "time_series",
        caption = caption,
        direction = "vertical",
    }

    local interval_index = 1
    local gui = {
        element = frame,
        entry = entry,
        interval_index = interval_index,
    }

    local button_flow = frame.add{
        type = "flow",
        name = "buttons",
        direction = "horizontal",
    }
    gui.buttons = button_flow
    local intervals = global.registry[entity.unit_number]
    for i, interval in ipairs(interval_defs) do
        button_flow.add{
            type = "button",
            name = interval.name,
            caption = interval.caption,
            enabled = i ~= interval_index,
        }
    end

    local scroll = frame.add{
        type = "scroll-pane",
        name = "scroll",
    }
    local legend = scroll.add{
        type = "flow",
        name = "legend",
        direction = "horizontal"
    }
    gui.legend = legend

    local interval = entry.intervals[interval_index]
    local chunk = interval_register_gui(interval, player, gui)
    local camera_position = {
        x = chunk.coord.x + VIEWPORT_WIDTH/2/32,
        y = chunk.coord.y + VIEWPORT_HEIGHT/2/32 + 2,
    }
    local camera = frame.add{
        type = "camera",
        name = "graph",
        position = camera_position,
        surface_index = global.surface.index,
        zoom = player.display_scale,
    }
    camera.style.width = VIEWPORT_WIDTH
    camera.style.height = VIEWPORT_HEIGHT
    gui.camera = camera

    player.opened = frame

    global.gui[player.index] = gui
    
    render_interval(interval)
    --game.print("opened gui, viewer count = " .. interval.viewer_count)
end)

script.on_event(defines.events.on_gui_closed, function(event)
    local frame = event.element
    if event.gui_type ~= defines.gui_type.custom or not frame or not frame.valid or frame.name ~= "time_series" then
        return
    end
    local player = game.players[event.player_index]
    local gui = global.gui[player.index]
    local entry = gui.entry
    local interval = entry.intervals[gui.interval_index]
    interval_unregister_gui(interval, player)
    global.gui[player.index] = nil
    frame.destroy()
    --game.print("closed gui, viewer count = " .. interval.viewer_count)
end)

script.on_event(defines.events.on_gui_click, function(event)
    local gui = global.gui[event.player_index]
    if gui == nil or event.element.parent ~= gui.element.buttons then
        return
    end
    local new_index = interval_map[event.element.name]
    if new_index == gui.interval_index then
        return
    end
    local player = game.players[event.player_index]
    local entry = gui.entry
    local interval = entry.intervals[gui.interval_index]
    interval_unregister_gui(interval, player)

    gui.buttons.children[gui.interval_index].enabled = true
    gui.buttons.children[new_index].enabled = false
    gui.interval_index = new_index
    interval = entry.intervals[new_index]
    local chunk = interval_register_gui(interval, player, gui)
    local camera_position = {
        x = chunk.coord.x + VIEWPORT_WIDTH/2/32,
        y = chunk.coord.y + VIEWPORT_HEIGHT/2/32 + 2,
    }
    gui.camera.position = camera_position

    render_interval(interval)

    --game.print("pressed " .. event.element.name)
end)
