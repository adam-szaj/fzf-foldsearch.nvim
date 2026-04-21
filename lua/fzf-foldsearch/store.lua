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
  decoded.patterns = decoded.patterns or {}
  decoded.compositions = decoded.compositions or {}
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
  for _, c in ipairs(data.compositions) do
    if c.name == old_name then
      c.name = new_name
      save(data)
      return true
    end
  end
  return false
end

function M.delete_composition(name)
  local data = load()
  for i, c in ipairs(data.compositions) do
    if c.name == name or (not name and not c.name and c.created_at == name) then
      table.remove(data.compositions, i)
      save(data)
      return true
    end
  end
  return false
end

function M.delete_composition_by_idx(idx)
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

function M.get_composition_expr(name)
  local data = load()
  for _, c in ipairs(data.compositions) do
    if c.name == name then
      return c.expr
    end
  end
  return nil
end

function M.clear_namespace(ns)
  local data = load()
  local kept = {}
  for _, c in ipairs(data.compositions) do
    if c.namespace ~= ns then
      table.insert(kept, c)
    end
  end
  data.compositions = kept
  save(data)
end

function M.get_by_namespace(ns)
  local data = load()
  local result = {}
  for _, c in ipairs(data.compositions) do
    if c.namespace == ns then
      table.insert(result, c)
    end
  end
  return result
end

function M.has_namespace(ns)
  local data = load()
  for _, c in ipairs(data.compositions) do
    if c.namespace == ns then return true end
  end
  return false
end

function M.save_namespaced(name, expr, ns)
  local data = load()
  for i, c in ipairs(data.compositions) do
    if c.name == name then
      data.compositions[i].expr = expr
      data.compositions[i].created_at = os.time()
      save(data)
      return
    end
  end
  table.insert(data.compositions, {
    name       = name,
    expr       = expr,
    pinned     = true,
    namespace  = ns,
    created_at = os.time(),
  })
  save(data)
end

function M.setup(opts)
  cfg = vim.tbl_deep_extend('force', cfg, opts or {})
end

return M
