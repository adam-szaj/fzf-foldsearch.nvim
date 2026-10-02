local M = {}

function M.expand(pattern, group, lines, limit)
  if type(pattern) ~= 'string' or pattern == '' then return nil, 'pattern must be a non-empty Vim regex' end
  if type(group) ~= 'number' or group < 1 or group > 9 or group % 1 ~= 0 then
    return nil, 'group number must be between 1 and 9'
  end
  if not pcall(vim.regex, pattern) then return nil, 'invalid pattern: ' .. pattern end
  if not pcall(vim.regex, pattern .. '\\' .. group) then
    return nil, 'capture group ' .. group .. ' not found'
  end

  local match_pattern = [[\C]] .. pattern
  local cache = {}
  local function captured_values(line)
    if cache[line] then return cache[line] end
    local captured = { set = {}, order = {} }
    local offset = 0
    while offset <= #line do
      local match = vim.fn.matchstrpos(line, match_pattern, offset, 1)
      if match[2] < 0 then break end
      local value = vim.fn.matchlist(line, match_pattern, offset, 1)[group + 1]
      if value and value ~= '' and not captured.set[value] then
        captured.set[value] = true
        table.insert(captured.order, value)
      end
      offset = math.max(match[3], offset + 1)
    end
    cache[line] = captured
    return captured
  end

  local values, seen = {}, {}
  for _, line in ipairs(lines) do
    for _, value in ipairs(captured_values(line).order) do
      if not seen[value] then
        seen[value] = true
        table.insert(values, value)
        if #values > limit then return nil, 'group values exceed available pattern slots (' .. limit .. ')' end
      end
    end
  end

  local patterns = {}
  for _, value in ipairs(values) do
    local captured_value = value
    table.insert(patterns, {
      label = string.format('group %d = %s in %s', group, vim.fn.string(value), pattern),
      matcher = {
        match_str = function(_, line)
          if captured_values(line).set[captured_value] then return 0 end
        end,
      },
    })
  end
  return patterns
end

return M
