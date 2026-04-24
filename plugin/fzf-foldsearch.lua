if vim.g.loaded_fzf_foldsearch then return end
vim.g.loaded_fzf_foldsearch = true

vim.api.nvim_create_user_command('FzfFoldSearch', function()
  require('fzf-foldsearch').fold_search()
end, { desc = 'Fzf fold search' })

vim.api.nvim_create_user_command('FzfFoldSearchExpr', function(args)
  require('fzf-foldsearch').fold_search_expr(args.args)
end, { nargs = 1, desc = 'Fold search with explicit rg regex pattern' })

vim.api.nvim_create_user_command('FzfFoldEnd', function()
  require('fzf-foldsearch').fold_end()
end, { desc = 'End fzf fold search' })

vim.api.nvim_create_user_command('FzfFoldContextAdd', function(args)
  require('fzf-foldsearch').fold_context_add(tonumber(args.args) or 0)
end, { nargs = 1, desc = 'Change fold context' })

vim.api.nvim_create_user_command('FzfFoldExtractMatched', function()
  require('fzf-foldsearch').extract_matched()
end, { desc = 'Extract matched lines to new buffer' })

vim.api.nvim_create_user_command('FzfFoldExtractVisible', function()
  require('fzf-foldsearch').extract_visible()
end, { desc = 'Extract visible (matched + context) lines to new buffer' })

vim.api.nvim_create_user_command('FuzzLoggOpen', function()
  require('fzf-foldsearch').fuzzlogg_open()
end, { desc = 'Open FuzzLogg for current buffer' })

vim.api.nvim_create_user_command('FuzzLoggAdd', function(args)
  local inclusive = args.args ~= 'exclude'
  require('fzf-foldsearch').fuzzlogg_add(inclusive)
end, { nargs = '?', desc = 'Add FuzzLogg pattern (include|exclude, default: include)' })

vim.api.nvim_create_user_command('FuzzLoggRemove', function(args)
  require('fzf-foldsearch').fuzzlogg_remove(tonumber(args.args) or 1)
end, { nargs = 1, desc = 'Remove FuzzLogg pattern by index' })

vim.api.nvim_create_user_command('FuzzLoggClear', function()
  require('fzf-foldsearch').fuzzlogg_clear()
end, { desc = 'Clear all FuzzLogg patterns' })

vim.api.nvim_create_user_command('FuzzLoggClose', function()
  require('fzf-foldsearch').fuzzlogg_close()
end, { desc = 'Close FuzzLogg' })

vim.api.nvim_create_user_command('FuzzLoggContextAdd', function(args)
  require('fzf-foldsearch').fuzzlogg_context_add(tonumber(args.args) or 0)
end, { nargs = 1, desc = 'Change FuzzLogg context' })

vim.api.nvim_create_user_command('FuzzLoggList', function()
  require('fzf-foldsearch').fuzzlogg_list()
end, { desc = 'List active FuzzLogg patterns' })

vim.api.nvim_create_user_command('FuzzLoggJumpToResult', function()
  require('fzf-foldsearch').fuzzlogg_jump_to_result()
end, { desc = 'Jump from source to corresponding FuzzLogg result line' })

vim.api.nvim_create_user_command('FuzzLoggJumpToSource', function()
  require('fzf-foldsearch').fuzzlogg_jump_to_source()
end, { desc = 'Jump from FuzzLogg result to source line' })

vim.api.nvim_create_user_command('FuzzLoggSave', function(args)
  require('fzf-foldsearch').fuzzlogg_save(args.args ~= '' and args.args or nil)
end, { nargs = '?', desc = 'Save current FuzzLogg session as composition' })

vim.api.nvim_create_user_command('FuzzLoggLoad', function(args)
  require('fzf-foldsearch').fuzzlogg_load(args.args)
end, { nargs = 1, desc = 'Load composition or RPN expression into FuzzLogg' })

vim.api.nvim_create_user_command('FuzzLoggPanel', function()
  require('fzf-foldsearch').fuzzlogg_panel()
end, { desc = 'Open FuzzLogg panel (patterns & compositions)' })

vim.api.nvim_create_user_command('FuzzLoggImport', function(args)
  require('fzf-foldsearch.importer').import(vim.fn.expand(args.args))
end, { nargs = 1, complete = 'file', desc = 'Import .fl file into FuzzLogg store' })
