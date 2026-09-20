return {
    {
        "mfussenegger/nvim-dap",               -- debug adapter protocol
        dependencies = {
            "rcarriga/nvim-dap-ui",            -- debugger UI panels
            "theHamsta/nvim-dap-virtual-text", -- inline debug values
        },
        cmd = { "DapToggleBreakpoint", "DapContinue", "DapStepOver", "DapStepInto", "DapStepOut" },
        init = function()
            -- ssh -L tunnels for remote attach: :DapTunnel <ssh-host> <port> [remote-port]
            local tunnels = {}
            vim.api.nvim_create_user_command("DapTunnel", function(o)
                local host, port = o.fargs[1], o.fargs[2]
                local forward = ("127.0.0.1:%s:127.0.0.1:%s"):format(port, o.fargs[3] or port)
                local stderr = {}
                tunnels[port] = vim.fn.jobstart({
                    "ssh", "-N", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "ExitOnForwardFailure=yes", "-L", forward, host,
                }, {
                    stderr_buffered = true,
                    on_stderr = function(_, data) stderr = data end,
                    on_exit = function(_, code)
                        tunnels[port] = nil
                        vim.notify(("DapTunnel %s:%s closed (%d) %s"):format(host, port, code,
                            table.concat(stderr, " ")), code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
                    end,
                })
                vim.notify(("DapTunnel 127.0.0.1:%s -> %s"):format(port, host))
            end, { nargs = "+", desc = "SSH port forward for remote debugging" })
            vim.api.nvim_create_user_command("DapTunnelStop", function()
                for _, job in pairs(tunnels) do vim.fn.jobstop(job) end
            end, { desc = "Stop all DapTunnel forwards" })
        end,
        config = function()
            require("nvim-dap-virtual-text").setup()
            local dap, dapui = require("dap"), require("dapui")
            local pick_process = require("dap.utils").pick_process

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
            -- js-debug runs child sessions; close only when the last one ends
            local function close_ui()
                if vim.tbl_count(dap.sessions()) <= 1 then dapui.close() end
            end
            dap.listeners.before.event_terminated["dapui_config"] = close_ui
            dap.listeners.before.event_exited["dapui_config"] = close_ui

            -- buffers without dap configs (empty, dashboard, ...) list every filetype's configs
            dap.providers.configs["fallback"] = function(bufnr)
                if dap.configurations[vim.bo[bufnr].filetype] then return {} end
                local all, seen = {}, {}
                for _, configs in pairs(dap.configurations) do
                    for _, c in ipairs(configs) do
                        if not seen[c] then
                            seen[c] = true
                            table.insert(all, c)
                        end
                    end
                end
                return all
            end

            local function input_port(default)
                return function() return tonumber(vim.fn.input("Port: ", default)) end
            end
            local function input_path(prompt, default)
                return function() return vim.fn.input(prompt, default, "file") end
            end

            -- native: gdb for c/cpp/asm, codelldb for rust
            dap.adapters.gdb = {
                type = "executable",
                command = "gdb",
                args = { "--interpreter=dap", "--eval-command", "set print pretty on" }
            }

            dap.adapters.codelldb = {
                type = "server",
                port = "${port}",
                executable = {
                    command = "codelldb",
                    args = { "--port", "${port}" },
                },
            }

            local native_attach = {
                {
                    name = "Attach to process (gdb)",
                    type = "gdb",
                    request = "attach",
                    pid = pick_process,
                    cwd = "${workspaceFolder}",
                },
                {
                    -- remote: gdbserver :2345 ./prog (tunnel with :DapTunnel host 2345)
                    name = "Attach to gdbserver (remote)",
                    type = "gdb",
                    request = "attach",
                    target = function() return "127.0.0.1:" .. vim.fn.input("Port: ", "2345") end,
                    program = input_path("Local binary (symbols): ", vim.fn.getcwd() .. "/"),
                    cwd = "${workspaceFolder}",
                },
            }

            dap.configurations.c = vim.list_extend({
                {
                    name = "Launch (gdb)",
                    type = "gdb",
                    request = "launch",
                    program = input_path("Path to executable: ", vim.fn.getcwd() .. "/"),
                    cwd = "${workspaceFolder}",
                    stopAtBeginningOfMainSubprogram = true,
                },
            }, native_attach)
            dap.configurations.cpp = dap.configurations.c
            dap.configurations.asm = dap.configurations.c

            dap.configurations.rust = vim.list_extend({
                {
                    name = "Launch (codelldb)",
                    type = "codelldb",
                    request = "launch",
                    program = function()
                        vim.fn.system("cargo build")
                        return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
                    end,
                    cwd = "${workspaceFolder}",
                    stopOnEntry = false,
                },
                {
                    name = "Attach to process (codelldb)",
                    type = "codelldb",
                    request = "attach",
                    pid = pick_process,
                },
            }, native_attach)

            -- python: debugpy from mason; attach with connect goes straight to a
            -- `python -m debugpy --listen 5678` server
            local debugpy_python = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
            dap.adapters.python = function(cb, config)
                if config.request == "attach" and config.connect then
                    cb({ type = "server", host = config.connect.host, port = config.connect.port })
                else
                    cb({
                        type = "executable",
                        command = debugpy_python,
                        args = { "-m", "debugpy.adapter" },
                        options = { source_filetype = "python" },
                    })
                end
            end

            local function project_python()
                for _, venv in ipairs({ "venv", ".venv" }) do
                    local python = vim.fn.getcwd() .. "/" .. venv .. "/bin/python"
                    if vim.fn.executable(python) == 1 then return python end
                end
                return vim.fn.exepath("python3")
            end

            dap.configurations.python = {
                {
                    name = "Launch file",
                    type = "python",
                    request = "launch",
                    program = "${file}",
                    cwd = "${workspaceFolder}",
                    pythonPath = project_python,
                },
                {
                    name = "Attach to process",
                    type = "python",
                    request = "attach",
                    processId = pick_process,
                    justMyCode = false,
                },
                {
                    name = "Attach to debugpy port (remote)",
                    type = "python",
                    request = "attach",
                    connect = function()
                        return { host = "127.0.0.1", port = tonumber(vim.fn.input("Port: ", "5678")) }
                    end,
                    pathMappings = function()
                        return { {
                            localRoot = vim.fn.getcwd(),
                            remoteRoot = vim.fn.input("Remote root: ", "/"),
                        } }
                    end,
                    justMyCode = false,
                },
            }

            -- java: jdtls loads the java-debug bundle (lsp.lua) and hands out the adapter port
            local function jdtls_command(command, arguments)
                local client = vim.lsp.get_clients({ name = "jdtls" })[1]
                assert(client, "jdtls not running, open a .java file first")
                local res = client:request_sync("workspace/executeCommand",
                    { command = command, arguments = arguments }, 30000)
                assert(res and not res.err, command .. " failed: " .. vim.inspect(res and res.err))
                return res.result
            end

            dap.adapters.java = function(cb)
                cb({
                    type = "server",
                    host = "127.0.0.1",
                    port = jdtls_command("vscode.java.startDebugSession"),
                    enrich_config = function(config, on_config)
                        if config.request ~= "launch" or config.mainClass then return on_config(config) end
                        vim.ui.select(jdtls_command("vscode.java.resolveMainClass") or {}, {
                            prompt = "Main class: ",
                            format_item = function(m) return m.mainClass end,
                        }, function(m)
                            if not m then return end
                            local args = { m.mainClass, m.projectName }
                            local paths = jdtls_command("vscode.java.resolveClasspath", args)
                            on_config(vim.tbl_extend("force", config, {
                                mainClass = m.mainClass,
                                projectName = m.projectName,
                                modulePaths = paths[1],
                                classPaths = paths[2],
                                javaExec = jdtls_command("vscode.java.resolveJavaExecutable", args),
                            }))
                        end)
                    end,
                })
            end

            dap.configurations.java = {
                {
                    name = "Launch main class",
                    type = "java",
                    request = "launch",
                    cwd = "${workspaceFolder}",
                },
                {
                    -- java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005
                    name = "Attach to JDWP port (remote)",
                    type = "java",
                    request = "attach",
                    hostName = "127.0.0.1",
                    port = input_port("5005"),
                },
            }

            -- javascript/typescript: js-debug from mason; node >= 23 runs .ts directly
            local js_debug_server = vim.fn.stdpath("data")
                .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js"
            dap.adapters["pwa-node"] = {
                type = "server",
                host = "127.0.0.1",
                port = "${port}",
                executable = {
                    command = "node",
                    args = { js_debug_server, "${port}", "127.0.0.1" },
                },
            }

            dap.configurations.javascript = {
                {
                    name = "Launch file",
                    type = "pwa-node",
                    request = "launch",
                    program = "${file}",
                    cwd = "${workspaceFolder}",
                    console = "integratedTerminal",
                    skipFiles = { "<node_internals>/**", "node_modules/**" },
                },
                {
                    name = "Attach to node process",
                    type = "pwa-node",
                    request = "attach",
                    processId = pick_process,
                    cwd = "${workspaceFolder}",
                },
                {
                    -- node --inspect; remote: :DapTunnel host 9229
                    name = "Attach to inspector port (remote)",
                    type = "pwa-node",
                    request = "attach",
                    address = "127.0.0.1",
                    port = input_port("9229"),
                    localRoot = "${workspaceFolder}",
                    remoteRoot = function() return vim.fn.input("Remote root: ", "/opt/") end,
                    cwd = "${workspaceFolder}",
                    sourceMaps = true,
                    skipFiles = { "<node_internals>/**", "node_modules/**" },
                },
            }
            for _, ft in ipairs({ "typescript", "javascriptreact", "typescriptreact" }) do
                dap.configurations[ft] = dap.configurations.javascript
            end
        end
    },
}
