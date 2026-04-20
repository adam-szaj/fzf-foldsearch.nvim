local M = {}

local BINARY_OPS = { ['|'] = true, ['&'] = true, ['-'] = true }
local UNARY_OPS  = { ['~'] = true }

local function tokenize(expr)
  local tokens = {}
  for token in expr:gmatch('%S+') do
    if token ~= '(' and token ~= ')' then
      table.insert(tokens, token)
    end
  end
  return tokens
end

local function tree_depth(node)
  if not node then return 0 end
  if node.type then return 1 end  -- atom
  if node.op == '~' then
    return 1 + tree_depth(node.operand)
  end
  return 1 + math.max(tree_depth(node.left), tree_depth(node.right))
end

function M.parse(expr)
  local tokens = tokenize(expr)
  local stack = {}

  for _, token in ipairs(tokens) do
    if BINARY_OPS[token] then
      if #stack < 2 then
        error('RPN: not enough operands for "' .. token .. '"')
      end
      local right = table.remove(stack)
      local left  = table.remove(stack)
      local node = { op = token, left = left, right = right }
      if tree_depth(node) > 5 then
        error('RPN: max depth (5) exceeded')
      end
      table.insert(stack, node)
    elseif UNARY_OPS[token] then
      if #stack < 1 then
        error('RPN: not enough operands for "~"')
      end
      local operand = table.remove(stack)
      local node = { op = '~', operand = operand }
      if tree_depth(node) > 5 then
        error('RPN: max depth (5) exceeded')
      end
      table.insert(stack, node)
    elseif token:match('^/.*/$') then
      local pattern = token:sub(2, -2)
      table.insert(stack, { type = 'pattern', value = pattern })
    else
      table.insert(stack, { type = 'ref', name = token })
    end
  end

  if #stack ~= 1 then
    error('RPN: expression leaves ' .. #stack .. ' values on stack (expected 1)')
  end
  return stack[1]
end

local function match_set(lines, pattern)
  local ok, re = pcall(vim.regex, pattern)
  if not ok then
    error('invalid pattern: ' .. pattern)
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

function M.eval(tree, lines, get_comp, depth)
  depth = depth or 0
  if depth > 5 then
    error('RPN: max eval depth (5) exceeded')
  end

  if tree.type == 'pattern' then
    return match_set(lines, tree.value)
  end

  if tree.type == 'ref' then
    local expr = get_comp(tree.name)
    if not expr then
      error('RPN: unknown composition "' .. tree.name .. '"')
    end
    local subtree = M.parse(expr)
    return M.eval(subtree, lines, get_comp, depth + 1)
  end

  if tree.op == '~' then
    local operand_set = M.eval(tree.operand, lines, get_comp, depth + 1)
    return set_complement(operand_set, #lines)
  end

  local left_set  = M.eval(tree.left,  lines, get_comp, depth + 1)
  local right_set = M.eval(tree.right, lines, get_comp, depth + 1)

  if tree.op == '|' then return set_union(left_set, right_set) end
  if tree.op == '&' then return set_intersect(left_set, right_set) end
  if tree.op == '-' then return set_diff(left_set, right_set) end

  error('RPN: unknown op "' .. tostring(tree.op) .. '"')
end

function M.collect_patterns(tree)
  if tree.type == 'pattern' then
    return { tree.value }
  end
  if tree.type == 'ref' then
    return {}
  end
  if tree.op == '~' then
    return M.collect_patterns(tree.operand)
  end
  local result = {}
  for _, p in ipairs(M.collect_patterns(tree.left)) do
    table.insert(result, p)
  end
  for _, p in ipairs(M.collect_patterns(tree.right)) do
    table.insert(result, p)
  end
  return result
end

return M
