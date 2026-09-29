-- ghost-text completion from a local ollama fim model
return {
    {
        "milanglacier/minuet-ai.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        event = "InsertEnter",
        opts = {
            provider = "openai_fim_compatible",
            -- don't fire a request on every keystroke
            throttle = 1000,
            debounce = 400,
            -- cap how much surrounding code is sent, so prompt eval stays cheap
            context_window = 2000,
            n_completions = 1,
            request_timeout = 4,
            provider_options = {
                openai_fim_compatible = {
                    -- literal: an env lookup nil-crashed in neovide
                    api_key = function() return "ollama" end,
                    name = "Ollama",
                    end_point = "http://localhost:11434/v1/completions",
                    model = "qwen2.5-coder:0.5b",
                    optional = {
                        max_tokens = 64,
                        top_p = 0.9,
                        stop = { "\n\n" },
                    },
                },
            },
            virtualtext = {
                auto_trigger_ft = { "*" },
                auto_trigger_ignore_ft = { "TelescopePrompt", "snacks_picker_input" },
                keymap = {
                    accept = "<A-a>",
                    accept_line = "<A-l>",
                    accept_n_lines = "<A-z>",
                    next = "<A-]>",
                    prev = "<A-[>",
                    dismiss = "<A-e>",
                },
            },
        },
    },
}
