-- SMBIOS chassis types that mean "portable", used when the hostname is not one
-- of the known ones below
local DMI_PORTABLE = {
    [8] = true,  -- portable
    [9] = true,  -- laptop
    [10] = true, -- notebook
    [11] = true, -- hand held
    [14] = true, -- sub notebook
    [30] = true, -- tablet
    [31] = true, -- convertible
    [32] = true, -- detachable
}

local PROFILES = {
    ["luca-pc"] = "desktop",
    ["luca-notebook"] = "laptop",
}

local function first_line(path)
    local f = io.open(path, "r")
    if not f then return nil end

    local line = f:read("l")
    f:close()

    if not line or line == "" then return nil end
    return line
end

local host = first_line("/etc/hostname") or os.getenv("HOSTNAME") or "unknown"
local portable = DMI_PORTABLE[tonumber(first_line("/sys/class/dmi/id/chassis_type") or "")] == true

local M = {}

M.host = host
M.profile = PROFILES[host] or (portable and "laptop" or "desktop")
M.laptop = M.profile == "laptop"
M.desktop = not M.laptop

return M
