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

local function create_commit_autocmd(fn)
  local group = vim.api.nvim_create_augroup('Gitflow', { clear = true })
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
  if not opts.loop then
    action = quit
  end
  create_commit_autocmd(action)
  vim.cmd 'Git commit | startinsert'
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
    visited = false,
  }
  load_bufs(files)
  run(files[1])
end

function Gitflow.start()
  initialize()
end

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
  vim.cmd 'Git commit | startinsert'
end

function Gitflow.quit()
  quit()
end

function Gitflow.setup(custom_opts)
  config.set_options(custom_opts)
  opts = config.options
end

-- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING -- TESTING

local function get_working_branch()
  local branch = vim.fn.system "git branch --show-current 2> /dev/null | tr -d '\n'"
  if branch ~= '' then
    return branch
  end
end

local function on_working_branch()
  return opts.push['working_branch'] == get_working_branch()
end

function Gitflow.return_selection(responses)
  local line = vim.fn.line '.'
  local selection = vim.fn.getline(line)
  utils.parse_selection(selection, responses)
end

-- Print
function Gitflow.print()
  local question = 'You\'re not on branch "' .. opts.push['working_branch'] .. '". What would you like to do?'

  local responses = {
    {
      '1. switch branches to "' .. opts.push['working_branch'] .. '"',
      '2. set working_branch to "' .. get_working_branch() .. '"',
      "3. set gitflow's push option to false",
      '4. quit',
    },
    {
      function()
        print 'switch branches'
      end,
      function()
        print 'set working_branch'
      end,
      function()
        print 'push = false'
      end,
      function()
        print 'quit'
      end,
    },
  }

  if not on_working_branch() then
    utils.create_floating_window(question, responses)
  end
end

return Gitflow
