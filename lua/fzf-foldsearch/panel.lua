local M = {}

local store = require('fzf-foldsearch.store')

local state = {
  bufnr = nil,
  win = nil,
  source_win = nil,
  row_actions = {},
}

local function render(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local lines = { '# FuzzLogg Panel', '' }
  local row_actions = {}
  local function add_line(line, action)
    table.insert(lines, line)
    if action then row_actions[#lines] = action end
  end

  add_line('## Patterns (history)')
  local patterns = store.get_patterns()
  if #patterns == 0 then
    add_line('  (empty)')
  else
    for _, pattern in ipairs(patterns) do
      add_line('  ' .. pattern, { kind = 'pattern', pattern = pattern })
    end
  end

  add_line('')
  add_line('## Compositions')
  local compositions = store.get_compositions()
  if #compositions == 0 then
    add_line('  (empty)')
  else
    local no_ns = {}
    local by_ns = {}
    local ns_order = {}
    for index, composition in ipairs(compositions) do
      local item = { composition = composition, index = index }
      if composition.namespace then
        if not by_ns[composition.namespace] then
          by_ns[composition.namespace] = {}
          table.insert(ns_order, composition.namespace)
        end
        table.insert(by_ns[composition.namespace], item)
      else
        table.insert(no_ns, item)
      end
    end

    local function add_composition(item)
      local composition = item.composition
      local tag = composition.pinned and '[pinned]' or '[anon]  '
      local label = composition.name or os.date('%Y-%m-%d %H:%M', composition.created_at)
      add_line(string.format('  %s %-24s  %s', tag, label, composition.expr), {
        kind = 'composition',
        composition = composition,
        index = item.index,
      })
    end

    for _, item in ipairs(no_ns) do
      add_composition(item)
    end
    for _, ns in ipairs(ns_order) do
      add_line('')
      add_line('  ' .. ns .. '::')
      for _, item in ipairs(by_ns[ns]) do
        add_composition(item)
      end
    end
  end

  add_line('')
  add_line('── Keys: <CR> load  a/x include/exclude pattern  p pin  d delete  r rename  s save session  q close ──')

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  state.row_actions = row_actions
end

local function setup_keymaps(bufnr)
  local fuzzlogg = require('fzf-foldsearch.fuzzlogg')
  local opts = { buffer = bufnr, nowait = true, silent = true }
  local function ensure_session()
    return fuzzlogg.ensure_open(state.source_win)
  end
  local function current_action()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    return state.row_actions[row]
  end

  vim.keymap.set('n', 'q', function() M.panel_close() end, opts)

  vim.keymap.set('n', '<CR>', function()
    local action = current_action()
    if not action then return end
    if not ensure_session() then return end
    if action.kind == 'composition' then
      local composition = action.composition
      fuzzlogg.fuzzlogg_load(composition.name or composition.expr)
    elseif action.kind == 'pattern' then
      fuzzlogg.fuzzlogg_load_pattern(action.pattern)
    end
    render(bufnr)
  end, opts)

  vim.keymap.set('n', 'a', function()
    local action = current_action()
    if action and action.kind == 'pattern' then
      if not ensure_session() then return end
      fuzzlogg._add_pattern_direct(action.pattern, true)
      render(bufnr)
    end
  end, opts)

  vim.keymap.set('n', 'x', function()
    local action = current_action()
    if action and action.kind == 'pattern' then
      if not ensure_session() then return end
      fuzzlogg._add_pattern_direct(action.pattern, false)
      render(bufnr)
    end
  end, opts)

  vim.keymap.set('n', 'p', function()
    local action = current_action()
    if action and action.kind == 'composition' then
      store.pin_composition_by_idx(action.index, not action.composition.pinned)
      render(bufnr)
    end
  end, opts)

  vim.keymap.set('n', 'd', function()
    local action = current_action()
    if action and action.kind == 'composition' then
      store.delete_composition_by_idx(action.index)
      render(bufnr)
    end
  end, opts)

  vim.keymap.set('n', 'r', function()
    local action = current_action()
    if action and action.kind == 'composition' then
      local default = action.composition.name or os.date('%Y-%m-%d %H:%M', action.composition.created_at)
      vim.ui.input({ prompt = 'Rename to: ', default = default }, function(input)
        if input and input ~= '' then
          store.rename_composition_by_idx(action.index, input)
          render(bufnr)
        end
      end)
    end
  end, opts)

  vim.keymap.set('n', 's', function()
    if not ensure_session() then return end
    fuzzlogg.fuzzlogg_save(nil, function() render(bufnr) end)
  end, opts)
end

function M.panel_open()
  local current_win = vim.api.nvim_get_current_win()
  if current_win ~= state.win then
    state.source_win = require('fzf-foldsearch.fuzzlogg').source_window() or current_win
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.b[state.bufnr].fuzzlogg_source_win = state.source_win
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
  vim.b[state.bufnr].fuzzlogg_source_win = state.source_win
  pcall(vim.api.nvim_buf_set_name, state.bufnr, 'fuzzlogg://panel')

  render(state.bufnr)
  setup_keymaps(state.bufnr)

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.bufnr,
    once = true,
    callback = function()
      state.bufnr = nil
      state.win = nil
      state.source_win = nil
      state.row_actions = {}
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
