if vim.g.loaded_fzf_foldsearch then return end
vim.g.loaded_fzf_foldsearch = true

vim.api.nvim_create_user_command('FzfFoldSearch', function()
  require('fzf-foldsearch').fold_search()
end, { desc = 'Fzf fold search' })

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

vim.api.nvim_create_user_command('FzfViewerOpen', function()
  require('fzf-foldsearch').viewer_open()
end, { desc = 'Open klogg-style viewer for current buffer' })

vim.api.nvim_create_user_command('FzfViewerAdd', function(args)
  local inclusive = args.args ~= 'exclude'
  require('fzf-foldsearch').viewer_add(inclusive)
end, { nargs = '?', desc = 'Add pattern to viewer (include|exclude, default: include)' })

vim.api.nvim_create_user_command('FzfViewerRemove', function(args)
  require('fzf-foldsearch').viewer_remove(tonumber(args.args) or 1)
end, { nargs = 1, desc = 'Remove viewer pattern by index' })

vim.api.nvim_create_user_command('FzfViewerClear', function()
  require('fzf-foldsearch').viewer_clear()
end, { desc = 'Clear all viewer patterns' })

vim.api.nvim_create_user_command('FzfViewerClose', function()
  require('fzf-foldsearch').viewer_close()
end, { desc = 'Close viewer' })

vim.api.nvim_create_user_command('FzfViewerContextAdd', function(args)
  require('fzf-foldsearch').viewer_context_add(tonumber(args.args) or 0)
end, { nargs = 1, desc = 'Change viewer context' })

vim.api.nvim_create_user_command('FzfViewerList', function()
  require('fzf-foldsearch').viewer_list()
end, { desc = 'List active viewer patterns' })

vim.api.nvim_create_user_command('FzfViewerJumpToResult', function()
  require('fzf-foldsearch').jump_to_result()
end, { desc = 'Jump from source to corresponding result line' })

vim.api.nvim_create_user_command('FzfViewerJumpToSource', function()
  require('fzf-foldsearch').jump_to_source()
end, { desc = 'Jump from result to corresponding source line' })
