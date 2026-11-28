local M = {}

---@param title string
---@param items { display: string, value: any }[]
---@param on_select fun(value: any?)
---@param on_query? { key: string, fn: fun(query: string) } a prompt key acting on the typed text, never the match
function M.telescope(title, items, on_select, on_query)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local state = require("telescope.actions.state")

    pickers
        .new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = items,
                entry_maker = function(item)
                    return { value = item.value, display = item.display, ordinal = item.display }
                end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(bufnr, map)
                actions.select_default:replace(function()
                    local entry = state.get_selected_entry()
                    actions.close(bufnr)
                    on_select(entry and entry.value)
                end)
                if on_query then
                    map({ "i", "n" }, on_query.key, function()
                        local query = vim.trim(state.get_current_line())
                        actions.close(bufnr)
                        on_query.fn(query)
                    end)
                end
                return true
            end,
        })
        :find()
end

return M
