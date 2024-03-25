-- GitFlow: A plugin that helps streamline git workflow
-- Last Change:  2024 Jan 22
-- Maintainer:   Nate Pierce <natkiypie@protonmail.com>
-- License:      GNU General Public License v3.0

local usercmd = vim.api.nvim_create_user_command

if vim.g.loaded_gitflow == 1 then
  return
end

usercmd('Gitflow', function()
  require('gitflow').start()
end, {})

usercmd('Hprint', function()
  require('gitflow').print()
end, {})

vim.g.loaded_gitflow = 1
