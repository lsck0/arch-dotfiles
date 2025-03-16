return {
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "theHamsta/nvim-dap-virtual-text",
        },
        config = function()
            require("nvim-dap-virtual-text").setup()
            local dap, dapui = require("dap"), require("dapui")

            dapui.setup({
                layouts = { {
                    elements = { {
                        id = "breakpoints",
                        size = 0.25
                    }, {
                        id = "scopes",
                        size = 0.50
                    }, {
                        id = "watches",
                        size = 0.25
                    } },
                    position = "left",
                    size = 40
                }, {
                    elements = { {
                        id = "repl",
                        size = 1.0
                    } },
                    position = "bottom",
                    size = 10
                } },
            })

            dap.listeners.after.event_initialized["dapui_config"] = function()
                dapui.open()
            end
            dap.listeners.before.event_terminated["dapui_config"] = function()
                dapui.close()
            end
            dap.listeners.before.event_exited["dapui_config"] = function()
                dapui.close()
            end

            dap.adapters.gdb = {
                type = "executable",
                command = "gdb",
                args = { "--interpreter=dap", "--eval-command", "set print pretty on" }
            }

            dap.adapters.python = function(cb)
                cb({
                    type = 'executable',
                    command = 'debugpy',
                    options = {
                        source_filetype = 'python',
                    },
                })
            end

            dap.configurations.asm = {
                {
                    name = "Launch",
                    type = "gdb",
                    request = "launch",
                    program = function()
                        return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
                    end,
                    cwd = "${workspaceFolder}",
                    stopAtBeginningOfMainSubprogram = true,
                },
            }

            dap.configurations.c = dap.configurations.asm
            dap.configurations.cpp = dap.configurations.asm

            dap.configurations.rust = { {
                name = "Launch",
                type = "gdb",
                request = "launch",
                program = function()
                    vim.fn.system("cargo build")
                    return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
                end,
                cwd = "${workspaceFolder}",
                stopAtBeginningOfMainSubprogram = true,
            } }

            dap.configurations.python = { {
                name = "Launch",
                type = 'python',
                request = 'launch',
                program = function()
                    return vim.fn.input("Path to main file: ", vim.fn.getcwd() .. "/", "file")
                end,
                cwd = "${workspaceFolder}",
                pythonPath = function()
                    local cwd = vim.fn.getcwd()
                    if vim.fn.executable(cwd .. '/venv/bin/python') == 1 then
                        return cwd .. '/venv/bin/python'
                    elseif vim.fn.executable(cwd .. '/.venv/bin/python') == 1 then
                        return cwd .. '/.venv/bin/python'
                    else
                        return "/run/current-system/sw/bin/python"
                    end
                end,
            },
            }
        end
    },
}
