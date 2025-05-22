--- @module 'blink.cmp'
--- @class blink.cmp.Source
local yaml_parser = require("lyaml")
local source = {}

-- Cache for helm chart values
local values_cache = {}

-- Show values in vsplit
local function show_values(values)
  -- Open vertical split with the schema for reference
  vim.cmd("vsplit")
  vim.cmd("enew")
  vim.bo.filetype = "yaml"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(values, "\n"))
  vim.api.nvim_buf_set_keymap(0, "n", "q", ":bd!<CR>", { nowait = true, noremap = true, silent = true })
end

-- Execute helm show values command and parse the results
local function fetch_helm_values(chart_name)
  -- Check cache first
  if values_cache[chart_name] then
    return values_cache[chart_name]
  end

  -- Execute helm command to get values
  local cmd = { "helm", "show", "values", chart_name }
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    vim.notify("Failed to execute helm command: " .. result.stderr, vim.log.levels.ERROR)
    return {}
  end

  if result.stderr then
    vim.notify(result.stderr, vim.log.levels.WARN)
  end

  -- Parse YAML to Lua table
  if not yaml_parser then
    vim.notify("YAML parser not available. Install 'yaml.lua' for better parsing.", vim.log.levels.WARN)
    -- Fall back to a simple parsing approach if yaml module is not available
    return {}
  end

  local ok2, parsed = pcall(yaml_parser.load, result.stdout)
  if not ok2 then
    vim.notify("Failed to parse helm values YAML:" .. vim.inspect(parsed), vim.log.levels.ERROR)
    return {}
  end

  -- Cache the results
  values_cache[chart_name] = parsed
  return parsed
end

-- Detect chart references in a file
local function scan_file_for_charts(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local charts = {}
  local current_block = nil

  for i, line in ipairs(lines) do
    -- Look for chart annotations: # @repo/chart
    local chart_ref = line:match("#%s*@([%w%-%.%/]+)")
    if chart_ref then
      -- We found a chart reference
      current_block = {
        chart = chart_ref,
        line = i,
        key = line:match("^(%S+):"), -- The top-level key
      }

      if current_block.key then
        charts[current_block.key] = current_block
      end
    end

    -- If we're not in a block and we find a top-level key (no indentation)
    if not current_block and line:match("^%S+:") then
      local key = line:match("^(%S+):")
      current_block = {
        chart = nil, -- No chart reference yet
        line = i,
        key = key,
      }
      charts[key] = current_block
    end
  end

  return charts
end

-- Determine which chart block the cursor is in
local function get_current_chart_block(bufnr, cursor_row)
  local charts = scan_file_for_charts(bufnr)
  local current_block = nil
  local current_line = 0

  -- Find which block contains the cursor
  for _, block in pairs(charts) do
    if block.line <= cursor_row and block.line > current_line then
      current_block = block
      current_line = block.line
    end
  end

  return current_block
end

-- Get parent key path at cursor position
local function get_parent_key_path(bufnr, cursor_row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursor_row, false)
  local current_line = lines[cursor_row]

  -- Check if we're within a key definition
  local current_indent = vim.fn.indent(cursor_row)
  local path = {}

  -- Scan backwards to find parent keys
  for i = cursor_row - 1, 1, -1 do
    local line = lines[i]
    local indent = line:match("^(%s*)")
    local indent_level = #indent

    if indent_level < current_indent then
      local key = line:match("^%s*([^:]+):")
      if key then
        table.insert(path, 1, key:match("^%s*(.-)%s*$")) -- Trim whitespace
        current_indent = indent_level

        -- If we hit a zero-indent line, we've reached the top level
        if indent_level == 0 then
          break
        end
      end
    end
  end

  -- If we're currently typing a key, extract it
  local current_key = current_line:match("^%s*([^:]+)$")
  if current_key then
    table.insert(path, current_key:match("^%s*(.-)%s*$")) -- Trim whitespace
  end

  return path
end

-- Convert nested table of helm values to flat completion items
local function flatten_helm_values(tbl, prefix, current_path)
  prefix = prefix or ""
  current_path = current_path or {}
  --- @type lsp.CompletionItem
  local items = {}

  for k, v in pairs(tbl) do
    local key = prefix == "" and k or prefix .. "." .. k
    local path = vim.deepcopy(current_path)
    table.insert(path, k)

    if type(v) == "table" then
      -- Recurse for nested tables
      local nested_items = flatten_helm_values(v, key, path)
      for _, item in ipairs(nested_items) do
        table.insert(items, item)
      end

      --- @type lsp.CompletionItem
      local item = {
        label = k, -- Just the key name for display
        original_label = key, -- The full path for reference
        kind = require("blink.cmp.types").CompletionItemKind.Field,
        filterText = k,
        sortText = string.format("a%03d", #items), -- Sort objects first
        insertText = k,
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
        path = path,
        documentation = {
          kind = "markdown",
          value = "# " .. key .. "\nObject.",
        },
      }

      -- Also add the parent key as a completion item
      table.insert(items, item)
    else
      -- Handle primitive values (strings, numbers, booleans)
      local value_str = tostring(v)
      local value_kind = require("blink.cmp.types").CompletionItemKind.Value

      if type(v) == "string" then
        value_str = '"' .. value_str .. '"'
        value_kind = require("blink.cmp.types").CompletionItemKind.Text
      elseif type(v) == "number" then
        value_kind = require("blink.cmp.types").CompletionItemKind.Constant
      elseif type(v) == "boolean" then
        value_kind = require("blink.cmp.types").CompletionItemKind.Keyword
      end

      --- @type lsp.CompletionItem
      local item = {
        label = k, -- Just the key name for display
        original_label = key, -- The full path for reference
        kind = value_kind,
        filterText = k,
        sortText = string.format("b%03d", #items), -- Sort values after objects
        insertText = k .. ": " .. value_str,
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
        path = path,
        documentation = {
          kind = "markdown",
          value = "# " .. key .. "\nValue: `" .. value_str .. "`\nType: `" .. type(v) .. "`",
        },
      }
      table.insert(items, item)
    end
  end

  return items
end

-- Check if we're in a helm values file
local function is_helm_values_file()
  local filename = vim.fn.expand("%:t")
  return filename:match(".*values.ya?ml$") ~= nil
end

-- Get appropriate completion items based on cursor position and context
local function get_completion_items(bufnr, cursor_row, cursor_col)
  -- Find which chart block we're in
  local current_block = get_current_chart_block(bufnr, cursor_row)
  if not current_block or not current_block.chart then
    -- No chart annotation found, fallback to default behavior
    return {}
  end

  -- Get the chart's values
  local values = fetch_helm_values(current_block.chart)
  if not values or vim.tbl_isempty(values) then
    vim.notify("No values found for chart: " .. current_block.chart, vim.log.levels.WARN)
    return {}
  end

  -- Get the key path up to the cursor
  local parent_path = get_parent_key_path(bufnr, cursor_row)

  -- If we have a top-level key that doesn't match our block key,
  -- we're probably in a different block or at the top level
  if #parent_path > 0 and parent_path[1] ~= current_block.key then
    -- We might be in a different section of the file
    return {}
  end

  -- Remove the top-level key (e.g., "jenkins:") from our path
  if #parent_path > 0 and parent_path[1] == current_block.key then
    table.remove(parent_path, 1)
  end

  -- Get all completion items for this chart
  local items = flatten_helm_values(values)

  -- Filter based on our current path
  if #parent_path > 0 then
    -- We're in a nested path, filter items appropriately
    local filtered_items = {}

    for _, item in ipairs(items) do
      --   -- Check if this item's path matches our current path prefix
      local matches = true
      for i = 1, #parent_path - 1 do
        if i > #item.path or item.path[i] ~= parent_path[i] then
          matches = false
          break
        end
      end

      if matches and #item.path == #parent_path then
        -- This item is at the next level down from our current path
        local new_item = vim.deepcopy(item)

        -- We only want to show the next level in the hierarchy
        new_item.label = item.path[#parent_path]
        new_item.filterText = new_item.label
        new_item.sortText = new_item.sortText:sub(1, 1) .. new_item.label

        -- If it's the last level, include the value in the completion
        if #item.path == #parent_path + 1 then
          -- It's a leaf node, keep any value
          new_item.insertText = new_item.insertText
        else
          -- It's an intermediate node, just insert the key
          new_item.insertText = new_item.label .. ":"
        end

        table.insert(filtered_items, new_item)
      end
    end

    -- Remove duplicates (we might have multiple completion items with the same key)
    local seen = {}
    local unique_items = {}

    for _, item in ipairs(filtered_items) do
      if not seen[item.label] then
        seen[item.label] = true
        table.insert(unique_items, item)
      end
    end

    return unique_items
  end

  -- If we're at the top level, just return first-level items
  local top_level_items = {}
  local seen = {}

  for _, item in ipairs(items) do
    if #item.path == 1 and not seen[item.label] then
      seen[item.label] = true
      table.insert(top_level_items, item)
    end
  end

  return top_level_items
end

-- `opts` table comes from `sources.providers.helm_values.opts`
function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = opts or {}
  return self
end

-- Enable the source in helm/yaml files
function source:enabled()
  return is_helm_values_file()
end

function source:get_completions(ctx, callback)
  local bufnr = ctx.bufnr
  local cursor_row = ctx.cursor[1]
  local cursor_col = ctx.cursor[2]

  -- Get completion items appropriate for the current context
  local items = get_completion_items(bufnr, cursor_row, cursor_col)

  -- Prepare text edit ranges
  for _, item in ipairs(items) do
    -- Get the current line text up to the cursor
    local line = ctx.line

    -- Look for the beginning of the current key we're typing
    local key_start = line:match(".*()%s+%S*$")
    if key_start then
      -- We found the beginning of the key
      item.textEdit = {
        newText = item.insertText,
        range = {
          start = { line = cursor_row - 1, character = key_start },
          ["end"] = { line = cursor_row - 1, character = cursor_col },
        },
      }
    end
  end

  callback({
    items = items,
    is_incomplete_backward = false,
    is_incomplete_forward = false,
  })

  -- Return a cancellation function
  return function() end
end

function source:resolve(item, callback)
  item = vim.deepcopy(item)

  -- If documentation is not already set, try to add some helpful info
  if not item.documentation then
    item.documentation = {
      kind = "markdown",
      value = "# " .. item.label .. "\n\nHelm value from chart configuration.",
    }
  end

  callback(item)
end

function source:execute(ctx, item, callback, default_implementation)
  -- Use default implementation for inserting the completion
  default_implementation()

  -- The callback MUST be called once
  callback()
end

return source
