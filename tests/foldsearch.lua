-- Run from the repository root: nvim --headless -u NONE -i NONE -l tests/foldsearch.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local reload, picker
package.loaded["fzf-lua"] = {
  fzf_live = function(contents, opts)
    reload, picker = contents, opts
  end,
}
package.loaded["fzf-lua.utils"] = { nbsp = "\226\128\130" }
local foldsearch = require "fzf-foldsearch"
foldsearch.setup { save_history = false }

local notifications = {}
vim.notify = function(message)
  table.insert(notifications, message)
end

local lines = {
  "ERROR",
  "error",
  "Error",
  "WARN",
  "123",
  "a.b",
  "aXb",
  "[2024",
  "xERROR",
  "xerror",
  "ŻÓŁĆ",
  "żółć",
  "\\Cerror",
  "",
  "vxERROR",
  "vxerror",
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local source = vim.api.nvim_get_current_buf()
local oracle = vim.api.nvim_create_buf(false, true)
local patterns = {
  "error",
  "ERROR",
  "Error",
  [[ERROR\|WARN]],
  [[\d\+]],
  [[a\.b]],
  [[^\[2024]],
  [[\cERROR]],
  [[\Cerror]],
  [[\C\cERROR]],
  [[\c\Cerror]],
  [[\Verror]],
  [[\verror|warn]],
  [[\Serror]],
  [[\_Serror]],
  [[\%U00000045rror]],
  [[\v\Serror]],
  [[\V\verror]],
  [[\\Cerror]],
  "żółć",
  "ŻÓŁĆ",
  "^$",
  "absent",
  [[[\v]\Serror]],
  [[[\c]error]],
  [[[\C]error]],
  [[\v[_S]error]],
  [=[[[:alpha:]]error]=],
}

local checks = 0
for _, ignorecase in ipairs { false, true } do
  for _, smartcase in ipairs { false, true } do
    vim.o.ignorecase, vim.o.smartcase = ignorecase, smartcase
    for _, pattern in ipairs(patterns) do
      foldsearch.fold_search()
      local results = reload { pattern }
      local matched = {}
      for _, entry in ipairs(results) do
        matched[tonumber(entry:match "buffer:(%d+):")] = true
      end
      local expected = {}
      for i, line in ipairs(lines) do
        expected[i] = vim.api.nvim_buf_call(oracle, function()
          vim.api.nvim_buf_set_lines(oracle, 0, -1, false, { line })
          vim.api.nvim_win_set_cursor(0, { 1, 0 })
          return vim.fn.searchpos(pattern, "cnW")[1] == 1
        end)
        assert(
          (matched[i] or false) == expected[i],
          string.format(
            "picker differs from /: %q line %d (ic=%s scs=%s)",
            pattern,
            i,
            tostring(ignorecase),
            tostring(smartcase)
          )
        )
        checks = checks + 1
      end
      picker.actions.enter({}, { last_query = pattern })
      vim.wait(1000, function()
        return vim.fn.getreg "/" == pattern
      end)
      for i in ipairs(lines) do
        assert((vim.fn.foldclosed(i) == -1) == expected[i], "folds differ from picker: " .. pattern)
        checks = checks + 1
      end
      assert(vim.fn.getreg "/" == pattern, "search register changed the pattern")
      foldsearch.fold_end()
      assert(vim.wo.foldmethod == "manual" and vim.fn.foldclosed(1) == -1, "fold state not restored")
    end
  end
end

vim.o.ignorecase, vim.o.smartcase, vim.o.magic = true, true, true
vim.fn.setreg("/", [[ERROR\|WARN]])
foldsearch.fold_search()
assert(picker.query == [[ERROR\|WARN]], "last search was converted")
assert(#reload { "" } == #lines, "empty query should show the whole buffer")
assert(#reload { "absent" } == 0, "no-match query should be empty")
assert(#reload { [[\(]] } == 0, "invalid query should be empty")
foldsearch.fold_search_expr [[\(]]
assert(vim.fn.getreg "/" == [[ERROR\|WARN]], "invalid pattern overwrote last search")
assert(vim.fn.foldclosed(1) == -1, "invalid pattern changed folds")
assert(notifications[#notifications]:find("invalid Vim regex", 1, true), "invalid pattern was not reported")

vim.bo.buftype = "nofile"
foldsearch.fold_search()
assert(#reload { [[ERROR\|WARN]] } == 4, "scratch buffer must use Vim regexes")
vim.bo.buftype = ""

foldsearch.fold_search_expr [[ERROR\|WARN]]
foldsearch.extract_matched()
assert(
  vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "ERROR", "WARN", "xERROR", "vxERROR" }),
  "extracted results differ from picker"
)
vim.cmd "close"
assert(vim.api.nvim_get_current_buf() == source)
foldsearch.fold_end()

foldsearch.setup { context = 1 }
foldsearch.fold_search()
picker.actions["ctrl-o"]({}, { last_query = "^WARN$" })
vim.wait(1000, function()
  return vim.api.nvim_get_current_buf() ~= source
end)
assert(
  vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "Error", "WARN", "123" }),
  "picker extraction lost context"
)
vim.cmd "close"
foldsearch.setup { context = 0, sync_last_search = false }
foldsearch.fold_search()
assert(picker.query == "", "sync_last_search=false was ignored")
local last_search = vim.fn.getreg "/"
picker.actions.enter({}, { last_query = "" })
vim.wait(10)
assert(vim.fn.getreg "/" == last_search and vim.fn.foldclosed(1) == -1, "empty query changed search state")
foldsearch.setup { sync_last_search = true }

vim.cmd "setlocal foldmethod=manual foldminlines=0 foldenable"
vim.api.nvim_buf_set_name(source, vim.fn.tempname() .. ".log")
vim.cmd "2,3fold"
foldsearch.fold_search_expr "error"
foldsearch.fold_end()
assert(vim.fn.foldclosed(2) == 2 and vim.fn.foldclosedend(2) == 3, "original folds not restored")
vim.wo.foldenable = false
foldsearch.fold_search_expr "error"
foldsearch.fold_end()
assert(not vim.wo.foldenable, "foldenable not restored")
print(string.format("FoldSearch: %d comparisons with / passed", checks))
