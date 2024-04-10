local M = {}

-- Get get window's background color
function M.get_background_color()
  return vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID 'Normal'), 'bg#')
end

-- Validate table's keys hold values
function M.validate_table_option(table_option, key1, key2)
  if table_option[key1] and table_option[key2] then
    return true
  end
  return false
end

-- Clear commandline
function M.clear_cmdline()
  if vim.opt.cmdheight._value ~= 0 then
    vim.cmd 'normal! :'
  end
end

-- Prepend numbers to list of strings
function M.prepend_numbers(t)
  local modified_table = {}
  for i, v in ipairs(t) do
    modified_table[i] = i .. '. ' .. v
  end
  return modified_table
end

-- Parse file path from full file path
function M.parse_path(input)
  local pattern = 'lua/gitflow/.+'
  return string.match(input, pattern)
end

-- Get list of unstaged files
function M.get_modified_files()
  return vim.fn.systemlist 'git diff --name-only'
end

-- Get list of staged files
function M.get_staged_files()
  return vim.fn.systemlist 'git diff --cached --name-only'
end

-- Get file path
function M.get_file_path()
  local path = vim.fn.expand '%:r' .. '.' .. vim.fn.expand '%:e'
  return path
end

-- Converts list string to list number
function M.lstr_to_lnum(ls)
  local t = {}
  for _, s in ipairs(ls) do
    local hunk = tonumber(s)
    if hunk == 0 then
      hunk = 1
    end
    table.insert(t, hunk)
  end
  return t
end

-- Convert list of strings to list of numbers
function M.convert_list(lstr)
  local lnum = {}
  for _, str in ipairs(lstr) do
    if string.find(str, ',') then
      local subnum = {}
      for num in str:gmatch '%d+' do
        table.insert(subnum, tonumber(num))
      end
      table.insert(lnum, subnum)
    else
      table.insert(lnum, tonumber(str))
    end
  end
  return lnum
end

-- Find the first integer in a string
function M.find_first_num(inputString)
  local number = inputString:match '%d+'
  return tonumber(number)
end

-- Check if value is in set
function M.contains(t, v)
  for i = 1, #t do
    if t[i] == v then
      return true
    end
  end
  return false
end

-- Filter list
function M.filter(p, t, t2)
  local filtered = {}

  if vim.tbl_isempty(t2) then
    return t
  end

  for _, v in ipairs(t) do
    if not p(t2, v) then
      table.insert(filtered, v)
    end
  end

  return filtered
end

-- Set cursor position
function M.set_cursor_position(lnum)
  local bufnr = vim.fn.bufnr(0)
  vim.fn.setpos('.', { bufnr, lnum, 0 })
end

-- Get git working branch
function M.get_working_branch()
  local branch = vim.fn.system "git branch --show-current 2> /dev/null | tr -d '\n'"
  if branch ~= '' then
    return branch
  end
end

function M.get_git_branches()
  local branches = vim.fn.systemlist 'git branch --list'
  local cleaned_branches = {}
  for _, branch in ipairs(branches) do
    local cleaned_branch = branch:gsub('%*%s*', ''):gsub('^%s*(.-)%s*$', '%1')
    table.insert(cleaned_branches, cleaned_branch)
  end
  return cleaned_branches
end

-- Track untracked files
function M.track_untracked()
  local untracked_files = vim.fn.systemlist 'git ls-files --others --exclude-standard'
  for _, u in ipairs(untracked_files) do
    vim.cmd(string.gsub('Git add -N *', '*', u))
  end
end

-- Get lis of hunk lnums for each file
-- Thank you, Jakub Bochenski for the Regex example found here: https://stackoverflow.com/questions/24455377/git-diff-with-line-numbers-git-log-with-line-numbers
function M.get_hunks(file)
  local lstr = vim.fn.systemlist(
    string.gsub('git diff --unified=0 *', '*', file) .. [[ | grep -Po '^\+\+\+ ./\K|^@@ -[0-9]+(,[0-9]+)? \+\K[0-9]+']]
  )
  local hunks = M.lstr_to_lnum(lstr)
  return hunks
end

-- Get list of hunks including pairs of starting and ending lnums
function M.get_hunk_pairs(file)
  local lstr = vim.fn.systemlist(
    string.gsub('git diff --unified=0 *', '*', file)
      .. [[ | grep -Po '^\+\+\+ ./\K|^@@ -[0-9]+(,[0-9]+)? \+\K[0-9]+(,[0-9]+)?(?= @@)']]
  )
  local hunks = M.convert_list(lstr)
  return hunks
end

-- Convert line number pairs to starting lnumb and ending lnumb
function M.process_table(inputTable)
  local result = {}

  for _, item in ipairs(inputTable) do
    if type(item) == 'table' and #item == 2 and item[2] == 0 then
      table.insert(result, item[1])
    elseif type(item) == 'table' and #item == 2 and item[2] > 0 then
      table.insert(result, { item[1], item[2] + item[1] - 1 })
    else
      table.insert(result, item)
    end
  end

  return result
end

-- Find hunk range
function M.find_hunk_range(lnum, hunk)
  for _, item in ipairs(hunk) do
    if type(item) == 'number' then
      if item == lnum then
        return item
      end
    elseif type(item) == 'table' and #item == 2 and type(item[1]) == 'number' then
      if item[1] == lnum then
        return item
      end
    end
  end
  return nil
end

-- Add sign to gutter
function M.add_sign(bufnr, lnum)
  vim.fn.sign_place(0, 'Gitflow', 'Skip', bufnr, { lnum = lnum, priority = 99 })
end

-- Add signs to gutter
function M.add_signs(bufnr, lnums)
  local lines = {}
  for i = lnums[1], lnums[2] do
    table.insert(lines, i)
  end
  for _, line_num in ipairs(lines) do
    vim.fn.sign_place(0, 'Gitflow', 'Skip', bufnr, { lnum = line_num, priority = 99 })
  end
end

function M.remove_all_signs()
  vim.fn.sign_unplace 'Gitflow'
end

-- Create deep copy of table
local function deepcopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[deepcopy(orig_key)] = deepcopy(orig_value)
    end
    setmetatable(copy, deepcopy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end

function M.create_list(t, data)
  local l = {}

  for k, v in ipairs(t) do
    local node = deepcopy {
      data = data,
      next = '',
      prev = '',
    }

    node.data.id = v

    if t[k] then
      node.next = t[k + 1]
      node.prev = t[k - 1]
    end

    if k == 1 then
      node.prev = t[#t]
    end

    if k == #t then
      node.next = t[1]
    end

    l[node.data.id] = node
  end

  return l
end

function M.delete_list_node(l, key)
  l[l[key].prev].next = l[l[key].next].data.id
  l[l[key].next].prev = l[l[key].prev].data.id
  l[key] = nil
end

local function get_number_from_string(str)
  local pattern = '%d+'
  local number = string.match(str, pattern)
  return tonumber(number)
end

function M.parse_selection(selection, responses)
  return responses[2][get_number_from_string(selection)]()
end

local function delete_cursor_augroup()
  if vim.fn.exists '#RestrictCursor' == 0 then
    return
  end
  vim.api.nvim_del_augroup_by_name 'RestrictCursor'
end

local group

local function unrestrict_cursor_movement()
  group = vim.api.nvim_create_augroup('RestrictCursor', { clear = false })
  vim.api.nvim_create_autocmd('BufWinLeave', {
    pattern = {},
    callback = function()
      delete_cursor_augroup()
    end,
    group = group,
  })
end

local function restrict_cursor_movement(start_line)
  group = vim.api.nvim_create_augroup('RestrictCursor', { clear = false })
  vim.api.nvim_create_autocmd('CursorMoved', {
    pattern = '*',
    callback = function()
      if vim.fn.line '.' < start_line then
        vim.fn.cursor(start_line, 1)
      end
    end,
    group = group,
  })
end

function M.create_floating_window(question, responses)
  local content = {
    question,
    '',
  }
  for _, response in ipairs(responses[1]) do
    table.insert(content, response)
  end
  local max_length = 0
  for _, line in ipairs(content) do
    max_length = math.max(max_length, #line)
  end
  local width = max_length + 2
  local height = #content
  local row = 1
  local col = math.floor((vim.o.columns - width) / 2)
  local options = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'single',
  }
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, true, options)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  vim.api.nvim_win_set_cursor(winid, { 3, 0 })
  restrict_cursor_movement(#content - (#responses[1] - 1))
  unrestrict_cursor_movement()
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '', {
    callback = function()
      require('gitflow').return_selection(responses)
    end,
  })
end

return M
