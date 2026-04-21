local M = {}

local store = require('fzf-foldsearch.store')

local state = {
  bufnr = nil,
  win = nil,
}

local function buf_line_type(line)
  if line:match('^  /') or line:match('^  %S') then
    local trimmed = line:match('^%s+(.+)$')
    if trimmed then return 'pattern', trimmed end
  end
  if line:match('^  %[') then
    local name = line:match('%[pinned%]%s+(%S+)') or line:match('%[anon%]%s+(%S+)')
    local expr = line:match('%s%s(.+)$')
    return 'composition', name, expr
  end
  return nil
end

local function render(bufnr)
  local lines = { '# FuzzLogg Panel', '' }

  table.insert(lines, '## Patterns (history)')
  local patterns = store.get_patterns()
  if #patterns == 0 then
    table.insert(lines, '  (empty)')
  else
    for _, p in ipairs(patterns) do
      table.insert(lines, '  ' .. p)
    end
  end

  table.insert(lines, '')
  table.insert(lines, '## Compositions')
  local compositions = store.get_compositions()
  if #compositions == 0 then
    table.insert(lines, '  (empty)')
  else
    -- separate namespaced from anonymous/named
    local no_ns = {}
    local by_ns = {}
    local ns_order = {}
    for _, c in ipairs(compositions) do
      if c.namespace then
        if not by_ns[c.namespace] then
          by_ns[c.namespace] = {}
          table.insert(ns_order, c.namespace)
        end
        table.insert(by_ns[c.namespace], c)
      else
        table.insert(no_ns, c)
      end
    end

    for _, c in ipairs(no_ns) do
      local tag = c.pinned and '[pinned]' or '[anon]  '
      local label = c.name or os.date('%Y-%m-%d %H:%M', c.created_at)
      table.insert(lines, string.format('  %s %-24s  %s', tag, label, c.expr))
    end

    for _, ns in ipairs(ns_order) do
      table.insert(lines, '')
      table.insert(lines, '  ' .. ns .. '::')
      for _, c in ipairs(by_ns[ns]) do
        local tag = c.pinned and '[pinned]' or '[anon]  '
        local label = c.name or os.date('%Y-%m-%d %H:%M', c.created_at)
        table.insert(lines, string.format('  %s %-24s  %s', tag, label, c.expr))
      end
    end
  end

  table.insert(lines, '')
  table.insert(lines, '── Keys: <CR> load  a/x include/exclude pattern  p pin  d delete  r rename  s save session  q close ──')

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

local function setup_keymaps(bufnr)
  local fuzzlogg = require('fzf-foldsearch.fuzzlogg')
  local opts = { buffer = bufnr, nowait = true, silent = true }

  vim.keymap.set('n', 'q', function() M.panel_close() end, opts)

  vim.keymap.set('n', '<CR>', function()
    local line = vim.api.nvim_get_current_line()
    local kind, name, expr = buf_line_type(line)
    if kind == 'composition' then
      fuzzlogg.fuzzlogg_load(name or expr)
    elseif kind == 'pattern' then
      fuzzlogg.fuzzlogg_load('/' .. name .. '/')
    end
  end, opts)

  vim.keymap.set('n', 'a', function()
    local line = vim.api.nvim_get_current_line()
    local kind, name = buf_line_type(line)
    if kind == 'pattern' then
      -- add to active session as inclusive via direct call
      local fl = require('fzf-foldsearch.fuzzlogg')
      fl._add_pattern_direct(name, true)
      render(bufnr)
    end
  end, opts)

  vim.keymap.set('n', 'x', function()
    local line = vim.api.nvim_get_current_line()
    local kind, name = buf_line_type(line)
    if kind == 'pattern' then
      local fl = require('fzf-foldsearch.fuzzlogg')
      fl._add_pattern_direct(name, false)
      render(bufnr)
    end
  end, opts)

  vim.keymap.set('n', 'p', function()
    local line = vim.api.nvim_get_current_line()
    local kind, name = buf_line_type(line)
    if kind == 'composition' and name then
      local comps = store.get_compositions()
      for _, c in ipairs(comps) do
        if c.name == name then
          store.pin_composition(name, not c.pinned)
          break
        end
      end
      render(bufnr)
    end
  end, opts)

  vim.keymap.set('n', 'd', function()
    local line = vim.api.nvim_get_current_line()
    local kind, name = buf_line_type(line)
    if kind == 'composition' then
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local comp_start = 0
      local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i, l in ipairs(all_lines) do
        if l == '## Compositions' then comp_start = i; break end
      end
      local idx = row - comp_start - 1
      store.delete_composition_by_idx(idx)
      render(bufnr)
    end
  end, opts)

  vim.keymap.set('n', 'r', function()
    local line = vim.api.nvim_get_current_line()
    local kind, name = buf_line_type(line)
    if kind == 'composition' and name then
      vim.ui.input({ prompt = 'Rename to: ', default = name }, function(input)
        if input and input ~= '' then
          store.rename_composition(name, input)
          render(bufnr)
        end
      end)
    end
  end, opts)

  vim.keymap.set('n', 's', function()
    local fl = require('fzf-foldsearch.fuzzlogg')
    fl.fuzzlogg_save(nil)
    vim.defer_fn(function() render(bufnr) end, 200)
  end, opts)
end

function M.panel_open()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    else
      vim.cmd('split')
      state.win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(state.win, state.bufnr)
    end
    render(state.bufnr)
    return
  end

  vim.cmd('split')
  state.win = vim.api.nvim_get_current_win()
  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.bufnr)

  vim.bo[state.bufnr].buftype = 'nofile'
  vim.bo[state.bufnr].bufhidden = 'wipe'
  vim.bo[state.bufnr].swapfile = false
  vim.bo[state.bufnr].modifiable = false
  pcall(vim.api.nvim_buf_set_name, state.bufnr, 'fuzzlogg://panel')

  render(state.bufnr)
  setup_keymaps(state.bufnr)

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.bufnr,
    once = true,
    callback = function()
      state.bufnr = nil
      state.win = nil
    end,
  })
end

function M.panel_close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

function M.panel_refresh()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    render(state.bufnr)
  end
end

return M
