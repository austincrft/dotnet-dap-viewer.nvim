---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    return class_name:match("^Newtonsoft%.Json%.Linq%.JArray$") ~= nil
  end,
  extract = function(frame_id, vars, var_path, _, cb) require("dotnet-dap-viewer.value_converters").simple_unwrap("_values", frame_id, vars, var_path, cb) end,
}
