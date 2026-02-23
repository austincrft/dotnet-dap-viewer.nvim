local M = {}

local config = require("dotnet-dap-viewer.config")
local dap_module = require("dotnet-dap-viewer.dap")
local ui = require("dotnet-dap-viewer.ui")

-- Store original keymaps during debug session
local original_keymaps = {}
local is_registered = false

--- Extract the full dotted expression up to and including the word under the cursor.
--- For `license.Features.Count`, cursor on `Features` returns `license.Features`.
---@return string
local function get_dotted_expression()
  local line = vim.api.nvim_get_current_line()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0)) -- 0-indexed byte column
  col = col + 1 -- convert to 1-indexed

  -- Scan left from cursor: collect identifiers and dots
  local left = col
  while left > 1 do
    local ch = line:sub(left - 1, left - 1)
    if ch:match("[%w_.]") then
      left = left - 1
    else
      break
    end
  end

  -- Scan right from cursor: collect only identifier chars (stop at dot)
  local right = col
  while right < #line do
    local ch = line:sub(right + 1, right + 1)
    if ch:match("[%w_]") then
      right = right + 1
    else
      break
    end
  end

  local expr = line:sub(left, right)
  -- Trim any leading/trailing dots
  expr = expr:gsub("^%.+", ""):gsub("%.+$", "")
  return expr
end

--- Resolve a variable by name
---@param stack_frame_id integer
---@param var_name string
---@param callback fun(value: ResolvedVariable): nil
function M.resolve_variable(stack_frame_id, var_name, callback)
  dap_module.resolve_by_var_name(stack_frame_id, var_name, callback)
end

--- Resolve a variable by reference
---@param stack_frame_id integer
---@param vars_reference integer
---@param var_path string
---@param var_type string
---@param callback fun(value: ResolvedVariable): nil
function M.resolve_by_vars_reference(stack_frame_id, vars_reference, var_path, var_type, callback)
  dap_module.resolve_by_vars_reference(stack_frame_id, vars_reference, var_path, var_type, callback)
end

--- Open the variable viewer for a specific variable
---@param var_name string|nil Variable name (if nil, uses word under cursor)
function M.open_variable_viewer(var_name)
  local dap = require("dap")
  local session = dap.session()

  if not session then
    vim.notify("No active debug session", vim.log.levels.WARN)
    return
  end

  -- Get current frame
  local frame = session.current_frame
  if not frame then
    vim.notify("No current frame", vim.log.levels.WARN)
    return
  end

  -- Use word under cursor if no var_name provided
  if not var_name then
    var_name = get_dotted_expression()
  end

  -- Resolve and show the variable
  M.resolve_variable(frame.id, var_name, function(resolved)
    ui.show(resolved.value, frame.id, var_name)
  end)
end

--- Set up keymap for variable viewer
local function setup_keymap()
  local keymap = config.config.keymap
  if not keymap or keymap == false then
    return
  end

  -- Store original keymap if exists
  local current_buf = vim.api.nvim_get_current_buf()
  local maps = vim.api.nvim_buf_get_keymap(current_buf, "n")

  for _, map in ipairs(maps) do
    if map.lhs == keymap then
      original_keymaps[current_buf] = map
      break
    end
  end

  -- Set up keymap
  vim.keymap.set("n", keymap, function()
    M.open_variable_viewer()
  end, {
    buffer = current_buf,
    noremap = true,
    silent = true,
    desc = "Open .NET DAP variable viewer",
  })
end

--- Clean up keymaps after debug session
local function cleanup_keymap()
  local keymap = config.config.keymap
  if not keymap or keymap == false then
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()

  -- Remove our keymap
  pcall(vim.keymap.del, "n", keymap, { buffer = current_buf })

  -- Restore original if it existed
  if original_keymaps[current_buf] then
    vim.keymap.set("n", keymap, original_keymaps[current_buf].callback or original_keymaps[current_buf].rhs, {
      buffer = current_buf,
      noremap = original_keymaps[current_buf].noremap == 1,
      silent = original_keymaps[current_buf].silent == 1,
    })
    original_keymaps[current_buf] = nil
  end
end

--- Register with nvim-dap
local function register_with_dap()
  if is_registered then
    return
  end

  local ok, dap = pcall(require, "dap")
  if not ok then
    vim.notify("nvim-dap not found. Install nvim-dap to use auto_register_dap", vim.log.levels.WARN)
    return
  end

  -- Register listener for when debugger stops at a breakpoint
  dap.listeners.after.event_stopped["dotnet-dap-viewer"] = function(session)
    -- Only activate for netcoredbg or coreclr adapters
    local adapter = session.config.type
    local cmd = session.adapter and session.adapter["command"]
    if not (adapter == "coreclr" or adapter == "netcoredbg" or (cmd and cmd:find("netcoredbg"))) then
      return
    end

    -- Set up keymap
    setup_keymap()
  end

  -- Clean up when debug session exits
  dap.listeners.after.event_exited["dotnet-dap-viewer"] = function()
    cleanup_keymap()
    dap_module.clear_cache()
  end

  -- Clean up when debug session terminates
  dap.listeners.after.event_terminated["dotnet-dap-viewer"] = function()
    cleanup_keymap()
    dap_module.clear_cache()
  end

  is_registered = true
end

--- Setup function
---@param opts DotnetDapViewerConfig|nil
function M.setup(opts)
  config.setup(opts)

  if config.config.auto_register_dap then
    register_with_dap()
  end
end

-- Expose DAP module for advanced usage
M.dap = dap_module
M.ui = ui

return M
