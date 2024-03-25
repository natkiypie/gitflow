local Gitflow = {}

local utils = require 'utils'
local config = require 'gitflow.config'
local list, orig, skipped_files

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

local function orig_buf_visited(id)
  if not vim.tbl_contains(utils.get_modified_files(), get_orig_path()) then
    return
  end
  if id == get_orig_path() then
    orig.visited = true
  end
end

local function run(id)
  vim.cmd(string.gsub('edit path', 'path', id))
  list_orig_buf(id)
  orig_buf_visited(id)
  vim.bo.modifiable = false
  go_to_first_hunk(id)
  config.set_mappings()
end

local function delete_augroup()
  if vim.fn.exists '#Gitflow' == 1 then
    vim.api.nvim_del_augroup_by_name 'Gitflow'
  else
    return
  end
end

local function reset_mappings()
  if orig.visited then
    config.reset_mappings(orig.buf)
  end
end

local function quit()
  utils.remove_all_signs()
  vim.api.nvim_win_set_buf(0, orig.buf)
  vim.fn.setpos('.', orig.cur)
  vim.cmd 'setlocal buflisted'
  vim.bo.modifiable = true
  delete_augroup()
  list = nil
  skipped_files = nil
  reset_mappings()
  reset_plugin()
end

-- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING

local function get_git_branches()
  local branches = vim.fn.systemlist 'git branch --list'
  local cleaned_branches = {}
  for _, branch in ipairs(branches) do
    local cleaned_branch = branch:gsub('%*%s*', ''):gsub('^%s*(.-)%s*$', '%1')
    table.insert(cleaned_branches, cleaned_branch)
  end
  return cleaned_branches
end

-- function M.is_git_repo()
--   return not set_is_empty(find_git_repo())
-- end

-- function M.clear_cmdline()
--   if vim.opt.cmdheight._value ~= 0 then
--     vim.cmd 'normal! :'
--   end
-- end

-- function M.git_working_tree_clean()
--   local status = vim.fn.systemlist { 'git', 'status', '--porcelain=v1' }
--   return set_is_empty(status)
-- end

-- function M.get_git_branch()
--   local branch = vim.fn.system "git branch --show-current 2> /dev/null | tr -d '\n'"
--   if branch ~= '' then
--     return branch
--   end
-- end

-- usercmd('GitMergeUpdate', function()
--   if not userfn.is_git_repo() then
--     return
--   end
--   userfn.clear_cmdline()
--   if not userfn.git_working_tree_clean() then
--     return vim.notify('There are still changes not staged for commit', vim.log.levels.INFO, {})
--   end
--   if userfn.get_git_branch() == 'update' then
--     vim.cmd [[
--       Git checkout main
--       Git merge update
--       Git push
--       Git checkout update
--     ]]
--   else
--     return vim.notify('Not on branch update', vim.log.levels.INFO, {})
--   end
-- end, {})

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
--   return vim.tbl_is_empty(status)
-- end

-- local function get_git_branch()
--   local branch = vim.fn.system "git branch --show-current 2> /dev/null | tr -d '\n'"
--   if branch ~= '' then
--     return branch
--   end
-- end

-- local function get_git_branch()
--   local branch = vim.fn.system "git branch --show-current 2> /dev/null | tr -d '\n'"
--   if branch ~= '' then
--     return branch
--   end
-- end

local function get_git_branch()
  local branch = vim.fn.system 'git rev-parse --abbrev-ref HEAD'
  branch = branch:gsub('^%s*(.-)%s*$', '%1')
  return branch
end

-- local function get_main_git_branch()
--   local main_branch_ref = vim.fn.system 'git symbolic-ref --short refs/remotes/origin/HEAD'
--   local main_branch = main_branch_ref:match '.*/(.*)'
--   main_branch = main_branch:gsub('^%s*(.-)%s*$', '%1')
--   return main_branch
-- end

local function push(branch)
  local current_branch = get_git_branch()
  vim.cmd(string.gsub('Git checkout *', '*', branch))
  vim.cmd(string.gsub('Git merge *', '*', current_branch))
  vim.cmd 'Git push'
  vim.cmd(string.gsub('Git checkout *', '*', current_branch))
end

function Gitflow.return_branch()
  local line = vim.fn.line '.'
  local branch = vim.fn.getline(line)
  if get_git_branch() == 'main' or get_git_branch() == 'master' then
    vim.cmd 'Git push'
  else
    push(branch)
  end
  vim.cmd 'close'
end

local function create_floating_window()
  local branches = get_git_branches()
  local content = {
    'Select a branch to merge into:',
    '',
  }
  for _, branch in ipairs(branches) do
    table.insert(content, branch)
  end
  local max_length = 0
  for _, line in ipairs(content) do
    max_length = math.max(max_length, #line)
  end
  local width = max_length + 2 -- Add padding
  local height = #content
  local row = 1
  local col = math.floor((vim.o.columns - width) / 2)
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'single',
  }
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, true, opts)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  vim.api.nvim_win_set_cursor(winid, { 3, 0 })
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_keymap(
    bufnr,
    'n',
    '<CR>',
    "<Cmd>lua require('gitflow').return_branch()<CR>",
    { noremap = true, silent = true }
  )
end

local function create_commit_autocmd(fn)
  local group = vim.api.nvim_create_augroup('Gitflow', { clear = true })
  vim.api.nvim_create_autocmd('BufWinLeave', {
    pattern = 'COMMIT_EDITMSG',
    callback = function()
      vim.schedule(function()
        fn()
        if fn == quit then
          create_floating_window()
        end
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
  utils.remove_all_signs()
  list = utils.create_list(skipped_files, data)
  run(skipped_files[1])
  skipped_files = {}
  delete_augroup()
end

local function is_last_file()
  return vim.tbl_count(list) == 1
end

local function has_skipped_files()
  return #skipped_files > 0
end

local function commit_with_action(action)
  create_commit_autocmd(action)
  vim.cmd 'Git commit'
end

local function handle_last_file(id)
  utils.delete_list_node(list, id)
  if vim.tbl_isempty(utils.get_staged_files()) then
    return quit()
  end
  local action = has_skipped_files() and reinitialize_list or quit
  commit_with_action(action)
end

local function mark_skipped(hunk)
  local bufnr = vim.api.nvim_get_current_buf()
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
  local files = utils.get_modified_files()
  if vim.tbl_isempty(files) then
    print 'NO MODIFIED FILES'
    return
  end
  if not plugin_started() then
    return
  end
  list = utils.create_list(files, data)
  skipped_files = {}
  orig = {
    buf = vim.api.nvim_get_current_buf(),
    cur = vim.fn.getcurpos(),
    visited = false,
  }
  load_bufs(files)
  run(files[1])
end

function Gitflow.start()
  initialize()
end

-- function Gitflow.setup(custom_opts)
--   -- THE FOLLOWING WILL GO IN SETUP FUNCTION
--   -- config.set_options(custom_opts)
--   -- opts = config.options
--   config.set_mappings()
-- end

function Gitflow.next_file()
  local id = utils.get_file_path()
  run(list[id].next)
end

function Gitflow.prev_file()
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
  vim.cmd 'Git commit'
end

function Gitflow.quit()
  quit()
end

-- Print
function Gitflow.print()
  print 'lo and behold'
end

return Gitflow
