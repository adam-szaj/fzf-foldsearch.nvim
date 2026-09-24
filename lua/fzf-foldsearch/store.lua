local M = {}

local cfg = { max_anon = 20 }

local function store_path()
  return vim.fn.stdpath('data') .. '/fuzzlogg/store.json'
end

local function load()
  local path = store_path()
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data or #data == 0 then
    return { patterns = {}, compositions = {} }
  end
  local ok2, decoded = pcall(vim.fn.json_decode, table.concat(data, '\n'))
  if not ok2 or type(decoded) ~= 'table' then
    return { patterns = {}, compositions = {} }
  end
  if type(decoded.patterns) ~= 'table' then decoded.patterns = {} end
  if type(decoded.compositions) ~= 'table' then decoded.compositions = {} end
  return decoded
end

local function save(data)
  local path = store_path()
  local dir = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(dir, 'p')
  local ok, encoded = pcall(vim.fn.json_encode, data)
  if not ok then return end
  vim.fn.writefile({ encoded }, path)
end

function M.add_pattern(pattern)
  local data = load()
  for i, p in ipairs(data.patterns) do
    if p == pattern then
      table.remove(data.patterns, i)
      break
    end
  end
  table.insert(data.patterns, pattern)
  save(data)
end

function M.get_patterns()
  local data = load()
  local result = {}
  for i = #data.patterns, 1, -1 do
    table.insert(result, data.patterns[i])
  end
  return result
end

function M.save_composition(name, expr)
  local data = load()

  if name then
    for i, c in ipairs(data.compositions) do
      if c.name == name then
        data.compositions[i].expr = expr
        data.compositions[i].created_at = os.time()
        save(data)
        return
      end
    end
  end

  table.insert(data.compositions, {
    name = name,
    expr = expr,
    pinned = false,
    created_at = os.time(),
  })

  if not name then
    local anon_count = 0
    local oldest_i = nil
    local oldest_t = math.huge
    for i, c in ipairs(data.compositions) do
      if not c.name and not c.pinned then
        anon_count = anon_count + 1
        if c.created_at < oldest_t then
          oldest_t = c.created_at
          oldest_i = i
        end
      end
    end
    if anon_count > cfg.max_anon and oldest_i then
      table.remove(data.compositions, oldest_i)
    end
  end

  save(data)
end

function M.rename_composition(old_name, new_name)
  local data = load()
  for i, c in ipairs(data.compositions) do
    if c.name == old_name then
      return M.rename_composition_by_idx(i, new_name)
    end
  end
  return false
end

function M.delete_composition(name)
  if not name then return false end
  local data = load()
  for i, c in ipairs(data.compositions) do
    if c.name == name then
      table.remove(data.compositions, i)
      save(data)
      return true
    end
  end
  return false
end

function M.delete_composition_by_idx(idx)
  if type(idx) ~= 'number' or idx < 1 or idx % 1 ~= 0 then return false end
  local data = load()
  if data.compositions[idx] then
    table.remove(data.compositions, idx)
    save(data)
    return true
  end
  return false
end

function M.get_compositions()
  local data = load()
  return data.compositions
end

function M.pin_composition(name, pinned)
  if not name then return false end
  local data = load()
  for _, c in ipairs(data.compositions) do
    if c.name == name then
      c.pinned = (pinned ~= false)
      save(data)
      return true
    end
  end
  return false
end

function M.pin_composition_by_idx(idx, pinned)
  if type(idx) ~= 'number' or idx < 1 or idx % 1 ~= 0 then return false end
  local data = load()
  local composition = data.compositions[idx]
  if not composition then return false end
  composition.pinned = (pinned ~= false)
  save(data)
  return true
end

function M.rename_composition_by_idx(idx, new_name)
  if type(idx) ~= 'number' or idx < 1 or idx % 1 ~= 0 or not new_name or new_name == '' then
    return false
  end
  local data = load()
  local composition = data.compositions[idx]
  if not composition then return false end
  if composition.namespace then
    local ns = composition.namespace
    local label = new_name:match('^' .. vim.pesc(ns) .. '::([%w_%-]+)$') or new_name
    if not label:match('^[%w_%-]+$') then return false end
    new_name = ns .. '::' .. label
  end
  for i, other in ipairs(data.compositions) do
    if i ~= idx and other.name == new_name then return false end
  end
  composition.name = new_name
  save(data)
  return true
end

function M.get_composition_expr(name)
  if type(name) ~= 'string' or name == '' then return nil end
  local data = load()
  for _, c in ipairs(data.compositions) do
    if c.name == name then
      return c.expr
    end
  end
  return nil
end

function M.replace_namespaces(namespaces)
  local data = load()
  local replaced = {}
  for ns in pairs(namespaces) do
    replaced[ns] = true
  end
  local kept = {}
  for _, composition in ipairs(data.compositions) do
    if not replaced[composition.namespace] then
      table.insert(kept, composition)
    end
  end
  data.compositions = kept

  for ns, entries in pairs(namespaces) do
    for _, entry in ipairs(entries) do
      table.insert(data.compositions, {
        name = ns .. '::' .. entry.label,
        expr = entry.expr,
        pinned = true,
        namespace = ns,
        created_at = os.time(),
      })
    end
  end
  save(data)
end

function M.setup(opts)
  cfg = vim.tbl_deep_extend('force', cfg, opts or {})
end

return M
