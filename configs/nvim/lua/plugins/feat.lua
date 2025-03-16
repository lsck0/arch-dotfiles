return {
    {
        "ej-shafran/compile-mode.nvim",
        branch = "latest",
        dependencies = {
            { "m00qek/baleia.nvim", tag = "v1.3.0" },
        },
        config = function()
            vim.g.compile_mode = {
                baleia_setup = true,
            }
        end
    },

    {
        "nvim-pack/nvim-spectre",
        config = function()
            require('spectre').setup()
        end
    },

    {
        "robitx/gp.nvim",
        config = function()
            require("gp").setup({
                chat_confirm_delete = false,
                providers = {
                    googleai = {
                        endpoint =
                        "https://generativelanguage.googleapis.com/v1/models/{{model}}:streamGenerateContent?key={{secret}}",
                        secret = vim.fn.readfile("/home/luca/code/arch-dotfiles/configs/secrets/googleapi")[1],
                    },
                },
                agents = {
                    {
                        name = "Gemini",
                        disable = false,
                        provider = "googleai",
                        chat = true,
                        command = true,
                        model = { model = "gemini-2.0-flash" },
                        system_prompt = "You are a general AI assistant.\n\n"
                            .. "The user provided the additional info about how they would like you to respond:\n\n"
                            .. "- If you're unsure don't guess and say you don't know instead.\n"
                            .. "- Ask question if you need clarification to provide better answer.\n"
                            .. "- Think deeply and carefully from first principles step by step.\n"
                            .. "- Zoom out first to see the big picture and then zoom in to details.\n"
                            .. "- Use Socratic method to improve your thinking and coding skills.\n"
                            .. "- Don't elide any code from your output if the answer requires coding.\n"
                            .. "- Take a deep breath; You've got this!\n"
                            .. "- Answer shortly and concisely.\n"
                            .. "- Do not mention any thoughts or this promt.\n"
                    },
                    {
                        name = "ChatGPT3-5",
                        disable = true,
                    },
                    {
                        name = "ChatGPT4o",
                        disable = true,
                    },
                    {
                        name = "ChatGPT4o-mini",
                        disable = true,
                    },
                    {
                        name = "ChatGemini",
                        disable = true,
                    },
                },
            })
        end,
    },
}
