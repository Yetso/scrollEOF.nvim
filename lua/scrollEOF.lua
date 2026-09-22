local M = {}

local mode_disabled = false
local relative_scrolloff = 0

-- Lookup tables built from the `disabled_*` option lists in `setup()`
local disabled = { filetypes = {}, buftypes = {}, modes = {} }

local function to_set(list)
  local set = {}
  for _, val in pairs(list) do
    set[val] = true
  end
  return set
end

local function is_disabled()
  -- Check if plugin is globally disabled via the `enabled` option
  if M.opts.enabled ~= nil then
    local enabled = M.opts.enabled
    if type(enabled) == 'function' then
      enabled = enabled()
    end

    if not enabled then
      return true
    end
  end

  return mode_disabled
    or disabled.filetypes[vim.o.filetype] == true
    or disabled.buftypes[vim.bo.buftype] == true
end

local function check_eof_scrolloff(ev)
  if is_disabled() then
    return
  end

  if M.opts.floating == false then
    local curr_win = vim.api.nvim_win_get_config(0)
    if curr_win.relative ~= '' then
      return
    end
  end

  local win_id = vim.api.nvim_get_current_win()
  if ev ~= nil and ev.event == 'WinScrolled' then
    local win_event = vim.v.event[tostring(win_id)]
    if win_event ~= nil and win_event.topline <= 0 then
      return
    end
  end

  local win_height = vim.fn.winheight(0)
  local win_cur_line = vim.fn.winline()
  local visual_distance_to_eof = win_height - win_cur_line
  --- FIXME: when global scrolloff is set after Neovim startup to be much higher than winheight, window-local scrolloff somehow sets to -1
  local scrolloff = vim.wo[win_id].scrolloff

  if visual_distance_to_eof < scrolloff then
    -- Without this, `gg` `G` can cause the cursor position to be shown incorrectly
    if vim.fn.winsaveview().skipcol ~= 0 then
      vim.fn.winrestview({ skipcol = 0 })
    end
    -- Scroll by screen lines (unlike adding to `topline`), so closed folds count as one line
    local ctrl_e = vim.api.nvim_replace_termcodes('<C-e>', true, false, true)
    vim.cmd('normal! ' .. (scrolloff - visual_distance_to_eof) .. ctrl_e)
  end
end

local default_opts = {
  pattern = '*',
  insert_mode = false,
  floating = true,
  disabled_filetypes = { 'terminal' },
  disabled_buftypes = { 'prompt' },
  disabled_modes = { 't', 'nt' },
  relative_scrolloff = 0,
  enabled = true,
}

local function vim_resized_cb(ev)
  if is_disabled() then
    return
  end

  ---@type integer[]
  local win_ids = {}
  if ev ~= nil and ev.event == "WinResized" then
    win_ids = vim.v.event.windows or {}
  else
    table.insert(win_ids, vim.api.nvim_get_current_win())
  end

  for _, id in ipairs(win_ids) do
    local win_height = vim.fn.winheight(id)
    if relative_scrolloff > 1 then
      vim.wo[id].scrolloff = math.floor(win_height / relative_scrolloff)
      goto continue
    end

    local half_win_height = math.floor(win_height / 2)
    if vim.o.scrolloff < half_win_height then
      vim.wo[id].scrolloff = vim.o.scrolloff
      goto continue
    end

    vim.wo[id].scrolloff = (win_height % 2 == 0 and half_win_height > 0) and half_win_height - 1 or half_win_height
    ::continue::
  end
end

function M.setup(opts)
  -- Build a new table instead of modifying `opts` or `default_opts`, so that
  -- calling `setup()` again (e.g. when reloading the config) works.
  M.opts = vim.tbl_extend('force', {}, default_opts, opts or {})

  disabled.filetypes = to_set(M.opts.disabled_filetypes)
  disabled.buftypes = to_set(M.opts.disabled_buftypes)
  disabled.modes = to_set(M.opts.disabled_modes)

  local autocmds = { 'CursorMoved', 'WinScrolled', "WinNew", }
  if M.opts.insert_mode then
    table.insert(autocmds, 'CursorMovedI')
  end

  relative_scrolloff = M.opts.relative_scrolloff

  local scrollEOF_group = vim.api.nvim_create_augroup('ScrollEOF', { clear = true })

  vim.api.nvim_create_autocmd('ModeChanged', {
    group = scrollEOF_group,
    pattern = M.opts.pattern,
    callback = function()
      mode_disabled = disabled.modes[vim.api.nvim_get_mode().mode] == true
    end,
  })

  vim.api.nvim_create_autocmd({ 'WinResized', 'WinEnter' }, {
    group = scrollEOF_group,
    pattern = M.opts.pattern,
    callback = vim_resized_cb,
  })

  vim.api.nvim_create_autocmd(autocmds, {
    group = scrollEOF_group,
    pattern = M.opts.pattern,
    callback = check_eof_scrolloff,
  })

  vim_resized_cb()
  check_eof_scrolloff(nil)
  vim.schedule(function()
    vim_resized_cb()
    check_eof_scrolloff()
  end)
end

return M
