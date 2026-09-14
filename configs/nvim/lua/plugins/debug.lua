return {
    {
        "mfussenegger/nvim-dap", -- debug adapter protocol
        dependencies = {
            "rcarriga/nvim-dap-ui", -- debugger UI panels
            "theHamsta/nvim-dap-virtual-text", -- inline debug values
        },
        cmd = { "DapToggleBreakpoint", "DapContinue", "DapStepOver", "DapStepInto", "DapStepOut" },
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
                    type = "executable",
                    command = "debugpy",
                    options = {
                        source_filetype = "python",
                    },
                })
            end

            -- codelldb: rust + any lldb-debuggable target (installed via
            -- codelldb-bin, mason-managed binary verified on PATH).
            dap.adapters.codelldb = {
                type = "server",
                port = "${port}",
                executable = {
                    command = "codelldb",
                    args = { "--port", "${port}" },
                },
            }

            -- js-debug for typescript/javascript (vscode's debug adapter,
            -- standalone via node). Install: mason's js-debug-adapter puts
            -- js-debug-adapter-prefix here; fall back to the bare command
            -- if it's on PATH.
            local js_debug_dir = vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter"
            local js_dbg_cmd = vim.fs.find("js-debug-adapter-prefix", {
                path = vim.fn.stdpath("data") .. "/mason/bin", type = "file"
            })[1]
            if js_dbg_cmd then
                dap.adapters["pwa-node"] = {
                    type = "server",
                    host = "localhost",
                    port = "${port}",
                    executable = {
                        command = "node",
                        args = {
                            js_debug_dir .. "/js-debug/src/dapDebugServer.js",
                            "${port}",
                        },
                    },
                }
                dap.configurations.typescript = {
                    {
                        name = "Launch file",
                        type = "pwa-node",
                        request = "launch",
                        program = "${file}",
                        cwd = "${workspaceFolder}",
                        runtimeExecutable = "tsx",
                        runtimeArgs = {},
                        console = "integratedTerminal",
                        internalConsoleOptions = "neverOpen",
                        skipFiles = { "<node_internals>/**", "node_modules/**" },
                    },
                    {
                        name = "Attach to node process",
                        type = "pwa-node",
                        request = "attach",
                        processId = require("dap.utils").pick_process,
                        cwd = "${workspaceFolder}",
                    },
                }
                dap.configurations.javascript = dap.configurations.typescript
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
                name = "Launch (codelldb)",
                type = "codelldb",
                request = "launch",
                program = function()
                    vim.fn.system("cargo build")
                    return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
                end,
                cwd = "${workspaceFolder}",
                stopOnEntry = false,
            } }

            dap.configurations.python = { {
                name = "Launch",
                type = "python",
                request = "launch",
                program = function()
                    return vim.fn.input("Path to main file: ", vim.fn.getcwd() .. "/", "file")
                end,
                cwd = "${workspaceFolder}",
                pythonPath = function()
                    local cwd = vim.fn.getcwd()
                    if vim.fn.executable(cwd .. "/venv/bin/python") == 1 then
                        return cwd .. "/venv/bin/python"
                    elseif vim.fn.executable(cwd .. "/.venv/bin/python") == 1 then
                        return cwd .. "/.venv/bin/python"
                    else
                        return "/run/current-system/sw/bin/python"
                    end
                end,
            },
            }
        end
    },
}
