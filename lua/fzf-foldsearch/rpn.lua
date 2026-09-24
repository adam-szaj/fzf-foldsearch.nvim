local M = {}

local BINARY_OPS = { ['|'] = true, ['&'] = true, ['-'] = true }
local UNARY_OPS = { ['~'] = true }
local MAX_TREE_DEPTH = 128
local MAX_REFERENCE_DEPTH = 5

local function tokenize(expr)
  local tokens = {}
  local i = 1

  while i <= #expr do
    while i <= #expr and expr:sub(i, i):match('%s') do
      i = i + 1
    end
    if i > #expr then break end

    local char = expr:sub(i, i)
    if char == '(' or char == ')' then
      table.insert(tokens, char)
      i = i + 1
    elseif char == '/' then
      local start = i
      i = i + 1
      local backslashes = 0
      local closed = false
      while i <= #expr do
        local char = expr:sub(i, i)
        if char == '/' and backslashes % 2 == 0 then
          i = i + 1
          closed = true
          break
        end
        if char == '\\' then
          backslashes = backslashes + 1
        else
          backslashes = 0
        end
        i = i + 1
      end
      if not closed then
        error('RPN: unterminated /pattern/ atom')
      end
      table.insert(tokens, expr:sub(start, i - 1))
    else
      local start = i
      while i <= #expr and not expr:sub(i, i):match('[%s()]') do
        i = i + 1
      end
      table.insert(tokens, expr:sub(start, i - 1))
    end
  end

  return tokens
end

local function tree_depth(node)
  if node.type then return 1 end
  if node.op == '~' then
    return 1 + tree_depth(node.operand)
  end
  return 1 + math.max(tree_depth(node.left), tree_depth(node.right))
end

local function pattern_node(pattern)
  return { type = 'pattern', value = pattern }
end

local function operation_node(op, left, right)
  if op == '~' then
    return { op = op, operand = left }
  end
  return { op = op, left = left, right = right }
end

function M.parse(expr)
  local tokens = tokenize(expr)
  local stack = {}

  for _, token in ipairs(tokens) do
    if token ~= '(' and token ~= ')' then
      if BINARY_OPS[token] then
        if #stack < 2 then
          error('RPN: not enough operands for "' .. token .. '"')
        end
        local right = table.remove(stack)
        local left = table.remove(stack)
        local node = operation_node(token, left, right)
        if tree_depth(node) > MAX_TREE_DEPTH then
          error('RPN: max expression depth (' .. MAX_TREE_DEPTH .. ') exceeded')
        end
        table.insert(stack, node)
      elseif UNARY_OPS[token] then
        if #stack < 1 then
          error('RPN: not enough operands for "~"')
        end
        local node = operation_node('~', table.remove(stack))
        if tree_depth(node) > MAX_TREE_DEPTH then
          error('RPN: max expression depth (' .. MAX_TREE_DEPTH .. ') exceeded')
        end
        table.insert(stack, node)
      elseif token:match('^/.*/$') then
        table.insert(stack, pattern_node(token:sub(2, -2)))
      elseif token == '@empty' then
        table.insert(stack, { type = 'empty' })
      elseif token:match('^[%w_%-]+::[%w_%-]+$') or token:match('^[%w_%-]+$') then
        table.insert(stack, { type = 'ref', name = token })
      else
        error('RPN: unrecognized token "' .. token .. '"')
      end
    end
  end

  if #stack ~= 1 then
    error('RPN: expression leaves ' .. #stack .. ' values on stack (expected 1)')
  end
  return stack[1]
end

function M.resolve(tree, get_comp, active, depth)
  active = active or {}
  depth = depth or 0
  if depth > MAX_REFERENCE_DEPTH then
    error('RPN: max composition reference depth (' .. MAX_REFERENCE_DEPTH .. ') exceeded')
  end

  if tree.type == 'pattern' then
    return pattern_node(tree.value)
  end
  if tree.type == 'empty' then
    return { type = 'empty' }
  end
  if tree.type == 'ref' then
    if active[tree.name] then
      error('RPN: circular composition reference "' .. tree.name .. '"')
    end
    local expr = get_comp and get_comp(tree.name)
    if not expr then
      error('RPN: unknown composition "' .. tree.name .. '"')
    end
    active[tree.name] = true
    local ok, resolved = pcall(M.resolve, M.parse(expr), get_comp, active, depth + 1)
    active[tree.name] = nil
    if not ok then error(resolved) end
    return resolved
  end
  if tree.op == '~' then
    return operation_node('~', M.resolve(tree.operand, get_comp, active, depth))
  end
  return operation_node(tree.op,
    M.resolve(tree.left, get_comp, active, depth),
    M.resolve(tree.right, get_comp, active, depth))
end

local function match_set(lines, pattern, regex_cache)
  local re = regex_cache and regex_cache[pattern]
  if not re then
    local ok
    ok, re = pcall(vim.regex, pattern)
    if not ok then
      error('invalid pattern: ' .. pattern)
    end
    if regex_cache then regex_cache[pattern] = re end
  end
  local set = {}
  for i, line in ipairs(lines) do
    if re:match_str(line) then
      set[i] = true
    end
  end
  return set
end

local function set_union(a, b)
  local result = {}
  for k in pairs(a) do result[k] = true end
  for k in pairs(b) do result[k] = true end
  return result
end

local function set_intersect(a, b)
  local result = {}
  for k in pairs(a) do
    if b[k] then result[k] = true end
  end
  return result
end

local function set_diff(a, b)
  local result = {}
  for k in pairs(a) do
    if not b[k] then result[k] = true end
  end
  return result
end

local function set_complement(a, total)
  local result = {}
  for i = 1, total do
    if not a[i] then result[i] = true end
  end
  return result
end

local function eval_resolved(tree, lines, depth, regex_cache)
  depth = depth or 0
  if depth > MAX_TREE_DEPTH then
    error('RPN: max evaluation depth (' .. MAX_TREE_DEPTH .. ') exceeded')
  end
  if tree.type == 'pattern' then
    return match_set(lines, tree.value, regex_cache)
  end
  if tree.type == 'empty' then
    return {}
  end
  if tree.op == '~' then
    return set_complement(eval_resolved(tree.operand, lines, depth + 1, regex_cache), #lines)
  end

  local left = eval_resolved(tree.left, lines, depth + 1, regex_cache)
  local right = eval_resolved(tree.right, lines, depth + 1, regex_cache)
  if tree.op == '|' then return set_union(left, right) end
  if tree.op == '&' then return set_intersect(left, right) end
  if tree.op == '-' then return set_diff(left, right) end
  error('RPN: unknown op "' .. tostring(tree.op) .. '"')
end

function M.eval(tree, lines, get_comp, regex_cache)
  local resolved = M.resolve(tree, get_comp)
  return eval_resolved(resolved, lines, nil, regex_cache)
end

function M.collect_patterns(tree)
  local patterns = {}
  local seen = {}
  local function visit(node)
    if node.type == 'pattern' then
      if not seen[node.value] then
        seen[node.value] = true
        table.insert(patterns, node.value)
      end
    elseif node.type == 'empty' then
      return
    elseif node.op == '~' then
      visit(node.operand)
    else
      visit(node.left)
      visit(node.right)
    end
  end
  visit(tree)
  return patterns
end

function M.collect_references(tree)
  local refs = {}
  local seen = {}
  local function visit(node)
    if node.type == 'ref' then
      if not seen[node.name] then
        seen[node.name] = true
        table.insert(refs, node.name)
      end
    elseif node.type == 'pattern' or node.type == 'empty' then
      return
    elseif node.op == '~' then
      visit(node.operand)
    else
      visit(node.left)
      visit(node.right)
    end
  end
  visit(tree)
  return refs
end

local function quote_pattern(pattern)
  local result = {}
  local backslashes = 0
  for i = 1, #pattern do
    local char = pattern:sub(i, i)
    if char == '/' and backslashes % 2 == 0 then
      table.insert(result, '\\/')
    else
      table.insert(result, char)
    end
    if char == '\\' then
      backslashes = backslashes + 1
    else
      backslashes = 0
    end
  end
  return '/' .. table.concat(result) .. '/'
end

function M.serialize(tree)
  local tokens = {}
  local function visit(node)
    if node.type == 'pattern' then
      table.insert(tokens, quote_pattern(node.value))
    elseif node.type == 'empty' then
      table.insert(tokens, '@empty')
    elseif node.type == 'ref' then
      table.insert(tokens, node.name)
    elseif node.op == '~' then
      visit(node.operand)
      table.insert(tokens, '~')
    else
      visit(node.left)
      visit(node.right)
      table.insert(tokens, node.op)
    end
  end
  visit(tree)
  return table.concat(tokens, ' ')
end

return M
