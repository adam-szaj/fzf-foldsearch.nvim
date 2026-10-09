local M = {}

local config = {
  context = 0,
  large_file_mb = 50,
  result_open = "new", -- 'new' (split), 'edit' (same window), 'vnew' (vsplit), 'tabnew'
  max_result_bufs = 5, -- max buforów wyników w pamięci; 0 = bez limitu
  sync_last_search = true, -- inicjuj fzf query z vim '/' register
  update_last_search = true, -- ustaw '/' register po zatwierdzeniu wzorca
  save_history = true, -- zapisuj wzorce do store (historia FuzzLogg)
}

local state = {
  pattern = nil,
  context = 0,
  viewfile = nil,
  active = false,
  bufnr = nil,
  result_bufs = {},
}

local function pattern_flags(pattern)
  local very_magic, explicit_case = false, false
  local magic = true
  local i = 1
  while i <= #pattern do
    local char = pattern:sub(i, i)
    local atom = pattern:sub(i, i + 1)
    if (char == "[" and magic) or (atom == "\\[" and not magic) then
      i = i + (char == "[" and 1 or 2)
      if pattern:sub(i, i) == "^" then
        i = i + 1
      end
      if pattern:sub(i, i) == "]" then
        i = i + 1
      end
      while i <= #pattern and pattern:sub(i, i) ~= "]" do
        if pattern:sub(i, i) == "\\" then
          i = i + 2
        elseif pattern:sub(i, i + 1):match "^%[[:=%.]" then
          local delimiter = pattern:sub(i + 1, i + 1) .. "]"
          local ending = pattern:find(delimiter, i + 2, true)
          i = ending and ending + 2 or #pattern + 1
        else
          i = i + 1
        end
      end
      i = i + 1
    elseif char == "\\" then
      if atom == "\\v" or atom == "\\V" then
        very_magic = atom == "\\v"
        magic = very_magic
      elseif atom == "\\m" or atom == "\\M" then
        magic = atom == "\\m"
      elseif atom == "\\c" or atom == "\\C" then
        explicit_case = true
      end
      i = i + 2
    else
      i = i + 1
    end
  end
  -- Like Vim's smartcase, skip regex operators rather than counting e.g. \S.
  local text = very_magic and pattern:gsub("[_%%].", "") or pattern:gsub("\\[_%%]?.", "")
  return explicit_case, text ~= vim.fn.tolower(text)
end

local function compile_regex(pattern)
  local explicit_case, uppercase = pattern_flags(pattern)
  local ignorecase = vim.o.ignorecase and not (vim.o.smartcase and uppercase)
  -- Do not add \c alongside an explicit \C: Vim gives \c precedence.
  local case_flag = explicit_case and "" or (ignorecase and "\\c" or "\\C")
  return vim.regex(case_flag .. pattern)
end

local function disable_heavy_features(bufnr)
  -- local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(bufnr))
  -- if not ok or not stats then return end
  -- if stats.size < config.large_file_mb * 1024 * 1024 then return end
  -- vim.treesitter.stop(bufnr)
  -- for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
  --   vim.lsp.stop_client(client.id)
  -- end
end

local function save_view(bufnr)
  if state.viewfile then
    return
  end
  state.viewfile = vim.fn.tempname()
  local saved_viewoptions = vim.o.viewoptions
  vim.o.viewoptions = "folds"
  vim.cmd("mkview " .. state.viewfile)
  vim.o.viewoptions = saved_viewoptions

  local lines = vim.fn.readfile(state.viewfile)
  table.insert(lines, 1, "silent! normal! zE")
  table.insert(lines, "setlocal fdt=" .. vim.o.foldtext)
  if vim.o.foldenable then
    table.insert(lines, "setlocal fen")
  else
    table.insert(lines, "setlocal nofen")
  end
  lines = vim.tbl_filter(function(l)
    return not l:match "^enew" and not l:match "^doautoall"
  end, lines)
  vim.fn.writefile(lines, state.viewfile, "S")
end

local function compute_matches(bufnr, pattern, context)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total = #lines

  local matched = {}
  local ok, regex = pcall(compile_regex, pattern)
  if not ok then
    vim.notify("fzf-foldsearch: invalid Vim regex: " .. pattern, vim.log.levels.WARN)
    return lines, matched, {}
  end
  for i, line in ipairs(lines) do
    if regex:match_str(line) then
      matched[i] = true
    end
  end

  local visible = {}
  for i = 1, total do
    if matched[i] then
      for c = math.max(1, i - context), math.min(total, i + context) do
        visible[c] = true
      end
    end
  end

  return lines, matched, visible
end

local function apply_folds(bufnr, pattern, context)
  local lines, matched, visible = compute_matches(bufnr, pattern, context)
  local total = #lines

  vim.cmd "setlocal foldmethod=manual foldminlines=0 foldenable"
  vim.cmd "normal! zE"

  local fold_start = nil
  for i = 1, total + 1 do
    if i <= total and not visible[i] then
      if not fold_start then
        fold_start = i
      end
    else
      if fold_start then
        vim.cmd(fold_start .. "," .. (i - 1) .. "fold")
        fold_start = nil
      end
    end
  end

  if not next(matched) then
    vim.notify("fzf-foldsearch: pattern not found", vim.log.levels.WARN)
  end
end

local function open_result_buf(lines, name)
  local unique_name = name and (name .. ":" .. os.time()) or nil
  vim.cmd(config.result_open)
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  if unique_name then
    pcall(vim.api.nvim_buf_set_name, bufnr, unique_name)
  end

  table.insert(state.result_bufs, bufnr)
  if config.max_result_bufs > 0 then
    while #state.result_bufs > config.max_result_bufs do
      local old = table.remove(state.result_bufs, 1)
      if vim.api.nvim_buf_is_valid(old) then
        vim.cmd("bwipe " .. old)
      end
    end
  end
end

function M.extract_matched()
  if not state.active or not state.pattern or not state.bufnr then
    vim.notify("fzf-foldsearch: no active fold search", vim.log.levels.WARN)
    return
  end

  local lines, matched, _ = compute_matches(state.bufnr, state.pattern, state.context)
  local result = {}
  for i, line in ipairs(lines) do
    if matched[i] then
      table.insert(result, line)
    end
  end

  open_result_buf(result, "foldsearch://matched")
end

function M.extract_visible()
  if not state.active or not state.pattern or not state.bufnr then
    vim.notify("fzf-foldsearch: no active fold search", vim.log.levels.WARN)
    return
  end

  local lines, _, visible = compute_matches(state.bufnr, state.pattern, state.context)
  local result = {}
  for i, line in ipairs(lines) do
    if visible[i] then
      table.insert(result, line)
    end
  end

  open_result_buf(result, "foldsearch://visible")
end

local function do_fold(bufnr, pattern)
  if not pcall(compile_regex, pattern) then
    vim.notify("fzf-foldsearch: invalid Vim regex: " .. pattern, vim.log.levels.WARN)
    return
  end
  state.pattern = pattern
  state.context = config.context
  state.bufnr = bufnr

  if config.update_last_search then
    vim.fn.setreg("/", pattern)
  end
  if config.save_history then
    require("fzf-foldsearch.store").add_pattern(pattern)
  end

  disable_heavy_features(bufnr)
  save_view(bufnr)
  apply_folds(bufnr, pattern, state.context)
  state.active = true
end

function M.fold_search()
  local bufnr = vim.api.nvim_get_current_buf()
  local fzf = require "fzf-lua"
  local entry_prefix = string.format("[%d]%sbuffer:", bufnr, require("fzf-lua.utils").nbsp)

  local function with_pattern(opts, fn)
    local pattern = opts.last_query
    if not pattern or pattern == "" then
      return
    end
    vim.schedule(function()
      fn(pattern)
    end)
  end

  local function picker_lines(args)
    local ok, regex = pcall(compile_regex, args[1] or "")
    if not ok then
      return {}
    end
    local result = {}
    for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      local col = regex:match_str(line)
      if col then
        -- Buffer metadata lets the builtin previewer show unsaved/scratch buffers.
        table.insert(result, string.format("%s%d:%d:%s", entry_prefix, i, col + 1, line))
      end
    end
    return result
  end

  fzf.fzf_live(picker_lines, {
    query = config.sync_last_search and vim.fn.getreg "/" or "",
    prompt = "FoldSearch> ",
    exec_empty_query = true,
    previewer = "builtin",
    fzf_opts = { ["--delimiter"] = ":", ["--with-nth"] = "2.." },
    silent = true,
    actions = {
      ["enter"] = function(_, opts)
        with_pattern(opts, function(pattern)
          do_fold(bufnr, pattern)
        end)
      end,
      ["ctrl-x"] = function(_, opts)
        with_pattern(opts, function(pattern)
          local lines, matched, _ = compute_matches(bufnr, pattern, config.context)
          local result = {}
          for i, line in ipairs(lines) do
            if matched[i] then
              table.insert(result, line)
            end
          end
          open_result_buf(result, "foldsearch://matched")
        end)
      end,
      ["ctrl-o"] = function(_, opts)
        with_pattern(opts, function(pattern)
          local lines, _, visible = compute_matches(bufnr, pattern, config.context)
          local result = {}
          for i, line in ipairs(lines) do
            if visible[i] then
              table.insert(result, line)
            end
          end
          open_result_buf(result, "foldsearch://visible")
        end)
      end,
    },
  })
end

function M.fold_search_expr(pattern)
  if not pattern or pattern == "" then
    vim.notify("fzf-foldsearch: no pattern given", vim.log.levels.WARN)
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  do_fold(bufnr, pattern)
end

function M.fold_end()
  if not state.active then
    return
  end

  if state.viewfile then
    vim.cmd("silent! source " .. state.viewfile)
    vim.fn.delete(state.viewfile)
    state.viewfile = nil
  end

  state.active = false
  state.pattern = nil
  state.bufnr = nil
end

function M.fold_context_add(n)
  if not state.active or not state.pattern or not state.bufnr then
    vim.notify("fzf-foldsearch: no active fold search", vim.log.levels.WARN)
    return
  end

  state.context = math.max(0, state.context + n)
  apply_folds(state.bufnr, state.pattern, state.context)
end

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", config, opts)
  local fuzzlogg = require "fzf-foldsearch.fuzzlogg"
  if opts.fuzzlogg then
    fuzzlogg.setup(opts.fuzzlogg)
  end
end

local fuzzlogg = require "fzf-foldsearch.fuzzlogg"
M.fuzzlogg_open = fuzzlogg.fuzzlogg_open
M.fuzzlogg_add = fuzzlogg.fuzzlogg_add
M.fuzzlogg_add_group = fuzzlogg.fuzzlogg_add_group
M.fuzzlogg_remove = fuzzlogg.fuzzlogg_remove
M.fuzzlogg_clear = fuzzlogg.fuzzlogg_clear
M.fuzzlogg_close = fuzzlogg.fuzzlogg_close
M.fuzzlogg_context_add = fuzzlogg.fuzzlogg_context_add
M.fuzzlogg_list = fuzzlogg.fuzzlogg_list
M.fuzzlogg_jump_to_source = fuzzlogg.fuzzlogg_jump_to_source
M.fuzzlogg_jump_to_result = fuzzlogg.fuzzlogg_jump_to_result
M.fuzzlogg_save = fuzzlogg.fuzzlogg_save
M.fuzzlogg_load = fuzzlogg.fuzzlogg_load
M.fuzzlogg_load_pattern = fuzzlogg.fuzzlogg_load_pattern

local panel = require "fzf-foldsearch.panel"
M.fuzzlogg_panel = panel.panel_open
M.fuzzlogg_panel_close = panel.panel_close

local importer = require "fzf-foldsearch.importer"
M.fuzzlogg_import = importer.import

return M
