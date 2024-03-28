local config = {}
local utils = require 'utils'

config.options = {
  commit = true,
  loop = true,
  mappings = { 'b', 'c', 'h', 'j', 'k', 'l', 'p', 'q', 's', 'x', 'X' },
  push = {
    working_branch = nil,
    upstream_branch = nil,
  },
  skip_sign = '│',
  skip_sign_color = utils.get_background_color(),
  track_untracked = false,
}

function config.set_options(custom_opts)
  config.options = vim.tbl_deep_extend('force', config.options, custom_opts or {})
  config.options.push = utils.validate_table_option(config.options.push, 'working_branch', 'upstream_branch')
    and config.options.push
end

local function generate_default_mappings(custom_mappings)
  custom_mappings = custom_mappings and custom_mappings or {}
  local defaults = {}
  defaults['b'] = 'update_upstream_branch'
  defaults['c'] = 'commit'
  defaults['h'] = 'prev_file'
  defaults['j'] = 'next_hunk'
  defaults['k'] = 'prev_hunk'
  defaults['l'] = 'next_file'
  defaults['p'] = 'preview_hunk'
  defaults['q'] = 'quit'
  defaults['s'] = 'stage'
  defaults['x'] = 'skip_hunk'
  defaults['X'] = 'skip_node'

  local t = {}
  local keys = config.options.mappings
  for i = 1, #keys do
    if defaults[keys[i]] ~= nil then
      t[keys[i]] = defaults[keys[i]]
    end
  end
  return t
end

function config.reset_mappings(buf)
  local default_mappings = generate_default_mappings()
  for key, _ in pairs(default_mappings) do
    vim.api.nvim_buf_del_keymap(buf, 'n', key)
  end
end

local function map_key(key, func)
  local buf = vim.fn.bufnr()
  local prefix = [[lua require('gitflow').]]
  local lua_cmd = prefix .. func .. '()'
  local cmd = '<cmd>' .. lua_cmd .. '<CR>'
  local opts = { silent = true, noremap = true }
  vim.api.nvim_buf_set_keymap(buf, 'n', key, cmd, opts)
end

function config.set_mappings(custom_mappings)
  if custom_mappings ~= nil then
    for key, val in pairs(custom_mappings) do
      map_key(key, val)
    end
  else
    local default_mappings = generate_default_mappings()
    for key, val in pairs(default_mappings) do
      map_key(key, val)
    end
  end
end

function config.print()
  print 'lo and behold'
end

return config
