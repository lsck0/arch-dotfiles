---@meta
-- type stub for the global hyprland api
---@alias HlDispatcher any

---@class HlWindowDispatchers
---@field close fun(): HlDispatcher
---@field drag fun(): HlDispatcher
---@field float fun(opts: table): HlDispatcher
---@field fullscreen fun(opts: table): HlDispatcher
---@field move fun(opts: table): HlDispatcher
---@field resize fun(opts?: table): HlDispatcher

---@class HlGroupDispatchers
---@field next fun(): HlDispatcher
---@field toggle fun(): HlDispatcher

---@class HlDispatchers
---@field dpms fun(opts: table): HlDispatcher
---@field exec_cmd fun(cmd: string): HlDispatcher
---@field focus fun(opts: table): HlDispatcher
---@field group HlGroupDispatchers
---@field layout fun(msg: string): HlDispatcher
---@field submap fun(name: string): HlDispatcher
---@field window HlWindowDispatchers

---@class Hl
---@field dsp HlDispatchers
---@field plugin table<string, any>
---@field animation fun(spec: table)
---@field bind fun(keys: string, action: HlDispatcher, opts?: table)
---@field config fun(cfg: table)
---@field curve fun(name: string, spec: table)
---@field define_submap fun(name: string, binds: fun())
---@field env fun(name: string, value: string)
---@field exec_cmd fun(cmd: string): any
---@field layer_rule fun(rule: table)
---@field monitor fun(spec: table)
---@field on fun(event: string, handler: fun(...): any)
---@field window_rule fun(rule: table)
---@field workspace_rule fun(rule: table)
hl = {}
