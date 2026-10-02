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
  base = nil,
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
  state.base = nil
  state.patterns = {}
  state.context = config.context
  state.line_map = {}
  state.src_map = {}
  state.timer = nil
  state.autocmds = {}
end

local function active_pattern_count()
  return #state.patterns + (state.base and #state.base.patterns or 0)
end

local function build_filter_tree(persistent_only)
  local tree = state.base and state.base.tree or nil
  local excluded = {}
  for _, pattern in ipairs(state.patterns) do
    if not persistent_only or not pattern.transient then
      local atom = { type = 'pattern', value = pattern.key or pattern.pattern }
      if pattern.inclusive then
        tree = tree and { op = '|', left = tree, right = atom } or atom
      else
        table.insert(excluded, atom)
      end
    end
  end

  for _, atom in ipairs(excluded) do
    if tree then
      tree = { op = '-', left = tree, right = atom }
    else
      tree = { type = 'empty' }
    end
  end
  return tree
end

local function all_patterns()
  local patterns = {}
  if state.base then
    vim.list_extend(patterns, state.base.patterns)
  end
  vim.list_extend(patterns, state.patterns)
  return patterns
end

local function compute_lines(src_lines, context)
  local tree = build_filter_tree()
  if not tree then return {}, {}, {}, {}, {} end

  local patterns = all_patterns()
  local regex_cache = {}
  for _, pattern in ipairs(patterns) do
    regex_cache[pattern.key or pattern.pattern] = pattern.re
  end
  local selected = rpn.eval(tree, src_lines, store.get_composition_expr, regex_cache)
  local highlight_patterns = {}
  for _, pattern in ipairs(patterns) do
    if pattern.inclusive then
      table.insert(highlight_patterns, pattern)
    end
  end

  local visible = {}
  local color_by = {}
  for i, line in ipairs(src_lines) do
    if selected[i] then
      visible[i] = true
      for idx, pattern in ipairs(highlight_patterns) do
        if pattern.re:match_str(line) then
          color_by[i] = idx
          break
        end
      end
    end
  end

  local context_color_by = {}
  if context > 0 then
    local expanded = {}
    for i = 1, #src_lines do
      if visible[i] then
        for c = math.max(1, i - context), math.min(#src_lines, i + context) do
          expanded[c] = true
          if not context_color_by[c] then
            context_color_by[c] = color_by[i]
          end
        end
      end
    end
    visible = expanded
  end

  local res_lines = {}
  local line_map = {}
  local src_map = {}
  for i = 1, #src_lines do
    if visible[i] then
      local res_i = #res_lines + 1
      table.insert(res_lines, src_lines[i])
      line_map[res_i] = i
      src_map[i] = res_i
    end
  end

  return res_lines, line_map, src_map, color_by, context_color_by, highlight_patterns
end

local function render()
  if not state.active then return end
  if not vim.api.nvim_buf_is_valid(state.src_bufnr) then return end
  if not vim.api.nvim_buf_is_valid(state.res_bufnr) then return end

  local src_lines = vim.api.nvim_buf_get_lines(state.src_bufnr, 0, -1, false)
  local res_lines, line_map, src_map, color_by, context_color_by, highlight_patterns =
    compute_lines(src_lines, state.context)

  vim.bo[state.res_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.res_bufnr, 0, -1, false, res_lines)
  vim.bo[state.res_bufnr].modifiable = false

  state.line_map = line_map
  state.src_map = src_map

  for _, p in ipairs(all_patterns()) do
    vim.api.nvim_buf_clear_namespace(state.res_bufnr, p.ns_id, 0, -1)
    vim.api.nvim_buf_clear_namespace(state.src_bufnr, p.ns_id, 0, -1)
  end

  for res_i, src_i in pairs(line_map) do
    local pat_idx = color_by[src_i] or context_color_by[src_i]
    if pat_idx then
      local p = highlight_patterns[pat_idx]
      vim.api.nvim_buf_add_highlight(state.res_bufnr, p.ns_id, p.hl_group, res_i - 1, 0, -1)
    end
  end

  for src_i, _ in pairs(src_map) do
    local pat_idx = color_by[src_i] or context_color_by[src_i]
    if pat_idx then
      local p = highlight_patterns[pat_idx]
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
    vim.cmd('split')
    state.res_win = vim.api.nvim_get_current_win()
    state.res_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(state.res_win, state.res_bufnr)
  else
    vim.cmd('vsplit')
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
  local tree = build_filter_tree(true)
  return tree and rpn.serialize(tree) or nil
end

local function auto_save()
  if not state.active then return end
  store.save_composition(nil, build_expr() or '@empty')
end

local function add_pattern(pattern, inclusive, defer_update, transient, matcher)
  if not state.active then
    vim.notify('FuzzLogg: not active, open first with fuzzlogg_open()', vim.log.levels.WARN)
    return false
  end
  if active_pattern_count() >= config.max_patterns then
    vim.notify('FuzzLogg: max patterns reached (' .. config.max_patterns .. ')', vim.log.levels.WARN)
    return false
  end

  local re = matcher
  if not re then
    local ok
    ok, re = pcall(vim.regex, pattern)
    if not ok then
      vim.notify('FuzzLogg: invalid pattern: ' .. pattern, vim.log.levels.ERROR)
      return false
    end
  end

  local idx = active_pattern_count() + 1
  local used = {}
  for _, active in ipairs(all_patterns()) do used[active.hl_group] = true end
  local slot
  for i = 1, #config.colors do
    if not used['FuzzLoggPat' .. i] then
      slot = i
      break
    end
  end
  slot = slot or (((idx - 1) % #config.colors) + 1)
  local color = config.colors[slot]
  local hl_group = 'FuzzLoggPat' .. slot
  local ns_id = vim.api.nvim_create_namespace('')

  vim.api.nvim_set_hl(0, hl_group, { fg = color, bold = true })

  table.insert(state.patterns, {
    pattern = pattern,
    inclusive = inclusive,
    re = re,
    ns_id = ns_id,
    hl_group = hl_group,
    color = color,
    transient = transient,
    key = matcher and {} or nil,
  })

  if not transient then store.add_pattern(pattern) end

  if not defer_update then
    local kind = inclusive and 'include' or 'exclude'
    vim.notify(string.format('FuzzLogg: pattern %d [%s] %s', idx, kind, pattern), vim.log.levels.INFO)
    schedule_render()
    if not transient then auto_save() end
  end
  return true
end

local function make_base(tree, expr, regex_cache)
  local pattern_list = {}
  for i, pattern in ipairs(rpn.collect_patterns(tree)) do
    local re = regex_cache[pattern]
    local idx = i
    local color = config.colors[((idx - 1) % #config.colors) + 1]
    local hl_group = 'FuzzLoggPat' .. idx
    vim.api.nvim_set_hl(0, hl_group, { fg = color, bold = true })
    table.insert(pattern_list, {
      pattern = pattern,
      inclusive = true,
      re = re,
      ns_id = vim.api.nvim_create_namespace(''),
      hl_group = hl_group,
      color = color,
    })
  end
  return { tree = tree, expr = expr, patterns = pattern_list }
end

local function clear_highlights(patterns)
  for _, pattern in ipairs(patterns) do
    if vim.api.nvim_buf_is_valid(state.res_bufnr) then
      vim.api.nvim_buf_clear_namespace(state.res_bufnr, pattern.ns_id, 0, -1)
    end
    if vim.api.nvim_buf_is_valid(state.src_bufnr) then
      vim.api.nvim_buf_clear_namespace(state.src_bufnr, pattern.ns_id, 0, -1)
    end
  end
end

local function active_pattern_labels()
  local lines = {}
  local index = 1
  if state.base then
    table.insert(lines, string.format('[1] = expression %s', state.base.expr))
    index = 2
  end
  for i, p in ipairs(state.patterns) do
    local kind = p.inclusive and '+' or '-'
    local scope = p.transient and ' [group]' or ''
    table.insert(lines, string.format('[%d] %s %s  (%s)%s', index + i - 1, kind, p.pattern, p.color, scope))
  end
  return lines
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

function M.fuzzlogg_add(inclusive, pattern)
  if not state.active then
    vim.notify('FuzzLogg: not active, open first with fuzzlogg_open()', vim.log.levels.WARN)
    return
  end
  inclusive = (inclusive ~= false)
  if pattern ~= nil then
    add_pattern(pattern, inclusive)
    return
  end

  local function submit_pattern(pattern)
    if not pattern or pattern == '' then return end
    vim.schedule(function() add_pattern(pattern, inclusive) end)
  end

  local history = store.get_patterns()
  require('fzf-lua').fzf_exec(history, {
    prompt = inclusive and 'FuzzLogg include> ' or 'FuzzLogg exclude> ',
    fzf_opts = { ['--print-query'] = '', ['--query'] = vim.fn.getreg('/') },
    actions = {
      ['enter'] = function(selected, opts)
        local pattern = selected and selected[#selected]
        if not pattern or pattern == '' then
          pattern = opts and opts.last_query
        end
        submit_pattern(pattern)
      end,
      ['alt-enter'] = {
        fn = function(_, opts) submit_pattern(opts and opts.last_query) end,
        header = 'add typed pattern',
      },
    },
  })
end

function M.fuzzlogg_add_group(group, pattern)
  if not state.active then
    vim.notify('FuzzLogg: not active, open first with fuzzlogg_open()', vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(state.src_bufnr, 0, -1, false)
  local available = config.max_patterns - active_pattern_count()
  local patterns, err = require('fzf-foldsearch.group_patterns').expand(pattern, group, lines, available)
  if not patterns then
    vim.notify('FuzzLogg: ' .. err, vim.log.levels.ERROR)
    return
  end
  if #patterns == 0 then
    vim.notify('FuzzLogg: no non-empty group values found', vim.log.levels.WARN)
    return
  end
  for _, derived in ipairs(patterns) do
    add_pattern(derived.label, true, true, true, derived.matcher)
  end
  store.add_pattern(pattern)
  schedule_render()
  vim.notify('FuzzLogg: added ' .. #patterns .. ' patterns from group ' .. group, vim.log.levels.INFO)
end

function M.fuzzlogg_save(name, on_saved)
  if not state.active then
    vim.notify('FuzzLogg: not active', vim.log.levels.WARN)
    return
  end
  local expr = build_expr()
  if not expr then
    vim.notify('FuzzLogg: no persistent patterns to save', vim.log.levels.WARN)
    return
  end

  if not name then
    vim.ui.input({ prompt = 'Save composition as: ' }, function(input)
      if input and input ~= '' then
        M.fuzzlogg_save(input, on_saved)
      end
    end)
    return
  end

  store.save_composition(name, expr)
  local omitted_groups = false
  for _, p in ipairs(state.patterns) do
    if p.transient then
      omitted_groups = true
      break
    end
  end
  local suffix = omitted_groups and ' (group patterns omitted)' or ''
  vim.notify('FuzzLogg: saved composition "' .. name .. '"' .. suffix, vim.log.levels.INFO)
  if on_saved then on_saved() end
end

local function load_tree(tree)
  local ok, resolved = pcall(rpn.resolve, tree, store.get_composition_expr)
  if not ok then
    vim.notify('FuzzLogg: eval error: ' .. tostring(resolved), vim.log.levels.ERROR)
    return
  end

  local leaf_patterns = rpn.collect_patterns(resolved)
  if #leaf_patterns > config.max_patterns then
    vim.notify('FuzzLogg: expression exceeds max patterns (' .. config.max_patterns .. ')', vim.log.levels.WARN)
    return
  end

  local src_lines = vim.api.nvim_buf_get_lines(state.src_bufnr, 0, -1, false)
  local regex_cache = {}
  local ok2, result_set = pcall(rpn.eval, resolved, src_lines, nil, regex_cache)
  if not ok2 then
    vim.notify('FuzzLogg: eval error: ' .. tostring(result_set), vim.log.levels.ERROR)
    return
  end

  local ok3, base = pcall(make_base, resolved, rpn.serialize(resolved), regex_cache)
  if not ok3 then
    vim.notify('FuzzLogg: eval error: ' .. tostring(base), vim.log.levels.ERROR)
    return
  end

  clear_highlights(all_patterns())
  state.base = base
  state.patterns = {}
  state.line_map = {}
  state.src_map = {}
  schedule_render()
  auto_save()

  local matches = 0
  for _ in pairs(result_set) do matches = matches + 1 end
  vim.notify('FuzzLogg: loaded expression, ' .. matches .. ' lines', vim.log.levels.INFO)
end

function M.fuzzlogg_load(expr_or_name)
  if not state.active then
    vim.notify('FuzzLogg: not active, open first with fuzzlogg_open()', vim.log.levels.WARN)
    return
  end
  if type(expr_or_name) ~= 'string' or expr_or_name == '' then
    vim.notify('FuzzLogg: no composition or expression given', vim.log.levels.WARN)
    return
  end

  local expr = store.get_composition_expr(expr_or_name) or expr_or_name

  local ok, tree = pcall(rpn.parse, expr)
  if not ok then
    vim.notify('FuzzLogg: parse error: ' .. tostring(tree), vim.log.levels.ERROR)
    return
  end
  load_tree(tree)
end

function M.fuzzlogg_load_pattern(pattern)
  if not state.active then
    vim.notify('FuzzLogg: not active, open first with fuzzlogg_open()', vim.log.levels.WARN)
    return
  end
  if type(pattern) ~= 'string' or pattern == '' then return end
  load_tree({ type = 'pattern', value = pattern })
end

local function remove_pattern_indices(indices)
  local offset = state.base and 1 or 0
  local persistent_removed = false
  for i = #state.patterns, 1, -1 do
    if indices[i + offset] then
      if not state.patterns[i].transient then persistent_removed = true end
      clear_highlights({ state.patterns[i] })
      table.remove(state.patterns, i)
    end
  end
  if state.base and indices[1] then
    clear_highlights(state.base.patterns)
    state.base = nil
    persistent_removed = true
  end
  schedule_render()
  if persistent_removed then auto_save() end
end

function M.fuzzlogg_remove(idx)
  if not state.active then return end
  local labels = active_pattern_labels()
  if idx == nil then
    if #labels == 0 then
      vim.notify('FuzzLogg: no active patterns', vim.log.levels.INFO)
      return
    end
    require('fzf-lua').fzf_exec(labels, {
      prompt = 'FuzzLogg remove> ',
      fzf_opts = { ['--multi'] = true, ['--header'] = 'Tab: select patterns; Enter: remove' },
      actions = {
        ['enter'] = function(selected)
          if not selected or #selected == 0 then return end
          local indices = {}
          for _, label in ipairs(selected) do
            local index = tonumber(label:match('^%[(%d+)%]'))
            if index then indices[index] = true end
          end
          if not next(indices) then return end
          vim.schedule(function()
            if state.active then remove_pattern_indices(indices) end
          end)
        end,
      },
    })
    return
  end
  if type(idx) ~= 'number' or idx < 1 or idx % 1 ~= 0 then
    vim.notify('FuzzLogg: invalid pattern index ' .. tostring(idx), vim.log.levels.WARN)
    return
  end
  if idx > #labels then
    vim.notify('FuzzLogg: no pattern at index ' .. tostring(idx), vim.log.levels.WARN)
    return
  end
  remove_pattern_indices({ [idx] = true })
end

function M.fuzzlogg_clear()
  if not state.active then return end
  local had_persistent = build_expr() ~= nil
  clear_highlights(all_patterns())
  state.base = nil
  state.patterns = {}
  schedule_render()
  if had_persistent then auto_save() end
end

function M.fuzzlogg_close()
  if not state.active then return end

  local src_bufnr = state.src_bufnr
  local src_win = state.src_win
  local res_bufnr = state.res_bufnr
  local res_win = state.res_win
  local same_window = res_win == src_win
  state.active = false
  clear_highlights(all_patterns())

  if same_window and vim.api.nvim_win_is_valid(src_win) and vim.api.nvim_buf_is_valid(src_bufnr) then
    vim.api.nvim_win_set_buf(src_win, src_bufnr)
  elseif vim.api.nvim_win_is_valid(res_win) then
    vim.api.nvim_win_close(res_win, true)
  end
  if vim.api.nvim_buf_is_valid(res_bufnr) then
    pcall(vim.api.nvim_buf_delete, res_bufnr, { force = true })
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
  if not state.active or (#state.patterns == 0 and not state.base) then
    vim.notify('FuzzLogg: no active patterns', vim.log.levels.INFO)
    return
  end
  vim.notify('FuzzLogg patterns:\n' .. table.concat(active_pattern_labels(), '\n'), vim.log.levels.INFO)
end

function M.fuzzlogg_jump_to_source()
  if not state.active then return end
  if not vim.api.nvim_win_is_valid(state.res_win) then return end
  local res_line = vim.api.nvim_win_get_cursor(state.res_win)[1]
  local src_line = state.line_map[res_line]
  if src_line and vim.api.nvim_win_is_valid(state.src_win) then
    if state.src_win == state.res_win then
      vim.api.nvim_win_set_buf(state.src_win, state.src_bufnr)
    end
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
    if state.src_win == state.res_win then
      vim.api.nvim_win_set_buf(state.res_win, state.res_bufnr)
    end
    vim.api.nvim_set_current_win(state.res_win)
    vim.api.nvim_win_set_cursor(state.res_win, { res_line, 0 })
    vim.cmd('normal! zz')
  end
end

M._add_pattern_direct = add_pattern

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
  if config.color_spec then
    config.colors = require('fzf-foldsearch.colors').generate_colors(config.color_spec)
  end
  if config.layout ~= 'vsplit' and config.layout ~= 'split' and config.layout ~= 'same_window' then
    error('FuzzLogg: layout must be "vsplit", "split", or "same_window"')
  end
  if type(config.colors) ~= 'table' or #config.colors == 0 then
    error('FuzzLogg: colors must contain at least one color')
  end
  for _, color in ipairs(config.colors) do
    if type(color) ~= 'string' or color == '' then
      error('FuzzLogg: each color must be a non-empty string')
    end
  end
  if type(config.max_patterns) ~= 'number' or config.max_patterns < 1 or config.max_patterns % 1 ~= 0 then
    error('FuzzLogg: max_patterns must be a positive integer')
  end
  if type(config.debounce_ms) ~= 'number' or config.debounce_ms < 0 or config.debounce_ms % 1 ~= 0 then
    error('FuzzLogg: debounce_ms must be a non-negative integer')
  end
  if type(config.context) ~= 'number' or config.context < 0 or config.context % 1 ~= 0 then
    error('FuzzLogg: context must be a non-negative integer')
  end
  if config.import_path then
    require('fzf-foldsearch.importer').setup({ import_path = config.import_path })
  end
end

return M
