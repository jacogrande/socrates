local M = {}

local curl = require('plenary.curl')
local json = vim.json or require('dkjson')

local socrates_ns = vim.api.nvim_create_namespace("Socrates")

-- Store the last buffer text so we can diff
local last_sent_text = nil

-- For debouncing
local debounce_timer = nil

-- Default config
local default_config = {
  openai_api_key = os.getenv("OPENAI_API_KEY"),
  model = "gpt-4o-mini",
  events = { "TextChangedI", "TextChanged" },
  debounce_ms = 2000, -- 2 seconds by default
}

--------------------------------------------------------------------------------
-- Utility: find which lines changed between old_lines and new_lines
--------------------------------------------------------------------------------
local function find_changed_lines(old_lines, new_lines)
  local changed = {}
  local max_len = math.max(#old_lines, #new_lines)

  for i = 1, max_len do
    local old_line = old_lines[i] or ""
    local new_line = new_lines[i] or ""
    if old_line ~= new_line then
      table.insert(changed, i)
    end
  end

  return changed
end

--------------------------------------------------------------------------------
-- Utility: create a line-number annotated string
-- e.g., (1) First line\n(2) Second line\n...
--------------------------------------------------------------------------------
local function annotate_lines(lines)
  local annotated = {}
  for i, line in ipairs(lines) do
    table.insert(annotated, string.format("(%d) %s", i, line))
  end
  return table.concat(annotated, "\n")
end

--------------------------------------------------------------------------------
-- 1) Helper to request Socratic dialog from OpenAI
--    We return a table of { line_number = ..., comment = ... }
--------------------------------------------------------------------------------
local function request_socratic_dialog(full_text_lines, changed_lines, config)
  -- Annotate lines so GPT knows how to reference them
  local annotated_text = annotate_lines(full_text_lines)
  local changed_lines_str = table.concat(changed_lines, ", ")

  -- The user message
  local user_prompt = string.format([[
You are a Socratic teacher. 
Here is the entire text (line numbers in parentheses for your reference):

%s

Only lines %s were changed from the previous version. Carefully read through the changed text, and ponder any serious criticisms, counterpoints, or questions. Act as if you're listening to an argument, so you should only interject when something sticks out as a bad argument or premise. It's okay if you have nothing to point out. Air on the side of staying quiet.

Return your response in JSON matching this schema (no extra keys, no additional commentary outside JSON):
{
  "comments": [
    {
      "line_number": number,
      "comment": string
    }
  ]
}
  ]],
    annotated_text,
    changed_lines_str
  )

  -- Perform the HTTP request
  local response = curl.post("https://api.openai.com/v1/chat/completions", {
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. config.openai_api_key,
    },
    body = json.encode({
      model = config.model,
      messages = {
        { role = "user", content = user_prompt }
      },
      max_tokens = 512,
      temperature = 0.7,
    }),
  })
  if response and response.status == 200 then
    local data = json.decode(response.body)
    if data and data.choices and data.choices[1] and data.choices[1].message then
      local raw_content = data.choices[1].message.content

      -- Attempt to parse GPT's JSON response
      local ok, comment_table = pcall(json.decode, raw_content)
      if ok and comment_table and comment_table.comments then
        return comment_table.comments
      else
        -- GPT might not always comply with the strict JSON format,
        -- so handle fallback or error as you see fit
        return {}
      end
    end
  end

  return {}
end

--------------------------------------------------------------------------------
-- 2) Set diagnostics for each comment object { line_number, comment }
--------------------------------------------------------------------------------
local function set_socratic_diagnostics(bufnr, comments)
  -- Clear existing "Socrates" diagnostics
  vim.diagnostic.reset(socrates_ns, bufnr)

  local diagnostics = {}

  for _, c in ipairs(comments) do
    local lnum = math.max(0, c.line_number - 1) -- 0-based
    table.insert(diagnostics, {
      lnum = lnum,
      col = 0,
      end_lnum = lnum,
      end_col = 0,
      severity = vim.diagnostic.severity.INFO,
      message = c.comment,
      source = "Socrates",
    })
  end

  vim.diagnostic.set(socrates_ns, bufnr, diagnostics)
end

--------------------------------------------------------------------------------
-- 3) Debounce helper
--------------------------------------------------------------------------------
local function schedule_socratic_request(callback, delay)
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
    debounce_timer = nil
  end

  debounce_timer = vim.loop.new_timer()
  debounce_timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      if debounce_timer then
        debounce_timer:stop()
        debounce_timer:close()
        debounce_timer = nil
      end

      callback()
    end)
  )
end

--------------------------------------------------------------------------------
-- 4) Autocommands to trigger the request
--------------------------------------------------------------------------------
local function setup_autocmds(config)
  vim.api.nvim_create_autocmd(config.events, {
    pattern = "*.md",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local text = table.concat(lines, "\n")

      -- If there's hardly any text, skip
      if #text < 10 then
        vim.diagnostic.reset(socrates_ns, bufnr)
        return
      end

      -- Debounced callback
      schedule_socratic_request(function()
        -- Determine changed lines vs. last_sent_text
        local old_lines = {}
        if last_sent_text ~= nil then
          old_lines = vim.split(last_sent_text, "\n")
        end

        local changed_lines = find_changed_lines(old_lines, lines)
        if #changed_lines == 0 then
          -- no changes, no need to request
          return
        end

        -- Call GPT
        local comments = request_socratic_dialog(lines, changed_lines, config)
        vim.schedule(function()
          if comments and #comments > 0 then
            set_socratic_diagnostics(bufnr, comments)
          else
            -- If GPT returned nothing or an error, clear or handle differently
            vim.diagnostic.reset(socrates_ns, bufnr)
          end
        end)

        -- Update last_sent_text
        last_sent_text = text
      end, config.debounce_ms)
    end,
  })
end

--------------------------------------------------------------------------------
-- 5) Setup function for the plugin
--------------------------------------------------------------------------------
function M.setup(user_config)
  local config = vim.tbl_deep_extend("force", default_config, user_config or {})

  if not config.openai_api_key or config.openai_api_key == "" then
    return
  end

  setup_autocmds(config)
end

return M

