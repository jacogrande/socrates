-- Purpose: The main plugin file that:
--  1. Exposes the public setup() function for plugin configuration
--  2. Sets up autocmds for markdown, attaches watchers, debounces LLM calls
--  3. Calls out to 'api.lua' to get LLM feedback, and 'feedback.lua' to render it.

local M = {}

local api = require("socrates.api")
local feedback = require("socrates.feedback")

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

M.config = {
  -- The user must provide an OpenAI API key via plugin setup in lazy or their config:
  openai_api_key = "",
  temperature = 0.7,  -- used when calling GPT

  -- How often (in ms) to debounce requests. When user types, we wait a bit before
  -- sending an update to avoid spamming the API. Tweak as desired.
  debounce_ms = 1000,
}

--------------------------------------------------------------------------------
-- DEBOUNCING + STATE
--------------------------------------------------------------------------------

-- Track pending timers to avoid repeated calls
local debounce_timers = {}

---Send the entire buffer to OpenAI, parse JSON feedback, and render in the buffer.
---@param bufnr number
local function send_buffer_to_llm(bufnr)
  -- Defer reading the buffer lines until we're in a safe context.
  vim.schedule(function()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local text = table.concat(lines, "\n")

    -- Use the API to send the text
    api.send_to_openai(text, M.config, function(err, raw_content)
      if err then
        vim.schedule(function()
          vim.notify("[socrates] LLM request error: " .. err, vim.log.levels.ERROR)
        end)
        return
      end

      -- Our plugin expects the content to be valid JSON array of feedback objects
      local ok, decoded = pcall(vim.json.decode, raw_content)
      if not ok or type(decoded) ~= "table" then
        vim.schedule(function()
          vim.notify("[socrates] Failed to parse LLM response as JSON array.", vim.log.levels.WARN)
        end)
        return
      end

      -- If decoding was successful, pass feedback to feedback.render_feedback
      vim.schedule(function()
        feedback.render_feedback(bufnr, decoded)
      end)
    end)
  end)
end

---Debounce requests so we don’t spam the LLM each time the user types.
---@param bufnr number
local function schedule_llm_request(bufnr)
  if debounce_timers[bufnr] then
    debounce_timers[bufnr]:stop()
    debounce_timers[bufnr] = nil
  end

  local timer = vim.loop.new_timer()
  timer:start(M.config.debounce_ms, 0, function()
    timer:stop()
    timer:close()
    debounce_timers[bufnr] = nil
    send_buffer_to_llm(bufnr)
  end)
  debounce_timers[bufnr] = timer
end

--------------------------------------------------------------------------------
-- BUFFER ATTACH
--------------------------------------------------------------------------------

---Attach to a buffer for markdown
---@param bufnr number
local function attach_to_markdown_buffer(bufnr)
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, _bufnr, changed_tick, start_line, old_lines_count, new_lines_count, byte_count)
      -- Remove overlapping feedback
      feedback.handle_lines_changed(_bufnr, changed_tick, start_line, old_lines_count, new_lines_count)
      -- Schedule a new LLM request
      schedule_llm_request(_bufnr)
      return false
    end,
    on_detach = function()
      -- Cleanup
      feedback.clear_feedback(bufnr)
      if debounce_timers[bufnr] then
        debounce_timers[bufnr]:stop()
        debounce_timers[bufnr] = nil
      end
    end,
  })
end

--------------------------------------------------------------------------------
-- SIDE PANE
--------------------------------------------------------------------------------

---Optional side pane for logs or additional info.
function M.open_side_pane()
  vim.cmd("vsplit | enew")
  vim.cmd("setlocal buftype=nofile bufhidden=wipe nobuflisted")
  vim.cmd("file GPT_Feedback")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "Feedback appears inline (virtual text) in the main buffer.",
    "This pane can be used for additional logs or notes.",
  })
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

---Plugin setup. Users can configure it in their lazy.nvim config, e.g.:
---  require("socrates").setup({
---    openai_api_key = "...",
---    debounce_ms = 1500,
---    temperature = 0.7,
---  })
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end

  -- Create a user command to open side pane
  vim.api.nvim_create_user_command("MarkdownFeedbackOpen", function()
    M.open_side_pane()
  end, {})

  -- Autocmd: attach only for markdown files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown" },
    callback = function(args)
      attach_to_markdown_buffer(args.buf)
    end,
  })
end

return M
