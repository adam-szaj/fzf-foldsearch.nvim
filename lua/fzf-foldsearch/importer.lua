local M = {}

local store = require('fzf-foldsearch.store')
local rpn   = require('fzf-foldsearch.rpn')

local import_path = nil  -- set by M.setup()

local function resolve_file(ref_ns, relative_to_dir)
  local fname = ref_ns .. '.fl'
  -- 1. relative to importing file
  local candidate = relative_to_dir .. '/' .. fname
  if vim.uv.fs_stat(candidate) then return candidate end
  -- 2. global import_path
  if import_path then
    local expanded = vim.fn.expand(import_path) .. '/' .. fname
    if vim.uv.fs_stat(expanded) then return expanded end
  end
  return nil
end

local function namespace_of(path)
  return vim.fn.fnamemodify(path, ':t:r')
end

local function collect_refs(expr)
  local refs = {}
  for token in expr:gmatch('%S+') do
    if token:match('^([%w_%-]+)::[%w_%-]+$') then
      local ns = token:match('^([%w_%-]+)::')
      refs[ns] = true
    end
  end
  return refs
end

-- Forward declaration for recursion
local import_file

import_file = function(path, importing_stack)
  path = vim.fn.expand(path)
  importing_stack = importing_stack or {}

  local ns = namespace_of(path)

  if importing_stack[ns] then
    vim.notify('FuzzLogg import: circular reference detected for "' .. ns .. '"', vim.log.levels.ERROR)
    return false
  end

  local dir = vim.fn.fnamemodify(path, ':h')
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    vim.notify('FuzzLogg import: cannot read file "' .. path .. '"', vim.log.levels.ERROR)
    return false
  end

  -- Parse lines first, collect all refs for auto-resolve before touching store
  local entries = {}
  for lineno, line in ipairs(lines) do
    line = line:gsub('#.*$', ''):match('^%s*(.-)%s*$')  -- strip comments + trim
    if line == '' then goto continue end

    local label, expr = line:match('^([%w_%-]+)%s*:%s*(.+)$')
    if not label then
      vim.notify(string.format('FuzzLogg import: syntax error in "%s" line %d', path, lineno), vim.log.levels.ERROR)
      return false
    end

    if not label:match('^_') then
      table.insert(entries, { label = label, expr = expr, lineno = lineno })
    end

    ::continue::
  end

  -- Auto-resolve referenced namespaces
  local new_stack = vim.tbl_extend('force', importing_stack, { [ns] = true })
  for _, entry in ipairs(entries) do
    local refs = collect_refs(entry.expr)
    for ref_ns, _ in pairs(refs) do
      if not store.has_namespace(ref_ns) then
        local ref_path = resolve_file(ref_ns, dir)
        if not ref_path then
          vim.notify(string.format(
            'FuzzLogg import: cannot resolve "%s.fl" (referenced from "%s" line %d)',
            ref_ns, path, entry.lineno
          ), vim.log.levels.ERROR)
          return false
        end
        local ok2 = import_file(ref_path, new_stack)
        if not ok2 then return false end
      end
    end
  end

  -- Validate all expressions before touching store
  for _, entry in ipairs(entries) do
    local ok2, err = pcall(rpn.parse, entry.expr)
    if not ok2 then
      vim.notify(string.format(
        'FuzzLogg import: parse error in "%s" line %d: %s',
        path, entry.lineno, tostring(err)
      ), vim.log.levels.ERROR)
      return false
    end
  end

  -- All good — clear namespace and write entries
  store.clear_namespace(ns)
  for _, entry in ipairs(entries) do
    store.save_namespaced(ns .. '::' .. entry.label, entry.expr, ns)
  end

  vim.notify(string.format(
    'FuzzLogg import: "%s" — %d label(s) loaded', ns, #entries
  ), vim.log.levels.INFO)

  return true
end

function M.import(path)
  return import_file(path, {})
end

function M.setup(opts)
  opts = opts or {}
  if opts.import_path then
    import_path = opts.import_path
  end
end

return M
