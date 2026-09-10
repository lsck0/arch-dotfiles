-- Theme dispatch. Each file under lua/themes/ is one wallpaper theme's
-- entry point: it does whatever is needed to make nvim render that theme
-- (almost always just `vim.cmd("colorscheme ...")`, but living in its own
-- file means a theme that ever needs extra setup — a flavour option, a
-- background=dark/light toggle — has an obvious place to put it that isn't
-- a shared case statement).
--
-- switch-wallpaper.sh writes a bare THEME NAME (not a vim command) to
-- ~/.cache/wal/nvim_theme:
--   - a THEME wallpaper -> the theme's own name, e.g. "ayu-dark" ->
--     lua/themes/ayu-dark.lua
--   - a PHOTO wallpaper -> "pywal" -> lua/themes/pywal.lua
-- M.apply(name) is called both at startup (below) and by the live
-- `nvim --server ... --remote-send` nudge switch-wallpaper.sh sends on
-- every wallpaper change, so both paths run the exact same code and can
-- never drift out of sync with each other.
--
-- Unknown/missing name falls back to pywal, same as a missing/empty marker
-- file — a fresh install or a theme name typo still gets working colors
-- rather than an error.

local M = {}

local MARKER = vim.env.HOME .. "/.cache/wal/nvim_theme"

M.current = "pywal"

function M.apply(name)
  name = name and name ~= "" and name or "pywal"
  local ok, err = pcall(function() require("themes." .. name).apply() end)
  if ok then
    M.current = name
    return
  end
  -- Do NOT swallow the error silently: a theme plugin failing to load and
  -- falling back to pywal with zero indication why is exactly what made a
  -- stale-nvim / broken-plugin-spec bug (the dracula.nvim "cmd=colorscheme"
  -- crash) look like "nothing works" instead of a clear, fixable error.
  vim.schedule(function()
    vim.notify(
      "theme: failed to apply '" .. name .. "', falling back to pywal\n" .. tostring(err),
      vim.log.levels.WARN
    )
  end)
  M.current = "pywal"
  pcall(function() require("themes.pywal").apply() end)
end

function M.apply_from_marker()
  local f = io.open(MARKER, "r")
  if not f then
    M.apply(nil)
    return
  end
  local name = f:read("*l")
  f:close()
  M.apply(name and name:gsub("%s+$", "") or nil)
end

return M
