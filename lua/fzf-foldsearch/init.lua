local M = {}

local config = {
  context = 0,
  large_file_mb = 50,
}

local state = {
  pattern = nil,
  context = 0,
  viewfile = nil,
  active = false,
  bufnr = nil,
}

local function disable_heavy_features(bufnr)
  local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(bufnr))
  if not ok or not stats then return end
  if stats.size < config.large_file_mb * 1024 * 1024 then return end

  vim.treesitter.stop(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    vim.lsp.stop_client(client.id)
  end
end

local function save_view(bufnr)
  if state.viewfile then return end
  state.viewfile = vim.fn.tempname()
  local saved_viewoptions = vim.o.viewoptions
  vim.o.viewoptions = 'folds'
  vim.cmd('mkview ' .. state.viewfile)
  vim.o.viewoptions = saved_viewoptions

  local lines = vim.fn.readfile(state.viewfile)
  table.insert(lines, 1, 'silent! normal! zE')
  table.insert(lines, 'setlocal fdt=' .. vim.o.foldtext)
  if vim.o.foldenable then
    table.insert(lines, 'setlocal fen')
  else
    table.insert(lines, 'setlocal nofen')
  end
  lines = vim.tbl_filter(function(l)
    return not l:match('^enew') and not l:match('^doautoall')
  end, lines)
  vim.fn.writefile(lines, state.viewfile, 'S')
end

local function apply_folds(bufnr, pattern, context)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total = #lines
  local re = vim.regex(pattern)

  local matched = {}
  for i, line in ipairs(lines) do
    if re:match_str(line) then
      matched[i] = true
    end
  end

  -- mark lines that should be visible (matched + context)
  local visible = {}
  for i = 1, total do
    if matched[i] then
      for c = math.max(1, i - context), math.min(total, i + context) do
        visible[c] = true
      end
    end
  end

  vim.cmd('setlocal foldmethod=manual foldminlines=0 foldenable')
  vim.cmd('normal! zE')

  -- fold contiguous invisible ranges
  local fold_start = nil
  for i = 1, total + 1 do
    if i <= total and not visible[i] then
      if not fold_start then fold_start = i end
    else
      if fold_start then
        vim.cmd(fold_start .. ',' .. (i - 1) .. 'fold')
        fold_start = nil
      end
    end
  end

  if not next(matched) then
    vim.notify('fzf-foldsearch: pattern not found', vim.log.levels.WARN)
  end
end

local function do_fold(bufnr, pattern)
  state.pattern = pattern
  state.context = config.context
  state.bufnr = bufnr

  disable_heavy_features(bufnr)
  save_view(bufnr)
  apply_folds(bufnr, pattern, state.context)
  state.active = true
end

function M.fold_search()
  local bufnr = vim.api.nvim_get_current_buf()

  require('fzf-lua').lgrep_curbuf({
    actions = {
      ['enter'] = function(_, opts)
        local pattern = opts.last_query
        if not pattern or pattern == '' then return end
        vim.schedule(function()
          do_fold(bufnr, pattern)
        end)
      end,
    },
  })
end

function M.fold_end()
  if not state.active then return end

  if state.viewfile then
    vim.cmd('silent! source ' .. state.viewfile)
    vim.fn.delete(state.viewfile)
    state.viewfile = nil
  end

  state.active = false
  state.pattern = nil
  state.bufnr = nil
end

function M.fold_context_add(n)
  if not state.active or not state.pattern or not state.bufnr then
    vim.notify('fzf-foldsearch: no active fold search', vim.log.levels.WARN)
    return
  end

  state.context = math.max(0, state.context + n)
  apply_folds(state.bufnr, state.pattern, state.context)
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
end

return M
