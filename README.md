# Gitflow 🔀

## USE CASE

1. User presses keymap

   - Gets list of modified files
   - Opens first file in diff view
   - Moves cursor to first hunk

2. Once all hunks are either staged or skipped

   - Opens next file in list of modified files

3. Once all files have been reviewed (all hunks in all files either staged or skipped)
   - Opens commit message
4. Once commit is complete
   - If there are any modified files remaining, repeat.
5. Once all modifications have been staged & committed
   - Closes loop
6. In addition
   - User can close loop at any time
   - User is able to skip to next file at any time

## ALGORITHM

#### Initialize

- get list of unstaged files using git:\
  `vim.fn.systemlist 'git diff --name-only'` -> `{string, n}`
- get list of hunk lnums for each file:

```Lua
function()
  local file = '/home/natkiypie/.dotfiles/natkiypie/.config/nvim/lua/custom/mappings.lua'

  local ls = vim.fn.systemlist(
    string.gsub('git diff --unified=0 *', '*', file) .. [[ | grep -Po '^\+\+\+ ./\K|^@@ -[0-9]+(,[0-9]+)? \+\K[0-9]+']]
  )
  local lnums = toNumber(ls)
  print(vim.inspect(lnums))
end
```

- assign modified_file tables values:

```Lua
modified_file = {
  file = unstaged_files[n],
  hunks = {lnums},
  skips = {},
}
```

- assign modified_files table values:

```Lua
modified_files = {
  files = {mf, mf+1, ... },
  skipped_files = {},
}
```

#### Run

- here's what's up. and we need to find out at which point in the process this goes
- reuse git functionality to update hunks table and filter out values found in skips table
- example using global variables `lnums` & `skips`:

```Lua
local lnums = { 95, 145, 122 }
local skips = { 95 }

table.insert(skips, 122)

local function set_contains(t, v)
  for i = 1, #t do
    if t[i] == v then
      return true
    end
  end
  return false
end

local function predicate(v)
  return not set_contains(skips, v)
end

local modified_file = {
  file = { 'a.lua', 'b.lua', 'c.lua' },
  hunks = vim.tbl_filter(predicate, lnums),
  skips = skips,
}

print(vim.inspect(modified_file.hunks))
print(vim.inspect(modified_file.skips))
```

- example using `deep copy`:

```Lua

local copy, modified_file

modified_file = {
  file = { 'a.lua', 'b.lua', 'c.lua' },
  hunks = { 95, 145, 122 },
  skips = { 95 },
}

-- Here is a simple recursive implementation of a deep copy that additionally handles metatables and avoids the __pairs metamethod (http://lua-users.org/wiki/CopyTable):
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

local function set_contains(t, v)
  for i = 1, #t do
    if t[i] == v then
      return true
    end
  end
  return false
end

local function predicate(v)
  return not set_contains(modified_file['skips'], v)
end

copy = deepcopy(modified_file)

copy['hunks'] = vim.tbl_filter(predicate, modified_file['hunks'])

modified_file = copy

print(vim.inspect(modified_file['hunks']))
```

- we can do the same with files and skipped_files in the modified_files table
- the tables might look like this:

```Lua
modified_file = {
  file = unstaged_files[n],
  hunks = filter_table(skips),
  skips = {},
}
```

and

```Lua
modified_files = {
  files = {mf, mf+1, ... },
  skipped_files = {},
}
```

- split modified_files[n].file & its diff in the window buffer:\
  `:Gvdiffsplit`
- set cursor position to modified_files[n].hunks[n]:\
  `vim.fn.setpos('.', { [bufnr], [lnum], [col] })`
- if staged...
- if skipped:
  - move lnum from hunks to skips
    - get cursor position
    - insert value into skips:\
      `table.insert(list, value)`
- once all hunks in file are staged/skipped:
  - close (if no more hunks) or go to next file:
    `vim.cmd 'edit file'` ???
  - split modified_files[n+1].file & its diff in the window buffer
    - Note: because we are removing files from the files table in modified_files, we may only have to edit modified_files[1] on every update
  - rinse & repeat

#### Update

- if modified_file.skips & modified_file.hunks are both empty:
  - remove from modified_files table
- if modified_file.skips is not empty:
  - move file from files to skipped_files
  - modified_file.hunks = modified_file.skips
- if files is empty & skipped_files is not:
  - files = skipped_files
  - skipped_files = {}
  - open commit message
- if files & skipped_files are both empty:
  - provide option to push and end program

#### Edge Cases

- user skips file (not hunk):
  - simply move file to skipped files?
  - if that's the case, skipped_files will have to act like a que, and the skipped file needs to be put at the end
- untracked files

## USEFUL COMMANDS

#### GitSigns

- `gitsigns.next_hunk()`
- `gitsigns.stage_hunk()`

#### Nvim / Git

- Get list of untracked files:\
  `vim.fn.systemlist 'git diff --name-only'` -> `{string, n}`
- List number of hunks in a specific file (pass the result to findFirstNumber util function - found below):\
  `vim.fn.systemlist 'git diff --numstat [file]'` -> `string` -> `findFirstNumber(string)` -> `number`

- Get list of staged files:\
   `vim.fn.systemlist 'git diff --cached --name-only` -> `{string, n}`\
  or\
   `vim.fn.systemlist 'git diff --staged --name-only` -> `{string, n}`
- List number of staged files:\
   `vim.fn.systemlist 'git diff --cached --numstat | wc -l'` -> `number`\
  or\
   `vim.fn.systemlist 'git diff --staged --numstat | wc -l'` -> `number`
- Get buf number:\
  `vim.fn.bufnr()`
- Get line numbers of hunks:\
  `git diff --unified=0 [file] | grep -Po '^\+\+\+ ./\K|^@@ -[0-9]+(,[0-9]+)? \+\K[0-9]+'`
- Set cursor position:\
  `vim.fn.setpos('.', { [bufnr], [lnum], [col] })`
- Close buffer after exiting loop:\
  `vim.cmd 'bd [file name]'`
- See for table methods:
  `h vim.tbl`

#### Lua / Data structures

- Find the first integer in a string:

```Lua
local findFirstNumber = function(inputString)
  local number = inputString:match '%d+'
  return tonumber(number)
end
```

- Converts list string to list number

```Lua
local function toNumber(ls)
  local t = {}
  for _, s in ipairs(ls) do
    if type(s) ~= 'string' then
      return
    end
    table.insert(t, tonumber(s))
  end
  return t
end
```

- Make copy of table:
- Create a que:

#### VimFugitive

- `[c` Jump to previous hunk, expanding inline diffs
  automatically. (This shadows the Vim built-in |[c|
  that provides a similar operation in |diff| mode.)
- `]c` Jump to next hunk, expanding inline diffs
  automatically. (This shadows the Vim built-in |]c|
  that provides a similar operation in |diff| mode.)
- `s` Stage (add) the file or hunk under the cursor.

## NOTES

- see: [how to write neovim plugin in lua](https://www.2n.pl/blog/how-to-write-neovim-plugins-in-lua)

## TODO

- [ ] Make plugin
