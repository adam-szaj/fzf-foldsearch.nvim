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
