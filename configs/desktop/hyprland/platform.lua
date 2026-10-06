-- form factor from platforms/<host>.sh, written by scripts/lib/platform.sh during config.sh; no second detection here
local FORM_FACTORS = {
    desktop = true,
    laptop = true,
    vm = true,
}

local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local path = config_home .. "/dotfiles/form-factor"

local f = io.open(path, "r")
local form_factor = f and f:read("l")
if f then f:close() end

if not FORM_FACTORS[form_factor] then
    error("platform: " .. path .. " holds '" .. tostring(form_factor) .. "', not desktop, laptop or vm; run config.sh")
end

local M = {}

M.form_factor = form_factor
M.laptop = form_factor == "laptop"

return M
