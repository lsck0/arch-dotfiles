-- programming/nvim's options as its mod.nu renders them; the file exists only once one differs from its default
local DEFAULTS = { spell_languages = { "en" }, dictation_language = "en" }

local options = vim.deepcopy(DEFAULTS)
local f = io.open(vim.fn.stdpath("data") .. "/dot-options.json")
if f then
    local ok, read = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(read) == "table" then
        for key, value in pairs(read) do
            if type(value) == type(DEFAULTS[key]) then
                options[key] = value
            end
        end
    end
end
return options
