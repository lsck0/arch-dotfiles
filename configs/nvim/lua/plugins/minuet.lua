-- Copilot-style inline completion (ghost text), powered by a local ollama code model over its OpenAI-compatible FIM endpoint.
return {
    {
        "milanglacier/minuet-ai.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        event = "InsertEnter",
        opts = {
            provider = "openai_fim_compatible",
            -- keystroke -> request debounce/throttle, so it does not fire on
            throttle = 1000,
            debounce = 400,
            -- cap how much surrounding code is sent, so prompt eval stays cheap
            context_window = 2000,
            n_completions = 1,
            request_timeout = 4,
            provider_options = {
                openai_fim_compatible = {
                    -- ollama needs no key; the client still wants a non-empty value
                    api_key = "TERM",
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
                -- ghost text in every filetype; add an ignore list here if noisy
                auto_trigger_ft = { "*" },
                auto_trigger_ignore_ft = { "TelescopePrompt", "snacks_picker_input" },
                keymap = {
                    accept = "<A-a>",      -- accept the whole suggestion
                    accept_line = "<A-l>", -- accept one line
                    accept_n_lines = "<A-z>",
                    next = "<A-]>",
                    prev = "<A-[>",
                    dismiss = "<A-e>",
                },
            },
        },
    },
}
