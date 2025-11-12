local M = {}

---@class WindowConfig
---@field width number Width as absolute (>1) or percentage (0-1). Default: 0.8
---@field height number Height as absolute (>1) or percentage (0-1). Default: 0.8
---@field min_width number Minimum width in columns. Default: 80
---@field min_height number Minimum height in rows. Default: 20
---@field max_width number|nil Maximum width in columns
---@field max_height number|nil Maximum height in rows

---@class IconsConfig
---@field expanded string Icon for expanded items with children. Default: " "
---@field collapsed string Icon for collapsed items with children. Default: " "
---@field leaf string Icon for items without children. Default: "  "

---@class DotnetDapViewerConfig
---@field auto_register_dap boolean Auto-register with nvim-dap
---@field keymap string|false Key to open variable viewer (false to disable)
---@field window WindowConfig Floating window configuration
---@field icons IconsConfig Icon configuration for the tree view

---@type DotnetDapViewerConfig
M.config = {
  auto_register_dap = true,
  keymap = false,
  window = {
    width = 0.8,       -- 80% of editor columns
    height = 0.8,      -- 80% of editor rows
    min_width = 80,    -- Minimum 80 columns
    min_height = 20,   -- Minimum 20 rows
    max_width = 180,   -- Maximum 180 columns
    max_height = nil,  -- No maximum height by default
  },
  icons = {
    expanded = " ",   -- Icon for expanded items with children
    collapsed = " ",  -- Icon for collapsed items with children
    leaf = "  ",       -- Icon for items without children
  },
}

---@param opts DotnetDapViewerConfig|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", {}, M.config, opts or {})
end

-- Initialize with defaults
M.setup()

return M
