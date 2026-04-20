local M = {}

local store = require('fzf-foldsearch.store')
local rpn   = require('fzf-foldsearch.rpn')

local config = {
  layout = 'vsplit',
  context = 0,
  debounce_ms = 100,
  max_patterns = 8,
  colors = {
    '#3d59a1', '#2ac3de', '#7aa2f7', '#bb9af7',
    '#394b70', '#0db9d7', '#9d7cd8', '#2d4f67',
  },
}

local ns_linenum = vim.api.nvim_create_namespace('fuzzlogg_linenum')

local state = {
  active = false,
  src_bufnr = nil,
  res_bufnr = nil,
  src_win = nil,
  res_win = nil,
  patterns = {},
  context = 0,
  line_map = {},
  src_map = {},
  timer = nil,
  autocmds = {},
}

local function reset_state()
  if state.timer then
    state.timer:stop()
    state.timer:close()
  end
  for _, id in ipairs(state.autocmds) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  state.active = false
  state.src_bufnr = nil
  state.res_bufnr = nil
  state.src_win = nil
  state.res_win = nil
  state.patterns = {}
  state.context = config.context
  state.line_map = {}
  state.src_map = {}
  state.timer = nil
  state.autocmds = {}
end

local function compute_lines(src_lines, patterns, context)
  if #patterns == 0 then
    return {}, {}, {}, {}, {}
  end

  local matched = {}
  for i, line in ipairs(src_lines) do
    matched[i] = {}
    for j, p in ipairs(patterns) do
      if p.re:match_str(line) then
        matched[i][j] = true
      end
    end
  end

  local visible_by = {}
  for i = 1, #src_lines do
    local inc_match = false
    local exc_match = false
    local first_pat = nil
    for j, p in ipairs(patterns) do
      if matched[i][j] then
        if p.inclusive then
          inc_match = true
          if not first_pat then first_pat = j end
        else
          exc_match = true
        end
      end
    end
    if inc_match and not exc_match then
      visible_by[i] = first_pat
    end
  end

  if context > 0 then
    local ctx_visible_by = {}
    for i = 1, #src_lines do
      if visible_by[i] then
        local pat_idx = visible_by[i]
        for c = math.max(1, i - context), math.min(#src_lines, i + context) do
          if not ctx_visible_by[c] then
            ctx_visible_by[c] = pat_idx
          end
        end
      end
    end
    visible_by = ctx_visible_by
  end

  local res_lines = {}
  local line_map = {}
  local src_map = {}
  for i = 1, #src_lines do
    if visible_by[i] then
      local res_i = #res_lines + 1
      table.insert(res_lines, src_lines[i])
      line_map[res_i] = i
      if not src_map[i] then
        src_map[i] = res_i
      end
    end
  end

  return res_lines, line_map, src_map, matched, visible_by
end

local function render()
  if not state.active then return end
  if not vim.api.nvim_buf_is_valid(state.src_bufnr) then return end
  if not vim.api.nvim_buf_is_valid(state.res_bufnr) then return end

  local src_lines = vim.api.nvim_buf_get_lines(state.src_bufnr, 0, -1, false)
  local res_lines, line_map, src_map, _, visible_by =
    compute_lines(src_lines, state.patterns, state.context)

  vim.bo[state.res_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.res_bufnr, 0, -1, false, res_lines)
  vim.bo[state.res_bufnr].modifiable = false

  state.line_map = line_map
  state.src_map = src_map

  for _, p in ipairs(state.patterns) do
    vim.api.nvim_buf_clear_namespace(state.res_bufnr, p.ns_id, 0, -1)
    vim.api.nvim_buf_clear_namespace(state.src_bufnr, p.ns_id, 0, -1)
  end

  for res_i, src_i in pairs(line_map) do
    local pat_idx = visible_by[src_i]
    if pat_idx then
      local p = state.patterns[pat_idx]
      vim.api.nvim_buf_add_highlight(state.res_bufnr, p.ns_id, p.hl_group, res_i - 1, 0, -1)
    end
  end

  for src_i, _ in pairs(src_map) do
    local pat_idx = visible_by[src_i]
    if pat_idx then
      local p = state.patterns[pat_idx]
      vim.api.nvim_buf_add_highlight(state.src_bufnr, p.ns_id, p.hl_group, src_i - 1, 0, -1)
    end
  end

  vim.api.nvim_buf_clear_namespace(state.res_bufnr, ns_linenum, 0, -1)
  local total = vim.api.nvim_buf_line_count(state.src_bufnr)
  local width = #tostring(total)
  for res_i, src_i in pairs(line_map) do
    vim.api.nvim_buf_set_extmark(state.res_bufnr, ns_linenum, res_i - 1, 0, {
      virt_text = { { string.format('%' .. width .. 'd │ ', src_i), 'LineNr' } },
      virt_text_pos = 'inline',
    })
  end
end

local function schedule_render()
  if not state.timer then
    state.timer = vim.uv.new_timer()
  else
    state.timer:stop()
  end
  state.timer:start(config.debounce_ms, 0, vim.schedule_wrap(render))
end

local function open_layout()
  state.src_win = vim.api.nvim_get_current_win()

  if config.layout == 'same_window' then
    state.res_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(state.src_win, state.res_bufnr)
    state.res_win = state.src_win
  elseif config.layout == 'split' then
    vim.cmd('new')
    state.res_win = vim.api.nvim_get_current_win()
    state.res_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(state.res_win, state.res_bufnr)
  else
    vim.cmd('vnew')
    state.res_win = vim.api.nvim_get_current_win()
    state.res_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(state.res_win, state.res_bufnr)
  end

  vim.bo[state.res_bufnr].buftype = 'nofile'
  vim.bo[state.res_bufnr].bufhidden = 'wipe'
  vim.bo[state.res_bufnr].swapfile = false
  vim.bo[state.res_bufnr].modifiable = false
  pcall(vim.api.nvim_buf_set_name, state.res_bufnr, 'fuzzlogg://results:' .. os.time())

  vim.keymap.set('n', '<CR>', function() M.fuzzlogg_jump_to_source() end,
    { buffer = state.res_bufnr, desc = 'FuzzLogg: jump to source' })
end

local function setup_autocmds()
  local id = vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = state.src_bufnr,
    callback = function()
      if state.active then schedule_render() end
    end,
  })
  table.insert(state.autocmds, id)

  id = vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = state.res_bufnr,
    once = true,
    callback = function()
      if state.active then M.fuzzlogg_close() end
    end,
  })
  table.insert(state.autocmds, id)

  id = vim.api.nvim_create_autocmd('BufDelete', {
    buffer = state.src_bufnr,
    once = true,
    callback = function()
      if state.active then M.fuzzlogg_close() end
    end,
  })
  table.insert(state.autocmds, id)
end

local function build_expr()
  local parts = {}
  for i, p in ipairs(state.patterns) do
    table.insert(parts, '/' .. p.pattern .. '/')
    if not p.inclusive then
      table.insert(parts, '~')
    end
    if i > 1 then
      table.insert(parts, '|')
    end
  end
  return table.concat(parts, ' ')
end

local function auto_save()
  if not state.active or #state.patterns == 0 then return end
  store.save_composition(nil, build_expr())
end

local function add_pattern(pattern, inclusive)
  if #state.patterns >= config.max_patterns then
    vim.notify('FuzzLogg: max patterns reached (' .. config.max_patterns .. ')', vim.log.levels.WARN)
    return
  end

  local ok, re = pcall(vim.regex, pattern)
  if not ok then
    vim.notify('FuzzLogg: invalid pattern: ' .. pattern, vim.log.levels.ERROR)
    return
  end

  local idx = #state.patterns + 1
  local color = config.colors[((idx - 1) % #config.colors) + 1]
  local hl_group = 'FuzzLoggPat' .. idx
  local ns_id = vim.api.nvim_create_namespace('fuzzlogg_' .. idx .. '_' .. os.time())

  vim.api.nvim_set_hl(0, hl_group, { fg = color, bold = true })

  table.insert(state.patterns, {
    pattern = pattern,
    inclusive = inclusive,
    re = re,
    ns_id = ns_id,
    hl_group = hl_group,
    color = color,
  })

  store.add_pattern(pattern)

  local kind = inclusive and 'include' or 'exclude'
  vim.notify(string.format('FuzzLogg: pattern %d [%s] %s', idx, kind, pattern), vim.log.levels.INFO)

  schedule_render()
  auto_save()
end

function M.fuzzlogg_open()
  if state.active then
    vim.notify('FuzzLogg: already active, close first with fuzzlogg_close()', vim.log.levels.WARN)
    return
  end

  state.context = config.context
  state.src_bufnr = vim.api.nvim_get_current_buf()

  open_layout()
  setup_autocmds()

  state.active = true
  vim.notify('FuzzLogg: opened. Add patterns with fuzzlogg_add()', vim.log.levels.INFO)
end

function M.fuzzlogg_add(inclusive)
  if not state.active then
    vim.notify('FuzzLogg: not active, open first with fuzzlogg_open()', vim.log.levels.WARN)
    return
  end
  inclusive = (inclusive ~= false)

  local history = store.get_patterns()
  require('fzf-lua').fzf_exec(history, {
    prompt = inclusive and 'FuzzLogg include> ' or 'FuzzLogg exclude> ',
    fzf_opts = { ['--print-query'] = '', ['--query'] = vim.fn.getreg('/') },
    actions = {
      ['enter'] = function(selected, opts)
        local pattern = (selected and selected[1] ~= '' and selected[1])
          or (opts and opts.last_query)
        if not pattern or pattern == '' then return end
        vim.schedule(function() add_pattern(pattern, inclusive) end)
      end,
    },
  })
end

function M.fuzzlogg_save(name)
  if not state.active then
    vim.notify('FuzzLogg: not active', vim.log.levels.WARN)
    return
  end
  if #state.patterns == 0 then
    vim.notify('FuzzLogg: no patterns to save', vim.log.levels.WARN)
    return
  end

  if not name then
    vim.ui.input({ prompt = 'Save composition as: ' }, function(input)
      if input and input ~= '' then
        M.fuzzlogg_save(input)
      end
    end)
    return
  end

  local expr = build_expr()
  store.save_composition(name, expr)
  vim.notify('FuzzLogg: saved composition "' .. name .. '"', vim.log.levels.INFO)
end

function M.fuzzlogg_load(expr_or_name)
  if not state.active then
    vim.notify('FuzzLogg: not active, open first with fuzzlogg_open()', vim.log.levels.WARN)
    return
  end

  local expr = expr_or_name
  if not expr:find('/') and not expr:find('[|&~-]') then
    local found = store.get_composition_expr(expr_or_name)
    if not found then
      vim.notify('FuzzLogg: composition "' .. expr_or_name .. '" not found', vim.log.levels.ERROR)
      return
    end
    expr = found
  end

  local ok, tree = pcall(rpn.parse, expr)
  if not ok then
    vim.notify('FuzzLogg: parse error: ' .. tostring(tree), vim.log.levels.ERROR)
    return
  end

  local src_lines = vim.api.nvim_buf_get_lines(state.src_bufnr, 0, -1, false)
  local ok2, result_set = pcall(rpn.eval, tree, src_lines, function(name)
    return store.get_composition_expr(name)
  end)
  if not ok2 then
    vim.notify('FuzzLogg: eval error: ' .. tostring(result_set), vim.log.levels.ERROR)
    return
  end

  for _, p in ipairs(state.patterns) do
    vim.api.nvim_buf_clear_namespace(state.res_bufnr, p.ns_id, 0, -1)
    vim.api.nvim_buf_clear_namespace(state.src_bufnr, p.ns_id, 0, -1)
  end
  state.patterns = {}

  local leaf_patterns = rpn.collect_patterns(tree)
  for i, pattern in ipairs(leaf_patterns) do
    local ok3, re = pcall(vim.regex, pattern)
    if ok3 then
      local color = config.colors[((i - 1) % #config.colors) + 1]
      local hl_group = 'FuzzLoggPat' .. i
      local ns_id = vim.api.nvim_create_namespace('fuzzlogg_' .. i .. '_' .. os.time())
      vim.api.nvim_set_hl(0, hl_group, { fg = color, bold = true })
      table.insert(state.patterns, {
        pattern = pattern,
        inclusive = true,
        re = re,
        ns_id = ns_id,
        hl_group = hl_group,
        color = color,
      })
    end
  end

  state.line_map = {}
  state.src_map = {}
  for i, _ in pairs(result_set) do
    local res_i = #state.line_map + 1
    state.line_map[res_i] = i
    if not state.src_map[i] then state.src_map[i] = res_i end
  end

  local res_lines = {}
  for res_i = 1, #state.line_map do
    local src_i = state.line_map[res_i]
    table.insert(res_lines, src_lines[src_i] or '')
  end

  vim.bo[state.res_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.res_bufnr, 0, -1, false, res_lines)
  vim.bo[state.res_bufnr].modifiable = false

  schedule_render()
  vim.notify('FuzzLogg: loaded expression, ' .. #res_lines .. ' lines', vim.log.levels.INFO)
end

function M.fuzzlogg_remove(idx)
  if not state.active then return end
  local p = state.patterns[idx]
  if not p then
    vim.notify('FuzzLogg: no pattern at index ' .. tostring(idx), vim.log.levels.WARN)
    return
  end

  vim.api.nvim_buf_clear_namespace(state.res_bufnr, p.ns_id, 0, -1)
  vim.api.nvim_buf_clear_namespace(state.src_bufnr, p.ns_id, 0, -1)
  table.remove(state.patterns, idx)

  schedule_render()
  auto_save()
end

function M.fuzzlogg_clear()
  if not state.active then return end
  for _, p in ipairs(state.patterns) do
    if vim.api.nvim_buf_is_valid(state.res_bufnr) then
      vim.api.nvim_buf_clear_namespace(state.res_bufnr, p.ns_id, 0, -1)
    end
    if vim.api.nvim_buf_is_valid(state.src_bufnr) then
      vim.api.nvim_buf_clear_namespace(state.src_bufnr, p.ns_id, 0, -1)
    end
  end
  state.patterns = {}
  schedule_render()
  auto_save()
end

function M.fuzzlogg_close()
  if not state.active then return end

  for _, p in ipairs(state.patterns) do
    if vim.api.nvim_buf_is_valid(state.src_bufnr) then
      vim.api.nvim_buf_clear_namespace(state.src_bufnr, p.ns_id, 0, -1)
    end
  end

  if state.res_win ~= state.src_win then
    if vim.api.nvim_win_is_valid(state.res_win) then
      vim.api.nvim_win_close(state.res_win, true)
    end
  else
    if vim.api.nvim_buf_is_valid(state.res_bufnr) then
      vim.cmd('bwipe ' .. state.res_bufnr)
    end
  end

  reset_state()
end

function M.fuzzlogg_context_add(n)
  if not state.active then
    vim.notify('FuzzLogg: not active', vim.log.levels.WARN)
    return
  end
  state.context = math.max(0, state.context + n)
  schedule_render()
end

function M.fuzzlogg_list()
  if not state.active or #state.patterns == 0 then
    vim.notify('FuzzLogg: no active patterns', vim.log.levels.INFO)
    return
  end
  local lines = {}
  for i, p in ipairs(state.patterns) do
    local kind = p.inclusive and '+' or '-'
    table.insert(lines, string.format('[%d] %s %s  (%s)', i, kind, p.pattern, p.color))
  end
  vim.notify('FuzzLogg patterns:\n' .. table.concat(lines, '\n'), vim.log.levels.INFO)
end

function M.fuzzlogg_jump_to_source()
  if not state.active then return end
  if not vim.api.nvim_win_is_valid(state.res_win) then return end
  local res_line = vim.api.nvim_win_get_cursor(state.res_win)[1]
  local src_line = state.line_map[res_line]
  if src_line and vim.api.nvim_win_is_valid(state.src_win) then
    vim.api.nvim_set_current_win(state.src_win)
    vim.api.nvim_win_set_cursor(state.src_win, { src_line, 0 })
    vim.cmd('normal! zz')
  end
end

function M.fuzzlogg_jump_to_result()
  if not state.active then return end
  if not vim.api.nvim_win_is_valid(state.src_win) then return end
  local src_line = vim.api.nvim_win_get_cursor(state.src_win)[1]
  local res_line = state.src_map[src_line]
  if res_line and vim.api.nvim_win_is_valid(state.res_win) then
    vim.api.nvim_set_current_win(state.res_win)
    vim.api.nvim_win_set_cursor(state.res_win, { res_line, 0 })
    vim.cmd('normal! zz')
  end
end

M._add_pattern_direct = add_pattern

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
end

return M
