local M = {}

local store = require('fzf-foldsearch.store')
local rpn = require('fzf-foldsearch.rpn')

local import_path = nil

local function resolve_file(ref_ns, relative_to_dir)
  local fname = ref_ns .. '.fl'
  local candidate = relative_to_dir .. '/' .. fname
  if vim.uv.fs_stat(candidate) then return candidate end
  if import_path then
    local expanded = vim.fn.expand(import_path) .. '/' .. fname
    if vim.uv.fs_stat(expanded) then return expanded end
  end
  return nil
end

local function namespace_of(path)
  return vim.fn.fnamemodify(path, ':t:r')
end

local function parse_entries(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, 'cannot read file "' .. path .. '"'
  end

  local entries = {}
  for lineno, source_line in ipairs(lines) do
    local line = source_line:match('^%s*(.-)%s*$')
    if line ~= '' and line:sub(1, 1) ~= '#' then
      local label, expr = line:match('^([%w_%-]+)%s*:%s*(.+)$')
      if not label then
        return nil, string.format('syntax error in "%s" line %d', path, lineno)
      end
      if not label:match('^_') then
        table.insert(entries, { label = label, expr = expr, lineno = lineno })
      end
    end
  end
  return entries
end

local pending_expr

local function import_file(path, pending, active)
  path = vim.fn.expand(path)
  local ns = namespace_of(path)
  if active[ns] then
    return false, 'circular reference detected for namespace "' .. ns .. '"'
  end
  if pending[ns] then return true end

  local entries, parse_error = parse_entries(path)
  if not entries then return false, parse_error end
  pending[ns] = entries
  active[ns] = true

  local dir = vim.fn.fnamemodify(path, ':h')
  for _, entry in ipairs(entries) do
    local parsed, tree = pcall(rpn.parse, entry.expr)
    if not parsed then
      active[ns] = nil
      return false, string.format('parse error in "%s" line %d: %s', path, entry.lineno, tostring(tree))
    end
    for _, ref in ipairs(rpn.collect_references(tree)) do
      if not pending_expr(pending, ref) then
        local ref_ns = ref:match('^([%w_%-]+)::')
        if not ref_ns then
          active[ns] = nil
          return false, string.format('unknown composition "%s" (referenced from "%s" line %d)', ref, path, entry.lineno)
        end
        if pending[ref_ns] then
          active[ns] = nil
          return false, string.format('unknown composition "%s" (referenced from "%s" line %d)', ref, path, entry.lineno)
        end
        local ref_path = resolve_file(ref_ns, dir)
        if not ref_path then
          active[ns] = nil
          return false, string.format('cannot resolve "%s.fl" (referenced from "%s" line %d)', ref_ns, path, entry.lineno)
        end
        local ok, err = import_file(ref_path, pending, active)
        if not ok then
          active[ns] = nil
          return false, err
        end
      end
    end
  end

  active[ns] = nil
  return true
end

pending_expr = function(pending, name)
  local ns, label = name:match('^([%w_%-]+)::([%w_%-]+)$')
  if ns and pending[ns] then
    for _, entry in ipairs(pending[ns]) do
      if entry.label == label then return entry.expr end
    end
    return nil
  end
  return store.get_composition_expr(name)
end

local function validate_pending(pending)
  for _, entries in pairs(pending) do
    for _, entry in ipairs(entries) do
      local ok, tree = pcall(rpn.parse, entry.expr)
      if not ok then
        return false, string.format('parse error at line %d: %s', entry.lineno, tostring(tree))
      end
      local ok2, resolved = pcall(rpn.resolve, tree, function(name)
        return pending_expr(pending, name)
      end)
      if not ok2 then
        return false, string.format('invalid expression at line %d: %s', entry.lineno, tostring(resolved))
      end
      local ok3, err = pcall(rpn.eval, resolved, {})
      if not ok3 then
        return false, string.format('invalid expression at line %d: %s', entry.lineno, tostring(err))
      end
    end
  end
  return true
end

function M.import(path)
  local pending = {}
  local ok, err = import_file(path, pending, {})
  if not ok then
    vim.notify('FuzzLogg import: ' .. err, vim.log.levels.ERROR)
    return false
  end

  local valid, validation_error = validate_pending(pending)
  if not valid then
    vim.notify('FuzzLogg import: ' .. validation_error, vim.log.levels.ERROR)
    return false
  end

  local replacements = {}
  for ns, entries in pairs(pending) do
    replacements[ns] = entries
  end
  store.replace_namespaces(replacements)
  local count = 0
  for _, entries in pairs(pending) do count = count + #entries end
  vim.notify(string.format('FuzzLogg import: loaded %d label(s) across %d namespace(s)', count, vim.tbl_count(pending)), vim.log.levels.INFO)
  return true
end

function M.setup(opts)
  opts = opts or {}
  if opts.import_path then
    import_path = opts.import_path
  end
end

return M
