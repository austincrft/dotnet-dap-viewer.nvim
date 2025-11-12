---@class Variable
---@field name string The variable's name.
---@field value string A one-line or multi-line string representing the variable.
---@field type? string The type of the variable, shown in the UI on hover.
---@field variablesReference integer Reference ID for child variables (0 = none).
---@field children? table<Variable>

---@class ResolvedVariable
---@field formatted_value string
---@field value table | string
---@field type string
---@field vars Variable[]
---@field variablesReference integer

local M = {
  ---@type table<integer, table<string, ResolvedVariable | "pending">>
  variable_cache = {},
  ---@type table<integer, table<string, (fun(value: ResolvedVariable))[]>>
  pending_callbacks = {},
}

function M.fetch_variables(variables_reference, depth, callback, frame_id, var_path)
  local dap = require("dap")
  local session = dap.session()
  if not session then
    callback({})
    return
  end

  session:request("variables", { variablesReference = variables_reference }, function(err, response)
    if err or not response or not response.variables then
      callback({})
      return
    end

    -- Helper to check if a type matches an inline converter
    local function matches_inline_converter(var_type)
      if not var_type then return false end
      local converters = require("dotnet-dap-viewer.value_converters").value_converters
      for _, converter in ipairs(converters) do
        if converter.inline_value then
          local ok, result = pcall(converter.satisfies_type, var_type, {})
          if ok and result then return true end
        end
      end
      return false
    end

    local result = {}
    local pending = #response.variables

    if pending == 0 then
      callback(result)
      return
    end

    for _, var in ipairs(response.variables) do
      local entry = {
        name = var.name,
        value = var.value,
        type = var.type,
        variablesReference = var.variablesReference,
        children = nil,
      }

      -- If this is an inline type and we have frame_id, fetch the formatted value immediately
      if frame_id and var_path and var.variablesReference ~= 0 and matches_inline_converter(var.type) then
        local eval_expr = var_path .. "." .. var.name .. ".ToString()"
        session:request("evaluate", { frameId = frame_id, expression = eval_expr, context = "hover" }, function(eval_err, eval_response)
          if not eval_err and eval_response and eval_response.result then
            entry.formatted_value = eval_response.result
            entry.variablesReference = 0
          end
          table.insert(result, entry)
          pending = pending - 1
          if pending == 0 then callback(result) end
        end)
      elseif var.variablesReference ~= 0 and depth > 0 then
        M.fetch_variables(var.variablesReference, depth - 1, function(child_vars)
          entry.children = child_vars
          pending = pending - 1
          if pending == 0 then
            table.insert(result, entry)
            callback(result)
          else
            table.insert(result, entry)
          end
        end, frame_id, var_path and (var_path .. "." .. var.name) or nil)
      else
        table.insert(result, entry)
        pending = pending - 1
        if pending == 0 then callback(result) end
      end
    end
  end)
end

M.extract = require("dotnet-dap-viewer.value_converters").extract

---@param stack_frame_id integer
---@param vars_reference integer
---@param var_type string
---@param cb fun(value: ResolvedVariable): nil
---@return false | nil
function M.resolve_by_vars_reference(stack_frame_id, vars_reference, var_path, var_type, cb)
  if stack_frame_id == nil then error("Stack frame id cannot be nil") end
  if vars_reference == nil then error("vars ref  id cannot be nil") end

  M.variable_cache[stack_frame_id] = M.variable_cache[stack_frame_id] or {}
  M.pending_callbacks[stack_frame_id] = M.pending_callbacks[stack_frame_id] or {}
  local cache = M.variable_cache[stack_frame_id]
  local callback_queue = M.pending_callbacks[stack_frame_id]
  callback_queue[vars_reference] = callback_queue[vars_reference] or {}

  if cache[vars_reference] and cache[vars_reference] ~= "pending" then return cb(cache[vars_reference]) end

  if cache[vars_reference] == "pending" then
    table.insert(callback_queue[vars_reference], cb)
    return
  end

  cache[vars_reference] = "pending"
  callback_queue[vars_reference] = { cb }

  ---@param children table<Variable>
  M.fetch_variables(vars_reference, 0, function(children)
    M.extract(stack_frame_id, children, var_path, var_type, function(lua_type, res, hi)
      -- Check if this converter produces inline values
      local has_inline_value = lua_type._inline_formatted_value ~= nil
      local inline_formatted = lua_type._inline_formatted_value

      -- Remove the marker from the result
      if has_inline_value then
        lua_type._inline_formatted_value = nil
      end

      ---@type ResolvedVariable
      local value = {
        formatted_value = "",
        hi = hi,
        vars = children,
        type = var_type,
        value = lua_type,
        variablesReference = vars_reference,
      }

      value.formatted_value = res

      -- If converter marked this as inline_value, process the result
      if has_inline_value and inline_formatted then
        -- Convert the lua_type values to include formatted_value and make non-expandable
        if type(lua_type) == "table" then
          for key, val in pairs(lua_type) do
            if type(val) == "table" and val.value then
              val.formatted_value = inline_formatted
              val.variablesReference = 0  -- Make it non-expandable
            end
          end
        end
      end

      cache[vars_reference] = value

      for _, f in ipairs(callback_queue[vars_reference]) do
        f(value)
      end
      callback_queue[vars_reference] = nil
    end)
  end, stack_frame_id, var_path)
end

---@param stack_frame_id integer
---@param var_name string
---@param cb fun(value: ResolvedVariable): nil
---@return false | nil
function M.resolve_by_var_name(stack_frame_id, var_name, cb)
  local dap = require("dap")

  M.variable_cache[stack_frame_id] = M.variable_cache[stack_frame_id] or {}
  M.pending_callbacks[stack_frame_id] = M.pending_callbacks[stack_frame_id] or {}
  local cache = M.variable_cache[stack_frame_id]
  local callback_queue = M.pending_callbacks[stack_frame_id]
  callback_queue[var_name] = callback_queue[var_name] or {}

  if cache[var_name] and cache[var_name] ~= "pending" then return cb(cache[var_name]) end

  if cache[var_name] == "pending" then
    table.insert(callback_queue[var_name], cb)
    return
  end

  cache[var_name] = "pending"
  callback_queue[var_name] = { cb }

  local eval_expr = var_name

  dap.session():request("evaluate", { frameId = stack_frame_id, expression = eval_expr, context = "hover" }, function(err, response)
    if err or not response or not response.variablesReference then
      cache[var_name] = nil
      callback_queue[var_name] = nil
      error("No variable reference found for: " .. var_name)
    end

    if response.variablesReference == 0 then
      ---@type ResolvedVariable
      local value = {
        formatted_value = response.result,
        vars = {},
        type = response.type,
        var_path = var_name,
        value = { [eval_expr] = {
          name = eval_expr,
          value = response.result,
          type = response.type,
          variablesReference = 0,
        } },
        variablesReference = response.variablesReference,
      }

      cache[var_name] = value

      for _, f in ipairs(callback_queue[var_name]) do
        f(value)
      end
      callback_queue[var_name] = nil
    else
      ---@param children table<Variable>
      M.fetch_variables(response.variablesReference, 0, function(children)
        M.extract(stack_frame_id, children, var_name, response.type, function(lua_type, res, hi)
          -- Check if this converter produces inline values
          local has_inline_value = lua_type._inline_formatted_value ~= nil
          local inline_formatted = lua_type._inline_formatted_value

          -- Remove the marker from the result
          if has_inline_value then
            lua_type._inline_formatted_value = nil
          end

          ---@type ResolvedVariable
          local value = {
            formatted_value = "",
            var_path = var_name,
            hi = hi,
            vars = children,
            type = response.type,
            value = lua_type,
            variablesReference = response.variablesReference,
          }

          value.formatted_value = res

          -- If converter marked this as inline_value, process the result
          if has_inline_value and inline_formatted then
            -- Convert the lua_type values to include formatted_value and make non-expandable
            if type(lua_type) == "table" then
              for key, val in pairs(lua_type) do
                if type(val) == "table" and val.value then
                  val.formatted_value = inline_formatted
                  val.variablesReference = 0  -- Make it non-expandable
                end
              end
            end
          end

          cache[var_name] = value

          for _, f in ipairs(callback_queue[var_name]) do
            f(value)
          end
          callback_queue[var_name] = nil
        end)
      end, stack_frame_id, var_name)
    end
  end)
end

--- Clears the variable cache for a given stack frame
---@param stack_frame_id integer|nil
function M.clear_cache(stack_frame_id)
  if stack_frame_id then
    M.variable_cache[stack_frame_id] = nil
    M.pending_callbacks[stack_frame_id] = nil
  else
    M.variable_cache = {}
    M.pending_callbacks = {}
  end
end

return M
