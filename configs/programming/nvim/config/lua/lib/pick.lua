local M = {}

---@param title string
---@param items { display: string, value: any }[]
---@param on_select fun(value: any?, query: string)
function M.telescope(title, items, on_select)
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
            attach_mappings = function(bufnr)
                actions.select_default:replace(function()
                    local entry = state.get_selected_entry()
                    local query = state.get_current_line()
                    actions.close(bufnr)
                    on_select(entry and entry.value, query)
                end)
                return true
            end,
        })
        :find()
end

return M
