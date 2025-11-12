# dotnet-dap-viewer.nvim

A standalone Neovim plugin that provides a custom debug viewier. It includes intelligent type converters for .NET debugging with nvim-dap. Automatically unwraps and formats complex .NET types (Lists, Dictionaries, GUIDs, Enums, etc.) for easier inspection during debug sessions.

This plugin extracts and adapts code from [easy-dotnet.nvim](https://github.com/GustavEikaas/easy-dotnet.nvim) by GustavEikaas, focusing specifically on the DAP type conversion functionality. If you are looking for a batteries-included approach to .NET development with Neovim, easy-dotnet.nvim is the best choice.

## Features

- **Type Converters** for common .NET types
- **Automatic Type Detection** and conversion
- **Floating Window Viewer** with expandable tree interface

## Supported Types

### Collections

- `List<T>` - Extracts `_items` array and respects `_size`
- `SortedList<K,V>` - Sorted key-value pairs
- `ImmutableList<T>` - Immutable list implementation
- `ReadOnlyCollection<T>` - Read-only wrapper
- `Dictionary<K,V>` - Key-value pairs with proper key formatting
- `OrderedDictionary<K,V>` - Ordered key-value pairs
- `ReadOnlyDictionary<K,V>` - Read-only dictionary wrapper
- `ConcurrentDictionary<K,V>` - Thread-safe dictionary
- `HashSet<T>` - Unique value collection
- `Queue<T>` - FIFO queue
- `Stack<T>` - LIFO stack (reversed for display)

### Simple Values

- `Guid` - Formatted GUID strings
- `DateOnly`, `DateTime`, `DateTimeOffset`, `TimeOnly`, `TimeSpan` - Human-readable dates
- `Version` - Version strings (e.g., "1.2.3.4")
- `Uri` - URI/URL strings
- `Enum` - Enum name + value (e.g., "Success = 1")
- `RuntimeType` - Type name and full name

### JSON Types

- `System.Text.Json.JsonElement`
- `System.Text.Json.Nodes.JsonObject`
- `System.Text.Json.Nodes.JsonArray`
- `System.Text.Json.Nodes.JsonValue`
- `Newtonsoft.Json.Linq.JObject`
- `Newtonsoft.Json.Linq.JArray`
- `Newtonsoft.Json.Linq.JProperty`
- `Newtonsoft.Json.Linq.JValue`

### Special Types

- `Exception` - Extracts message, inner exception, source, data, and stack trace with special highlighting

### Tuples

- `Tuple<>` and `ValueTuple<>` - Item1, Item2, etc. extracted as list

## Requirements

- Neovim >= 0.9
- [nvim-dap](https://github.com/mfussenegger/nvim-dap)
- [netcoredbg](https://github.com/Samsung/netcoredbg) (for .NET debugging)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "austincrft/dotnet-dap-viewer.nvim",
  dependencies = {
    "mfussenegger/nvim-dap",
  },
  opts = {},
}
```

## Configuration

### Default Configuration

```lua
require("dotnet-dap-viewer").setup({
  auto_register_dap = true,  -- Automatically integrate with nvim-dap
  keymap = false,            -- Key to open variable viewer (set to a string like "T" to enable)
  window = {
    width = 0.8,             -- 80% of editor width (or absolute like 120)
    height = 0.8,            -- 80% of editor height (or absolute like 40)
    min_width = 80,          -- Minimum 80 columns
    min_height = 20,         -- Minimum 20 rows
    max_width = 180,         -- Maximum 180 columns (useful for ultrawide monitors)
    max_height = nil,        -- No maximum height by default
  },
  icons = {
    expanded = " ",         -- Icon for expanded items with children
    collapsed = " ",        -- Icon for collapsed items with children
    leaf = "  ",             -- Icon for items without children
  },
})
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `auto_register_dap` | `boolean` | `true` | Automatically hook into nvim-dap events and enable converters |
| `keymap` | `string\|false` | `false` | Keymap to open variable viewer (provide a key like `"T"` to enable) |
| `window.width` | `number` | `0.8` | Window width as percentage (0-1) or absolute columns (>1) |
| `window.height` | `number` | `0.8` | Window height as percentage (0-1) or absolute rows (>1) |
| `window.min_width` | `number` | `80` | Minimum window width in columns |
| `window.min_height` | `number` | `20` | Minimum window height in rows |
| `window.max_width` | `number\|nil` | `180` | Maximum window width in columns (useful for ultrawide monitors) |
| `window.max_height` | `number\|nil` | `nil` | Maximum window height in rows |
| `icons.expanded` | `string` | `" "` | Icon displayed for expanded items with children |
| `icons.collapsed` | `string` | `" "` | Icon displayed for collapsed items with children |
| `icons.leaf` | `string` | `"  "` | Icon displayed for items without children |

## Usage

### Automatic Mode (Default)

When `auto_register_dap = true` (default), the plugin automatically enhances your debug sessions:

1. Start a debug session with nvim-dap
2. If you've configured a keymap (e.g., `keymap = "<leader><leader>"`), press that key while cursor is on a variable when stopped at a breakpoint
3. A floating window opens showing the converted variable in an expandable tree view
4. Use `<CR>` to expand/collapse items, `q`/`<Esc>` to close

### Manual Mode

If you set `auto_register_dap = false`, you can manually open the viewer:

```lua
require("dotnet-dap-viewers").open_variable_viewer("myVariable")
```

## Floating Window Controls

When the variable viewer is open:

- `<CR>` / `Enter` - Expand/collapse variable under cursor
- `q` / `<Esc>` - Close the window
- `hjkl` / Arrow keys - Navigate

## Examples

### Before (raw DAP output)
```
myList = {System.Collections.Generic.List<int>}
  _items = {int[10]}
  _size = 3
  _version = 1
```

### After (with converters)
```
 myList: [3] - [1, 2, 3]
```

### Expanded View
```
 myList: [3] - [1, 2, 3]
   [0]: 1
   [1]: 2
   [2]: 3
```

### GUID Conversion
```
Before: { _a = 12345, _b = 6789, ... }
After:  12345678-1234-1234-1234-123456789abc
```

### Dictionary Conversion
```
Before: { _entries = {...}, _count = 2, ... }
After:  { key1: value1, key2: value2 }
```

## License

MIT License - See [LICENSE](LICENSE) for details.

## Credits

This plugin extracts and adapts code from [easy-dotnet.nvim](https://github.com/GustavEikaas/easy-dotnet.nvim) by GustavEikaas, focusing specifically on the DAP type conversion functionality.

## See Also

- [easy-dotnet.nvim](https://github.com/GustavEikaas/easy-dotnet.nvim) - Full-featured .NET development plugin
- [nvim-dap](https://github.com/mfussenegger/nvim-dap) - Debug Adapter Protocol client
- [netcoredbg](https://github.com/Samsung/netcoredbg) - .NET Core debugger
