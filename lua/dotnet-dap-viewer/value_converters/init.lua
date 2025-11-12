---@class ValueConverter
---@field extract fun(stack_frame_id: integer, vars: Variable[], var_path: string, var_type: string, cb: fun(result: table, pretty_string: string, highlight?: string))
---@field satisfies_type fun(var_type: string, vars: Variable[]): boolean
---@field inline_value? boolean If true, the formatted value will be displayed inline and the variable becomes non-expandable

local M = {}

---@type ValueConverter[]
M.value_converters = {
  require("dotnet-dap-viewer.value_converters.exception"),
  require("dotnet-dap-viewer.value_converters.type"),
  require("dotnet-dap-viewer.value_converters.enum"),
  require("dotnet-dap-viewer.value_converters.date"),
  require("dotnet-dap-viewer.value_converters.uri"),
  require("dotnet-dap-viewer.value_converters.version"),
  require("dotnet-dap-viewer.value_converters.jobject"),
  require("dotnet-dap-viewer.value_converters.jarray"),
  require("dotnet-dap-viewer.value_converters.jvalue"),
  require("dotnet-dap-viewer.value_converters.jproperty"),
  require("dotnet-dap-viewer.value_converters.guid"),
  require("dotnet-dap-viewer.value_converters.list"),
  require("dotnet-dap-viewer.value_converters.sorted_list"),
  require("dotnet-dap-viewer.value_converters.immutable_list"),
  require("dotnet-dap-viewer.value_converters.readonly_list"),
  require("dotnet-dap-viewer.value_converters.tuple"),
  require("dotnet-dap-viewer.value_converters.hashset"),
  require("dotnet-dap-viewer.value_converters.queue"),
  require("dotnet-dap-viewer.value_converters.stack"),
  require("dotnet-dap-viewer.value_converters.dictionaries"),
  require("dotnet-dap-viewer.value_converters.readonly_dictionary"),
  require("dotnet-dap-viewer.value_converters.concurrent_dictionary"),
  require("dotnet-dap-viewer.value_converters.json_object"),
  require("dotnet-dap-viewer.value_converters.json_element"),
  require("dotnet-dap-viewer.value_converters.json_value_of_element"),
  require("dotnet-dap-viewer.value_converters.json_array"),
}

function M.simple_unwrap(unwrap_key, frame_id, vars, var_path, cb)
  local var = nil
  for _, property in ipairs(vars) do
    if property.name == unwrap_key then var = property end
  end
  if not var then error("Failed to unwrap " .. var_path .. "." .. unwrap_key) end
  if var and var.variablesReference ~= 0 then
    require("dotnet-dap-viewer.dap").resolve_by_vars_reference(frame_id, var.variablesReference, var_path .. "." .. unwrap_key, var.type, function(value) cb(value.value, value.formatted_value) end)
  else
    cb({ var }, var.value)
  end
end

---Converts a list of DAP variables into a Lua table.
---Numeric-looking keys like [0], [1] go into array part.
---Named keys go into map part.
---
---@param vars table[] # List of DAP variable tables with .name and .value
function M.vars_to_table(var_path, vars, cb)
  local result = {}

  for _, c in ipairs(vars) do
    local index = c.name:match("^%[(%d+)%]$")
    if index then
      c.var_path = var_path .. c.name
      table.insert(result, c)
    else
      c.var_path = var_path .. "." .. c.name
      result[c.name] = c
    end
  end
  cb(result, require("dotnet-dap-viewer.pretty_printers.catch-all").pretty_print(result))
end

---Resolves any C# type and invokes the given callback with the lua result
---@param stack_frame_id integer
---@param vars Variable[]
---@param var_path string
---@param var_type string
---@param cb fun(result: table, pretty_string: string, highlight?: string)
M.extract = function(stack_frame_id, vars, var_path, var_type, cb)
  ---@param r ValueConverter
  ---@type ValueConverter[]
  local matches = vim.iter(M.value_converters):filter(function(r) return r.satisfies_type(var_type, vars) end):totable()

  if #matches > 1 then
    error("More than one value converter found for type " .. var_type)
  elseif #matches == 1 then
    local converter = matches[1]

    -- If converter has inline_value, wrap the callback to mark result as inline
    if converter.inline_value then
      local original_cb = cb
      cb = function(result, pretty_string, highlight)
        -- Mark the result as having an inline value
        result._inline_formatted_value = pretty_string
        original_cb(result, pretty_string, highlight)
      end
    end

    converter.extract(stack_frame_id, vars, var_path, var_type, cb)
  else
    M.vars_to_table(var_path, vars, cb)
  end
end

return M
