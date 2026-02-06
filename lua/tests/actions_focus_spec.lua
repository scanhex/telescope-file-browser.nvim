local Path = require "plenary.path"
local telescope = require "telescope"
local action_state = require "telescope.actions.state"
local fb_utils = require "telescope._extensions.file_browser.utils"

local function find_prompt_bufnr()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "TelescopePrompt" then
      return bufnr
    end
  end
end

describe("actions.create with vim.ui.input window", function()
  local old_input
  local tmp_dir
  local created_file

  before_each(function()
    old_input = vim.ui.input

    tmp_dir = Path:new(vim.fn.tempname())
    tmp_dir:mkdir { parents = true }
    created_file = Path:new { tmp_dir:absolute(), "actions_focus_spec.txt" }:absolute()

    telescope.setup {
      defaults = {
        path_display = { "truncate" },
      },
      extensions = {
        file_browser = {
          use_ui_input = true,
          quiet = true,
          grouped = false,
          hidden = true,
          initial_mode = "normal",
        },
      },
    }
    telescope.load_extension "file_browser"
  end)

  after_each(function()
    vim.ui.input = old_input

    local prompt_bufnr = find_prompt_bufnr()
    if prompt_bufnr then
      pcall(require("telescope.pickers").on_close_prompt, prompt_bufnr)
    end

    if tmp_dir and tmp_dir:exists() then
      tmp_dir:rm { recursive = true }
    end
  end)

  it("keeps telescope alive when input opens a focused floating window", function()
    vim.ui.input = function(_, cb)
      local bufnr = vim.api.nvim_create_buf(false, true)
      local winid = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        row = 1,
        col = 1,
        width = 24,
        height = 1,
        style = "minimal",
      })

      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_close(winid, true)
        end
        vim.defer_fn(function()
          cb(created_file)
        end, 5)
      end, 5)
    end

    telescope.extensions.file_browser.file_browser {
      path = tmp_dir:absolute(),
      cwd = tmp_dir:absolute(),
      layout_strategy = "horizontal",
      layout_config = { width = 100, height = 20 },
    }

    local prompt_bufnr
    local picker
    local ready = vim.wait(1000, function()
      prompt_bufnr = find_prompt_bufnr()
      if not prompt_bufnr then
        return false
      end
      picker = action_state.get_current_picker(prompt_bufnr)
      return picker ~= nil and vim.api.nvim_win_is_valid(picker.prompt_win)
    end, 20)

    assert.is_true(ready)
    local prompt_win = picker.prompt_win
    local fb_actions = require "telescope".extensions.file_browser.actions
    fb_actions.create(prompt_bufnr)

    local created = vim.wait(1500, function()
      return Path:new(created_file):exists()
    end, 20)
    assert.is_true(created)
    assert.is_true(vim.api.nvim_buf_is_valid(prompt_bufnr))
    assert.is_true(vim.api.nvim_win_is_valid(prompt_win))
    assert.are.same(prompt_win, vim.api.nvim_get_current_win())
  end)

  it("keeps telescope alive during confirmation prompts", function()
    local target = Path:new { tmp_dir:absolute(), "remove_me.txt" }
    target:touch()

    vim.ui.input = function(_, cb)
      local bufnr = vim.api.nvim_create_buf(false, true)
      local winid = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        row = 1,
        col = 1,
        width = 24,
        height = 1,
        style = "minimal",
      })

      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_close(winid, true)
        end
        vim.defer_fn(function()
          cb "y"
        end, 5)
      end, 5)
    end

    telescope.extensions.file_browser.file_browser {
      path = tmp_dir:absolute(),
      cwd = tmp_dir:absolute(),
      layout_strategy = "horizontal",
      layout_config = { width = 100, height = 20 },
    }

    local prompt_bufnr
    local picker
    local ready = vim.wait(1000, function()
      prompt_bufnr = find_prompt_bufnr()
      if not prompt_bufnr then
        return false
      end
      picker = action_state.get_current_picker(prompt_bufnr)
      return picker ~= nil and vim.api.nvim_win_is_valid(picker.prompt_win)
    end, 20)
    assert.is_true(ready)

    local prompt_win = picker.prompt_win
    local selection_index
    local selected = vim.wait(1000, function()
      local results = picker.finder and picker.finder.results
      if type(results) ~= "table" then
        return false
      end
      for i, entry in ipairs(results) do
        local path = type(entry) == "table" and entry.value or entry
        if type(path) == "string" and fb_utils.sanitize_path_str(path) == fb_utils.sanitize_path_str(target:absolute()) then
          selection_index = i
          return true
        end
      end
      return false
    end, 20)
    assert.is_true(selected)
    picker:set_selection(picker:get_row(selection_index))

    local fb_actions = require "telescope".extensions.file_browser.actions
    fb_actions.remove(prompt_bufnr)

    local removed = vim.wait(1500, function()
      return not target:exists()
    end, 20)
    assert.is_true(removed)
    assert.is_true(vim.api.nvim_buf_is_valid(prompt_bufnr))
    assert.is_true(vim.api.nvim_win_is_valid(prompt_win))
    assert.are.same(prompt_win, vim.api.nvim_get_current_win())
  end)
end)
