local M = {}

-- Simple floating window implementation
local Window = {}
Window.__index = Window

local function get_default_win_opts()
  local config = require("dotnet-dap-viewer.config")
  local win_config = config.config.window

  -- Calculate width
  local width
  if win_config.width <= 1 then
    -- Percentage mode
    width = math.floor(vim.o.columns * win_config.width)
  else
    -- Absolute mode
    width = math.floor(win_config.width)
  end

  -- Calculate height
  local height
  if win_config.height <= 1 then
    -- Percentage mode
    height = math.floor(vim.o.lines * win_config.height)
  else
    -- Absolute mode
    height = math.floor(win_config.height)
  end

  -- Apply minimum constraints
  width = math.max(width, win_config.min_width or 80)
  height = math.max(height, win_config.min_height or 20)

  -- Apply maximum constraints
  if win_config.max_width then
    width = math.min(width, win_config.max_width)
  end
  if win_config.max_height then
    height = math.min(height, win_config.max_height)
  end

  -- Ensure we don't exceed screen size
  width = math.min(width, vim.o.columns - 4)
  height = math.min(height, vim.o.lines - 4)

  return {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  }
end

-- Sort members by visibility (public first, then private/protected)
local function sort_members(members)
  table.sort(members, function(a, b)
    local a_name = a.name
    local b_name = b.name

    -- Special categories ("Static members", "Raw View", etc.) go last
    local a_special = (a_name == "Static members" or a_name == "Raw View" or a_name == "Non-Public members")
    local b_special = (b_name == "Static members" or b_name == "Raw View" or b_name == "Non-Public members")

    if a_special and not b_special then return false end
    if not a_special and b_special then return true end
    if a_special and b_special then return a_name < b_name end

    -- Public members (no underscore prefix) before private (underscore prefix)
    local a_private = a_name:match("^_")
    local b_private = b_name:match("^_")

    if a_private and not b_private then return false end
    if not a_private and b_private then return true end

    -- Alphabetical within same visibility (case-insensitive)
    return a_name:lower() < b_name:lower()
  end)
  return members
end

function Window.new_float()
  local self = setmetatable({}, Window)
  self.buf = vim.api.nvim_create_buf(false, true)
  self.opts = get_default_win_opts()
  self.buf_opts = {
    modifiable = false,
    filetype = nil,
  }
  self.callbacks = {}
  return self
end

function Window:write_buf(lines)
  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf })
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf })
  return self
end

function Window:close()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
    self.win = nil
  end
end

function Window:pos_center()
  self.opts.col = math.floor((vim.o.columns - self.opts.width) / 2)
  if self.win then
    vim.api.nvim_win_set_config(self.win, self.opts)
  end
  return self
end

function Window:create()
  local win = vim.api.nvim_open_win(self.buf, true, self.opts)
  self.win = win

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(self.win, true)
  end, { buffer = self.buf, noremap = true, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(self.win, true)
  end, { buffer = self.buf, noremap = true, silent = true })

  vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf })

  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
      if tonumber(event.match) == win then
        for _, cb in ipairs(self.callbacks) do
          cb()
        end
      end
    end,
  })
  return self
end

-- Debugger float state
local state = {
  root_vars = {},
  lines = {},
  line_to_var = {},
  current_frame_id = nil,
}

-- Recursively flatten variable tree into display lines
local function build_lines(vars, indent, line_counter)
  indent = indent or ""
  line_counter = line_counter or { count = 0 }
  local lines = {}
  local config = require("dotnet-dap-viewer.config")
  local icons = config.config.icons

  for _, var in ipairs(vars) do
    local prefix = var.variablesReference and var.variablesReference > 0 and (var.expanded and icons.expanded or icons.collapsed) or icons.leaf

    -- Build the display value
    local display_value = var.loading and "Loading..." or var.value or ""

    -- If there's a formatted_value and it's different from the regular value, append it
    if var.formatted_value and var.formatted_value ~= var.value and var.formatted_value ~= display_value and not var.loading then
      display_value = display_value .. " " .. var.formatted_value
    end

    local label = indent .. prefix .. var.name .. ": " .. display_value

    line_counter.count = line_counter.count + 1
    table.insert(lines, label)
    state.line_to_var[line_counter.count] = var

    if var.expanded and var.children then
      local sub = build_lines(var.children, indent .. "  ", line_counter)
      vim.list_extend(lines, sub)
    end
  end

  return lines
end

local function apply_highlights(window, lines)
  local ns = vim.api.nvim_create_namespace("dotnet-dap-viewer")
  local hi = "DotnetDapViewersVariable"
  for i, _ in ipairs(lines) do
    vim.api.nvim_buf_add_highlight(window.buf, ns, hi, i - 1, 0, -1)
  end
end

local function redraw(window)
  state.line_to_var = {}
  state.lines = build_lines(state.root_vars)
  window:write_buf(state.lines)
  apply_highlights(window, state.lines)
end

function M.redraw()
  if M._current_window then
    redraw(M._current_window)
  end
end

local function is_list(tbl)
  return type(tbl) == "table" and tbl[1] ~= nil
end

-- Expand/collapse variable at cursor
function M.toggle_under_cursor(window)
  local cursor = vim.api.nvim_win_get_cursor(window.win)
  local line = cursor[1]
  local var = state.line_to_var[line]

  if not var or not var.variablesReference or var.variablesReference == 0 then
    return
  end

  if var.expanded then
    var.expanded = false
    redraw(window)
    return
  end

  if var.children then
    var.expanded = true
    redraw(window)
    return
  end

  var.loading = true
  var.expanded = true
  redraw(window)

  local dap = require("dotnet-dap-viewer.dap")
  dap.resolve_by_vars_reference(state.current_frame_id, var.variablesReference, var.var_path, var.type, function(children)
    ---@type table
    ---@diagnostic disable-next-line: assign-type-mismatch
    local converted_value = children.value

    if is_list(converted_value) then
      var.children = vim.tbl_map(function(r)
        return {
          name = r.name,
          type = r.type,
          value = r.value,
          var_path = r.var_path,
          variablesReference = r.variablesReference,
          formatted_value = r.formatted_value,
          expanded = false,
          children = r.children,
        }
      end, converted_value)
      var.children = sort_members(var.children)
    else
      local root_vars = {}
      for key, value in pairs(converted_value) do
        table.insert(root_vars, {
          name = key,
          value = value.value or value,
          type = value.type,
          var_path = value.var_path,
          variablesReference = value.variablesReference,
          formatted_value = value.formatted_value,
          expanded = false,
          children = value.children,
        })
      end
      var.children = sort_members(root_vars)
    end

    var.loading = false
    redraw(window)
  end)
end

--- Show debugger variable UI
---@param varlist table[] List of DAP-style variables
---@param frame_id number Frame ID to use for async resolution
function M.show(varlist, frame_id)
  if M._current_window then
    M.close()
  end
  state.current_frame_id = frame_id

  local root_vars = {}
  for key, value in pairs(varlist) do
    table.insert(root_vars, {
      name = key,
      value = value.value or value,
      type = value.type,
      var_path = value.var_path,
      variablesReference = value.variablesReference,
      formatted_value = value.formatted_value,
      expanded = false,
      children = value.children,
    })
  end

  state.root_vars = sort_members(root_vars)

  local float = Window.new_float():pos_center():create()
  M._current_window = float
  M.redraw()

  vim.keymap.set("n", "<CR>", function()
    M.toggle_under_cursor(float)
  end, { buffer = float.buf, noremap = true, silent = true })

  return float
end

function M.close()
  if M._current_window then
    M._current_window:close()
    M._current_window = nil
  end
end

return M
