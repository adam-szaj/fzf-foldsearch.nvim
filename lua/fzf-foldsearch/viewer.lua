local M = {}

local vconfig = {
  layout = 'vsplit',
  context = 0,
  debounce_ms = 100,
  max_patterns = 8,
  colors = {
    '#3d59a1', '#2ac3de', '#7aa2f7', '#bb9af7',
    '#394b70', '#0db9d7', '#9d7cd8', '#2d4f67',
  },
}

local vstate = {
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
  if vstate.timer then
    vstate.timer:stop()
    vstate.timer:close()
  end
  for _, id in ipairs(vstate.autocmds) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  vstate.active = false
  vstate.src_bufnr = nil
  vstate.res_bufnr = nil
  vstate.src_win = nil
  vstate.res_win = nil
  vstate.patterns = {}
  vstate.context = vconfig.context
  vstate.line_map = {}
  vstate.src_map = {}
  vstate.timer = nil
  vstate.autocmds = {}
end

local function compute_viewer_lines(src_lines, patterns, context)
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

local function render_results()
  if not vstate.active then return end
  if not vim.api.nvim_buf_is_valid(vstate.src_bufnr) then return end
  if not vim.api.nvim_buf_is_valid(vstate.res_bufnr) then return end

  local src_lines = vim.api.nvim_buf_get_lines(vstate.src_bufnr, 0, -1, false)
  local res_lines, line_map, src_map, _, visible_by =
    compute_viewer_lines(src_lines, vstate.patterns, vstate.context)

  vim.bo[vstate.res_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(vstate.res_bufnr, 0, -1, false, res_lines)
  vim.bo[vstate.res_bufnr].modifiable = false

  vstate.line_map = line_map
  vstate.src_map = src_map

  for _, p in ipairs(vstate.patterns) do
    vim.api.nvim_buf_clear_namespace(vstate.res_bufnr, p.ns_id, 0, -1)
    vim.api.nvim_buf_clear_namespace(vstate.src_bufnr, p.ns_id, 0, -1)
  end

  for res_i, src_i in pairs(line_map) do
    local pat_idx = visible_by[src_i]
    if pat_idx then
      local p = vstate.patterns[pat_idx]
      vim.api.nvim_buf_add_highlight(vstate.res_bufnr, p.ns_id, p.hl_group, res_i - 1, 0, -1)
    end
  end

  for src_i, _ in pairs(src_map) do
    local pat_idx = visible_by[src_i]
    if pat_idx then
      local p = vstate.patterns[pat_idx]
      vim.api.nvim_buf_add_highlight(vstate.src_bufnr, p.ns_id, p.hl_group, src_i - 1, 0, -1)
    end
  end
end

local function schedule_render()
  if not vstate.timer then
    vstate.timer = vim.uv.new_timer()
  else
    vstate.timer:stop()
  end
  vstate.timer:start(vconfig.debounce_ms, 0, vim.schedule_wrap(function()
    render_results()
  end))
end

local function open_viewer_layout()
  vstate.src_win = vim.api.nvim_get_current_win()
  local layout = vconfig.layout

  if layout == 'same_window' then
    vstate.res_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(vstate.src_win, vstate.res_bufnr)
    vstate.res_win = vstate.src_win
  elseif layout == 'split' then
    vim.cmd('new')
    vstate.res_win = vim.api.nvim_get_current_win()
    vstate.res_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(vstate.res_win, vstate.res_bufnr)
  else
    vim.cmd('vnew')
    vstate.res_win = vim.api.nvim_get_current_win()
    vstate.res_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(vstate.res_win, vstate.res_bufnr)
  end

  vim.bo[vstate.res_bufnr].buftype = 'nofile'
  vim.bo[vstate.res_bufnr].bufhidden = 'wipe'
  vim.bo[vstate.res_bufnr].swapfile = false
  vim.bo[vstate.res_bufnr].modifiable = false
  pcall(vim.api.nvim_buf_set_name, vstate.res_bufnr, 'viewer://results:' .. os.time())

  vim.keymap.set('n', '<CR>', function() M.jump_to_source() end, { buffer = vstate.res_bufnr, desc = 'Viewer: jump to source' })
end

local function setup_autocmds()
  local id = vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = vstate.src_bufnr,
    callback = function()
      if vstate.active then schedule_render() end
    end,
  })
  table.insert(vstate.autocmds, id)

  id = vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = vstate.res_bufnr,
    once = true,
    callback = function()
      if vstate.active then M.viewer_close() end
    end,
  })
  table.insert(vstate.autocmds, id)

  id = vim.api.nvim_create_autocmd('BufDelete', {
    buffer = vstate.src_bufnr,
    once = true,
    callback = function()
      if vstate.active then M.viewer_close() end
    end,
  })
  table.insert(vstate.autocmds, id)
end

local function add_pattern(pattern, inclusive)
  if #vstate.patterns >= vconfig.max_patterns then
    vim.notify('viewer: max patterns reached (' .. vconfig.max_patterns .. ')', vim.log.levels.WARN)
    return
  end

  local ok, re = pcall(vim.regex, pattern)
  if not ok then
    vim.notify('viewer: invalid pattern: ' .. pattern, vim.log.levels.ERROR)
    return
  end

  local idx = #vstate.patterns + 1
  local color = vconfig.colors[((idx - 1) % #vconfig.colors) + 1]
  local hl_group = 'FzfViewerPat' .. idx
  local ns_id = vim.api.nvim_create_namespace('fzf_viewer_' .. idx .. '_' .. os.time())

  vim.api.nvim_set_hl(0, hl_group, { bg = color, fg = '#000000', bold = true })

  table.insert(vstate.patterns, {
    pattern = pattern,
    inclusive = inclusive,
    re = re,
    ns_id = ns_id,
    hl_group = hl_group,
    color = color,
  })

  local kind = inclusive and 'include' or 'exclude'
  vim.notify(string.format('viewer: pattern %d [%s] %s', idx, kind, pattern), vim.log.levels.INFO)

  schedule_render()
end

function M.viewer_open()
  if vstate.active then
    vim.notify('viewer: already active, close first with viewer_close()', vim.log.levels.WARN)
    return
  end

  vstate.context = vconfig.context
  local bufnr = vim.api.nvim_get_current_buf()
  vstate.src_bufnr = bufnr

  open_viewer_layout()
  setup_autocmds()

  vstate.active = true

  vim.notify('viewer: opened. Add patterns with viewer_add()', vim.log.levels.INFO)
end

function M.viewer_add(inclusive)
  if not vstate.active then
    vim.notify('viewer: not active, open first with viewer_open()', vim.log.levels.WARN)
    return
  end
  inclusive = (inclusive ~= false)

  require('fzf-lua').lgrep_curbuf({
    query = vim.fn.getreg('/'),
    prompt = inclusive and 'Include pattern> ' or 'Exclude pattern> ',
    actions = {
      ['enter'] = function(_, opts)
        local pattern = opts.last_query
        if not pattern or pattern == '' then return end
        vim.schedule(function()
          add_pattern(pattern, inclusive)
        end)
      end,
    },
  })
end

function M.viewer_remove(idx)
  if not vstate.active then return end
  local p = vstate.patterns[idx]
  if not p then
    vim.notify('viewer: no pattern at index ' .. tostring(idx), vim.log.levels.WARN)
    return
  end

  vim.api.nvim_buf_clear_namespace(vstate.res_bufnr, p.ns_id, 0, -1)
  vim.api.nvim_buf_clear_namespace(vstate.src_bufnr, p.ns_id, 0, -1)
  table.remove(vstate.patterns, idx)

  schedule_render()
end

function M.viewer_clear()
  if not vstate.active then return end
  for _, p in ipairs(vstate.patterns) do
    if vim.api.nvim_buf_is_valid(vstate.res_bufnr) then
      vim.api.nvim_buf_clear_namespace(vstate.res_bufnr, p.ns_id, 0, -1)
    end
    if vim.api.nvim_buf_is_valid(vstate.src_bufnr) then
      vim.api.nvim_buf_clear_namespace(vstate.src_bufnr, p.ns_id, 0, -1)
    end
  end
  vstate.patterns = {}
  schedule_render()
end

function M.viewer_close()
  if not vstate.active then return end

  for _, p in ipairs(vstate.patterns) do
    if vim.api.nvim_buf_is_valid(vstate.src_bufnr) then
      vim.api.nvim_buf_clear_namespace(vstate.src_bufnr, p.ns_id, 0, -1)
    end
  end

  if vstate.res_win ~= vstate.src_win then
    if vim.api.nvim_win_is_valid(vstate.res_win) then
      vim.api.nvim_win_close(vstate.res_win, true)
    end
  else
    if vim.api.nvim_buf_is_valid(vstate.res_bufnr) then
      vim.cmd('bwipe ' .. vstate.res_bufnr)
    end
  end

  reset_state()
end

function M.viewer_context_add(n)
  if not vstate.active then
    vim.notify('viewer: not active', vim.log.levels.WARN)
    return
  end
  vstate.context = math.max(0, vstate.context + n)
  schedule_render()
end

function M.viewer_list()
  if not vstate.active or #vstate.patterns == 0 then
    vim.notify('viewer: no active patterns', vim.log.levels.INFO)
    return
  end
  local lines = {}
  for i, p in ipairs(vstate.patterns) do
    local kind = p.inclusive and '+' or '-'
    table.insert(lines, string.format('[%d] %s %s  (%s)', i, kind, p.pattern, p.color))
  end
  vim.notify('viewer patterns:\n' .. table.concat(lines, '\n'), vim.log.levels.INFO)
end

function M.jump_to_source()
  if not vstate.active then return end
  if not vim.api.nvim_win_is_valid(vstate.res_win) then return end
  local res_line = vim.api.nvim_win_get_cursor(vstate.res_win)[1]
  local src_line = vstate.line_map[res_line]
  if src_line and vim.api.nvim_win_is_valid(vstate.src_win) then
    vim.api.nvim_set_current_win(vstate.src_win)
    vim.api.nvim_win_set_cursor(vstate.src_win, { src_line, 0 })
    vim.cmd('normal! zz')
  end
end

function M.jump_to_result()
  if not vstate.active then return end
  if not vim.api.nvim_win_is_valid(vstate.src_win) then return end
  local src_line = vim.api.nvim_win_get_cursor(vstate.src_win)[1]
  local res_line = vstate.src_map[src_line]
  if res_line and vim.api.nvim_win_is_valid(vstate.res_win) then
    vim.api.nvim_set_current_win(vstate.res_win)
    vim.api.nvim_win_set_cursor(vstate.res_win, { res_line, 0 })
    vim.cmd('normal! zz')
  end
end

function M.setup(opts)
  vconfig = vim.tbl_deep_extend('force', vconfig, opts or {})
end

return M
