local Gitflow = {}

local utils = require 'utils'
local config = require 'gitflow.config'
local list, opts, orig, skipped_files

local function plugin_state()
  local running = false

  local function toggle_state()
    if running then
      return false
    end
    running = true
    return true
  end

  local function reset_state()
    running = false
  end

  return toggle_state, reset_state
end

local plugin_started, reset_plugin = plugin_state()

local data = {
  id = '',
  hunks = function(self)
    return utils.get_hunks(self.id)
  end,
  skipped_hunks = {},
  filtered_hunks = function(self)
    return utils.filter(utils.contains, self:hunks(), self.skipped_hunks)
  end,
  list_hunks = function(self)
    return utils.create_list(self:filtered_hunks(), {})
  end,
}

local function get_orig_path()
  local id = vim.api.nvim_buf_get_name(orig.buf)
  local path = utils.parse_path(id)
  return path
end

local function go_to_first_hunk(id)
  local position = { vim.fn.bufnr(), list[id].data:filtered_hunks()[1], 0 }
  vim.fn.setpos('.', position)
end

local function list_orig_buf(id)
  if id ~= get_orig_path() then
    vim.cmd 'setlocal nobuflisted'
  end
end

local function run(id)
  vim.cmd(string.gsub('edit path', 'path', id))
  list_orig_buf(id)
  vim.bo.modifiable = false
  go_to_first_hunk(id)
  config.set_mappings()
end

local function delete_commit_augroup()
  -- if vim.fn.exists '#GitflowCommit' == 1 then
  --   vim.api.nvim_del_augroup_by_name 'GitflowCommit'
  -- else
  --   return
  -- end
  if vim.fn.exists '#GitflowCommit' == 0 then
    return
  end
  vim.api.nvim_del_augroup_by_name 'GitflowCommit'
end

local function delete_cursor_augroup()
  if vim.fn.exists '#RestrictCursor' == 1 then
    vim.api.nvim_del_augroup_by_name 'RestrictCursor'
  else
    return
  end
end

local function return_file_settings()
  config.reset_mappings(0)
  vim.bo.modifiable = true
end

local function push()
  vim.cmd(string.gsub('silent Git checkout *', '*', opts.upstream_branch))
  vim.cmd(string.gsub('silent Git merge *', '*', opts.working_branch))
  vim.cmd 'Git push'
  vim.cmd(string.gsub('silent Git checkout *', '*', opts.working_branch))
end

local function quit()
  return_file_settings()
  utils.remove_all_signs()
  vim.api.nvim_win_set_buf(0, orig.buf)
  vim.fn.setpos('.', orig.cur)
  vim.cmd 'setlocal buflisted'
  vim.bo.modifiable = true
  delete_commit_augroup()
  list = nil
  skipped_files = nil
  reset_plugin()
  -- SMELL HERE
  -- if opts.push then
  --   push()
  -- end
end

-- OKAY, THIS ONE WORKS... OR WE CAN WORK WITH IT.
-- local function create_autocmd()
--   vim.api.nvim_create_autocmd('BufWritePost', {
--     pattern = 'COMMIT_EDITMSG',
--     callback = function()
--       vim.schedule(function()
--         utils.clear_cmdline()
--         print 'commit written'
--       end)
--     end,
--   })
-- end

local function create_commit_autocmd(fn)
  local group = vim.api.nvim_create_augroup('GitflowCommit', { clear = true })
  vim.api.nvim_create_autocmd('BufWinLeave', {
    pattern = 'COMMIT_EDITMSG',
    callback = function()
      vim.schedule(function()
        fn()
        -- if opts.push and fn == quit then
        --   push()
        -- end
      end)
    end,
    group = group,
  })
end

local function go_to_hunk(direction)
  local bufnr = vim.fn.bufnr()
  local id = utils.get_file_path()
  local hunks = list[id] and list[id].data:list_hunks() or {}
  local curpos = vim.fn.getcurpos()[2]
  local target_hunk = hunks[curpos] and hunks[curpos][direction]
  if target_hunk then
    vim.fn.setpos('.', { bufnr, target_hunk, 0 })
  end
end

local function last_hunk(id)
  return #list[id].data:filtered_hunks() == 1
end

local function has_skipped_hunks(id)
  return #list[id].data.skipped_hunks > 0
end

local function stage_hunk(bufnr, hunks, curpos)
  vim.cmd 'Gitsigns stage_hunk'
  local position = { bufnr, 0, 0 }
  if hunks[curpos] and hunks[curpos].next then
    position[2] = hunks[curpos].next
  end
  return vim.fn.setpos('.', position)
end

local function reinitialize_list()
  return_file_settings()
  utils.remove_all_signs()
  list = utils.create_list(skipped_files, data)
  run(skipped_files[1])
  skipped_files = {}
  delete_commit_augroup()
end

local function is_last_file()
  return vim.tbl_count(list) == 1
end

local function has_skipped_files()
  return #skipped_files > 0
end

local function commit_with_action(action)
  if not opts.loop then
    action = quit
  end
  create_commit_autocmd(action)
  if opts.start_insert then
    vim.cmd 'Git commit | startinsert'
  else
    vim.cmd 'Git commit'
  end
end

local function handle_last_file(id)
  utils.delete_list_node(list, id)
  if vim.tbl_isempty(utils.get_staged_files()) then
    return quit()
  end
  if opts.commit then
    local action = has_skipped_files() and reinitialize_list or quit
    return commit_with_action(action)
  end
  quit()
end

local function define_highlight_group()
  local highlight_group = {
    fg = opts.skip_sign_color,
  }
  vim.api.nvim_set_hl(0, 'SkipHLGroup', highlight_group)
end

local function mark_skipped(hunk)
  local bufnr = vim.api.nvim_get_current_buf()
  define_highlight_group()
  vim.fn.sign_define('Skip', { text = opts.skip_sign, texthl = 'SkipHLGroup' })
  if type(hunk) == 'number' then
    utils.add_sign(bufnr, hunk)
  elseif type(hunk) == 'table' then
    utils.add_signs(bufnr, hunk)
  end
end

local function handle_last_hunk(id)
  vim.cmd 'Gitsigns stage_hunk'
  if has_skipped_hunks(id) then
    table.insert(skipped_files, id)
  end
  if is_last_file() then
    handle_last_file(id)
    return true
  else
    return_file_settings()
    run(list[id].next)
    utils.delete_list_node(list, id)
    return false
  end
end

local function load_bufs(files)
  for _, v in ipairs(files) do
    vim.fn.bufload(vim.fn.bufadd(v))
  end
end

local function initialize()
  if opts.track_untracked then
    utils.track_untracked()
  end
  local files = utils.get_modified_files()
  if vim.tbl_isempty(files) then
    return vim.notify('There are no hunks left to stage.', vim.log.levels.WARN, {})
  end
  if not plugin_started() then
    return
  end
  list = utils.create_list(files, data)
  skipped_files = {}
  orig = {
    buf = vim.api.nvim_get_current_buf(),
    cur = vim.fn.getcurpos(),
  }
  load_bufs(files)
  run(files[1])
end

local function on_working_branch()
  return opts.working_branch == utils.get_working_branch()
end

local function check_working_branch()
  if on_working_branch() then
    return initialize()
  end
  local working_branch = utils.get_working_branch()
  local question = 'You\'re not on branch "' .. opts.working_branch .. '". What would you like to do?'

  local responses = {
    {
      '1. set working_branch to "' .. working_branch .. '"',
      "2. set gitflow's push option to false",
      '3. quit',
    },
    {
      function()
        opts.working_branch = working_branch
        vim.cmd 'close'
        initialize()
        delete_cursor_augroup()
      end,
      function()
        opts.push = false
        vim.cmd 'close'
        initialize()
        delete_cursor_augroup()
      end,
      function()
        vim.cmd 'close'
        delete_cursor_augroup()
      end,
    },
  }
  utils.create_floating_window(question, responses)
end

local function build_branch_functions(branches)
  local fns = {}
  for _, v in ipairs(branches) do
    local fn = function()
      opts.upstream_branch = v
      vim.cmd 'close'
      delete_cursor_augroup()
    end
    table.insert(fns, fn)
  end
  return fns
end

function Gitflow.update_upstream_branch()
  if not opts.push then
    return
  end
  local branches = utils.get_git_branches()
  local fns = build_branch_functions(branches)
  local ordered_branches = utils.prepend_numbers(branches)
  local question = 'upstream_branch is set to "' .. opts.upstream_branch .. '". Set upstream_branch to:'
  local responses = {
    ordered_branches,
    fns,
  }
  utils.create_floating_window(question, responses)
end

function Gitflow.return_selection(responses)
  local line = vim.fn.line '.'
  local selection = vim.fn.getline(line)
  utils.parse_selection(selection, responses)
end

function Gitflow.start()
  if opts.push then
    return check_working_branch()
  end
  initialize()
end

function Gitflow.next_file()
  return_file_settings()
  local id = utils.get_file_path()
  run(list[id].next)
end

function Gitflow.prev_file()
  return_file_settings()
  local id = utils.get_file_path()
  run(list[id].prev)
end

function Gitflow.next_hunk()
  go_to_hunk 'next'
end

function Gitflow.prev_hunk()
  go_to_hunk 'prev'
end

function Gitflow.skip_node()
  local id = utils.get_file_path()
  table.insert(skipped_files, id)
  if is_last_file() then
    handle_last_file(id)
    return
  end
  Gitflow.next_file()
  utils.delete_list_node(list, id)
end

function Gitflow.skip_hunk()
  local id = utils.get_file_path()
  local skipped_hunks = list[id].data.skipped_hunks
  local lnum = vim.fn.getcurpos()[2]
  local hunks = utils.get_hunk_pairs(id)
  local output_table = utils.process_table(hunks)
  local hunk = utils.find_hunk_range(lnum, output_table)
  if last_hunk(id) then
    mark_skipped(hunk)
    Gitflow.skip_node()
  else
    mark_skipped(hunk)
    go_to_hunk 'next'
    table.insert(skipped_hunks, lnum)
  end
end

function Gitflow.preview_hunk()
  vim.cmd 'Gitsigns preview_hunk'
end

function Gitflow.stage()
  local id = utils.get_file_path()
  local bufnr = vim.fn.bufnr()
  local hunks = list[utils.get_file_path()] and list[utils.get_file_path()].data:list_hunks() or {}
  local curpos = vim.fn.getcurpos()[2]
  if last_hunk(id) then
    if handle_last_hunk(id) then
      return
    end
  else
    return stage_hunk(bufnr, hunks, curpos)
  end
end

function Gitflow.commit()
  if opts.start_insert then
    vim.cmd 'Git commit | startinsert'
  else
    vim.cmd 'Git commit'
  end
end

function Gitflow.quit()
  quit()
end

function Gitflow.setup(custom_opts)
  config.set_options(custom_opts)
  opts = config.options
end

-- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING

-- local function find_git_repo()
--   local git_repo = vim.fs.find('.git', {
--     upward = true,
--     -- stop = vim.uv.os_homedir(),
--     stop = vim.loop.os_homedir(),
--     type = 'directory',
--     path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
--   })
--   return git_repo
-- end

-- local function is_git_repo()
--   return not vim.tbl_isempty(find_git_repo())
-- end

-- local function clear_cmdline()
--   if vim.opt.cmdheight._value ~= 0 then
--     vim.cmd 'normal! :'
--   end
-- end

-- local function git_working_tree_clean()
--   local status = vim.fn.systemlist { 'git', 'status', '--porcelain=v1' }
--   return vim.tbl_isempty(status)
-- end

-- TESTING TESTING TESTING TESING TESTING TESTING TESTING TESING TESTING TESTING TESTING TESING TESTING TESTING TESTING TESING TESTING TESTING

local commitbufwrite = false

local function test_reinitialize()
  utils.clear_cmdline()
  print 'reinitialize list'
end

local function test_push()
  print 'pushing'
end

local function test_quit()
  utils.clear_cmdline()
  print 'quitting'
  if commitbufwrite then
    test_push()
  end
  delete_commit_augroup()
end

local group = vim.api.nvim_create_augroup('GitflowCommit', { clear = true })

local function commit_autocmd(fn)
  vim.api.nvim_create_autocmd('BufWinLeave', {
    pattern = 'COMMIT_EDITMSG',
    callback = function()
      vim.schedule(function()
        fn()
      end)
    end,
    group = group,
  })
end

local function create_autocmd()
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = 'COMMIT_EDITMSG',
    callback = function()
      commitbufwrite = opts.push
      -- vim.schedule(function()
      -- end)
    end,
    group = group,
  })
end

function Gitflow.print()
  -- print 'lo and behold'
  group = vim.api.nvim_create_augroup('GitflowCommit', { clear = true })
  create_autocmd()
  commit_autocmd(test_quit)
  vim.cmd 'Git commit'
end

return Gitflow
