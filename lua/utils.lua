local M = {}

-- clear commandline
function M.clear_cmdline()
  if vim.opt.cmdheight._value ~= 0 then
    vim.cmd 'normal! :'
  end
end

-- parse file path from full file path
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

return M
