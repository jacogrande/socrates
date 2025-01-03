local M = {}

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

-- Feel free to store your custom config here, or pass it in M.setup() as a parameter
M.config = {
  -- For demonstration, we use a placeholder URL. Replace with your actual LLM endpoint.
  llm_api_url = "http://localhost:3000/llm-feedback",

  -- If you need an API key or other headers, set them here:
  api_headers = {
    ["Content-Type"] = "application/json",
    -- ["Authorization"] = "Bearer <YOUR_API_KEY>",
  },

  -- How often (in ms) to debounce requests. When user types, we wait for a short
  -- interval before sending an update to avoid spam. Tweak as desired.
  debounce_ms = 1000,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

-- We'll maintain a table of buffer -> feedback comments, so we know which extmarks
-- or signs to remove or update if the lines shift.
-- Example structure: feedback_state[bufnr] = { [commentId] = { lineRange, extmarkId, etc. }, ... }
local feedback_state = {}

-- We also track any pending timers for debouncing requests:
local debounce_timers = {}

--------------------------------------------------------------------------------
-- UTIL FUNCTIONS
--------------------------------------------------------------------------------

---Send an HTTP POST request with a Lua job. Real life usage might rely on:
---  - plenary.curl
---  - uv.http
---  - or a plugin like rest.nvim
---
---@param url string
---@param payload table
---@param headers table
---@param callback function(err, response)
local function send_request(url, payload, headers, callback)
  -- Convert payload table to JSON
  local json_payload = vim.json.encode(payload)

  -- Build command using curl. For production, you'd use a proper HTTP library.
  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    url,
  }
  for k, v in pairs(headers) do
    table.insert(cmd, "-H")
    table.insert(cmd, k .. ": " .. v)
  end
  table.insert(cmd, "-d")
  table.insert(cmd, json_payload)

  -- Jobstart to run the command asynchronously
  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      local body = table.concat(data, "\n")
      if body and #body > 0 then
        callback(nil, body)
      end
    end,
    on_stderr = function(_, data, _)
      -- you could log errors here
    end,
    on_exit = function(_, code, _)
      if code ~= 0 then
        callback("HTTP request failed with exit code " .. code, nil)
      end
    end,
  })

  if job_id <= 0 then
    callback("Failed to start job", nil)
  end
end

--------------------------------------------------------------------------------
-- FEEDBACK HANDLING
--------------------------------------------------------------------------------

---Render feedback in the current buffer:
--- - We create an extmark for each feedback object
--- - We store them so we can remove or update if lines shift
---@param bufnr number
---@param feedback_list table list of feedback JSON objects
local function render_feedback(bufnr, feedback_list)
  local ns = vim.api.nvim_create_namespace("my_second_person_ns")

  -- Clear existing marks for this buffer
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  feedback_state[bufnr] = {}

  for idx, feedback in ipairs(feedback_list) do
    local startLine = feedback.lineRange[1] or 0
    local endLine   = feedback.lineRange[2] or 0
    local title     = feedback.title or "No Title"
    local desc      = feedback.description or ""

    -- We create an extmark near the start line (Neovim lines are 0-based)
    -- so subtract 1 if your `feedback.lineRange` is 1-based.
    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, startLine, 0, {
      virt_text = { 
        { "⚠ " .. title, "ErrorMsg" },
      },
      virt_text_pos = "eol",
      -- You can store extra data so we can expand on demand, etc.
      user_data = {
        description = desc,
        lineRange   = {startLine, endLine},
      },
    })

    -- Track it in our feedback_state
    feedback_state[bufnr][idx] = {
      lineRange = {startLine, endLine},
      extmark_id = extmark_id,
      title = title,
      description = desc,
    }
  end
end

---Remove or update feedback if lines have changed.
---You could do something more sophisticated, but for simplicity:
--- - If the user modifies lines that overlap with a feedback’s lineRange,
---   remove that feedback altogether.
local function handle_lines_changed(bufnr, changed_tick, start_line, old_lines_count, new_lines_count)
  local state = feedback_state[bufnr]
  if not state then return end

  local ns = vim.api.nvim_create_namespace("my_second_person_ns")

  for comment_id, fb in pairs(state) do
    local fb_start = fb.lineRange[1]
    local fb_end   = fb.lineRange[2]

    -- If the changed lines overlap with feedback range, remove
    local changed_range_end = start_line + old_lines_count
    if not (changed_range_end < fb_start or start_line > fb_end) then
      -- Overlap => remove
      vim.api.nvim_buf_del_extmark(bufnr, ns, fb.extmark_id)
      state[comment_id] = nil
    end
  end
end

--------------------------------------------------------------------------------
-- CORE: SENDING BUFFER TO LLM
--------------------------------------------------------------------------------

---Send the entire buffer content to the LLM and await feedback.
---@param bufnr number
local function send_buffer_to_llm(bufnr)
  -- For demonstration, just gather full buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text  = table.concat(lines, "\n")

  local payload = {
    text = text,
    language = "markdown",
    -- Possibly additional context or user parameters
  }

  send_request(M.config.llm_api_url, payload, M.config.api_headers, function(err, res)
    if err then
      vim.schedule(function()
        vim.notify("[my-second-person] LLM request error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    -- We expect JSON feedback in the format you described
    local decoded = nil
    pcall(function()
      decoded = vim.json.decode(res)
    end)
    if type(decoded) == "table" then
      vim.schedule(function()
        render_feedback(bufnr, decoded)
      end)
    else
      vim.schedule(function()
        vim.notify("[my-second-person] Failed to parse LLM response as JSON.", vim.log.levels.WARN)
      end)
    end
  end)
end

--------------------------------------------------------------------------------
-- DEBOUNCING MECHANISM
--------------------------------------------------------------------------------

local function schedule_llm_request(bufnr)
  -- If there's a pending timer for this buffer, clear it
  if debounce_timers[bufnr] then
    debounce_timers[bufnr]:stop()
    debounce_timers[bufnr] = nil
  end

  -- Create a new timer
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
-- SETUP AUTOCMDS AND BUFFER ATTACH
--------------------------------------------------------------------------------

---Attach to the buffer to watch changes. This is only invoked for markdown files.
---@param bufnr number
local function attach_to_markdown_buffer(bufnr)
  -- We’ll watch text changes using nvim_buf_attach
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, _bufnr, changedtick, start_line, old_lines_count, new_lines_count, byte_count)
      -- If lines change in a region that overlaps feedback, remove that feedback
      handle_lines_changed(_bufnr, changedtick, start_line, old_lines_count, new_lines_count)
      -- Then schedule an LLM request (debounce)
      schedule_llm_request(_bufnr)
      return false
    end,
    on_detach = function()
      -- Clean up if needed
      feedback_state[bufnr] = nil
      if debounce_timers[bufnr] then
        debounce_timers[bufnr]:stop()
        debounce_timers[bufnr] = nil
      end
    end,
  })
end

---Open a side pane for GPT feedback.  
---For simplicity, this just opens a vertical split.  
---You can customize (e.g. use a floating window, scratch buffer, etc.)
function M.open_side_pane()
  -- Check if we already have a window open for feedback; if not, create one
  vim.cmd("vsplit | enew")
  vim.cmd("setlocal buftype=nofile bufhidden=wipe nobuflisted")
  vim.cmd("file GPT_Feedback")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Feedback will appear inline as virtual text in the main buffer.", "Use this pane for your notes or to see plugin logs." })
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end

  -- Create user command to open the side pane
  vim.api.nvim_create_user_command("MarkdownFeedbackOpen", function()
    M.open_side_pane()
  end, {})

  -- Autocmd: attach to markdown files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown" },
    callback = function(args)
      local bufnr = args.buf
      attach_to_markdown_buffer(bufnr)
    end,
  })
end

return M
