---@type ValueConverter
return {
  satisfies_type = function(class_name) return type(class_name) == "string" and class_name:match("^System%.Collections%.ObjectModel%.ReadOnlyDictionary") end,
  extract = function(frame_id, vars, var_path, _, cb) require("dotnet-dap-viewer.value_converters").simple_unwrap("Dictionary", frame_id, vars, var_path, cb) end,
}
