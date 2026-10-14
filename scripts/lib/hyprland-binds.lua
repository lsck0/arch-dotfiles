-- runs a hyprland keybindings file against a recording hl and prints each bind as submap, keys and description,
-- tab separated; the loops and helpers in the file run for real, so the list is what hyprland gets
local path = assert(arg[1], "usage: lua hyprland-binds.lua <hyprland_keybindings.lua>")

-- any dispatcher or helper the file reaches for: indexable and callable to any depth
local function stub()
    return setmetatable({}, {
        __index = function()
            return stub()
        end,
        __call = function()
            return stub()
        end,
    })
end

local submap = ""

hl = setmetatable({
    dsp = stub(),
    bind = function(keys, _, opts)
        local description = (opts and (opts.description or opts.desc)) or ""
        io.write(submap, "\t", keys, "\t", description, "\n")
    end,
    define_submap = function(name, binds)
        local outer = submap
        submap = name
        binds()
        submap = outer
    end,
}, {
    __index = function()
        return stub()
    end,
})

dofile(path)
