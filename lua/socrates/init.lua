local M = {}

local curl = require('plenary.curl')
local json = vim.json or require('dkjson')
math.randomseed(os.time()) -- Initialize random seed

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
  debounce_ms = 5000, -- 5 seconds by default
  response_threshold = 0.8 -- Higher threshold means fewer responses
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
---------------------------------------------------------------------------------
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
local function request_socratic_dialog_async(full_text_lines, changed_lines, config, done)
  -- Annotate lines so GPT knows how to reference them
  local annotated_text = annotate_lines(full_text_lines)
  local changed_lines_str = table.concat(changed_lines, ", ")
  
  vim.schedule(function()
    vim.notify(string.format(
      "Socrates: Building API request for changed lines: %s", 
      changed_lines_str
    ), vim.log.levels.INFO)
  end)

  local user_prompt = string.format([[
You are a Socratic teacher who is extremely selective about when to respond. 
Here is the entire text (line numbers in parentheses for your reference):

%s

Only lines %s were changed from the previous version. Your task is to steelman opposing arguments, but ONLY when the writer makes a point that has a genuinely strong counterargument.

CRITICAL INSTRUCTIONS:
1. Be EXTREMELY selective - remain silent most of the time (>80%% of updates should have no response)
2. Only respond when there is a truly compelling opposing viewpoint worth considering
3. Focus on steelmanning the strongest possible counterargument to the writer's position
4. Prioritize philosophical and logical counterpoints over factual corrections
5. Never respond to neutral statements, questions, or exploratory thinking
6. DEFAULT TO SILENCE unless the argument clearly warrants a strong counterpoint

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

  local request_body = json.encode({
    model = config.model,
    messages = {
      { role = "user", content = user_prompt }
    },
    max_tokens = 512,
    temperature = 1.0, -- Higher temperature increases randomness, making model more likely to remain silent
  })

  -- Make an *asynchronous* request with `callback`:
  curl.post("https://api.openai.com/v1/chat/completions", {
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. config.openai_api_key,
    },
    body = request_body,
    callback = function(response)  -- this runs *after* HTTP completes
      local comments = {}
      if response and response.status == 200 then
        local notify_status = function()
          vim.notify("Socrates: Received response with status 200", vim.log.levels.INFO)
        end
        vim.schedule(notify_status)
        
        local data = json.decode(response.body)
        if data and data.choices and data.choices[1] and data.choices[1].message then
          local raw_content = data.choices[1].message.content
          
          vim.schedule(function()
            vim.notify(string.format(
              "Socrates: Raw API response: %s", 
              string.sub(raw_content, 1, 100) .. (string.len(raw_content) > 100 and "..." or "")
            ), vim.log.levels.INFO)
          end)
          
          -- Attempt to parse GPT's JSON response
          local ok, comment_table = pcall(json.decode, raw_content)
          if ok and comment_table and comment_table.comments then
            comments = comment_table.comments
            vim.schedule(function()
              vim.notify(string.format(
                "Socrates: Successfully parsed %d comments from JSON response", 
                #comments
              ), vim.log.levels.INFO)
            end)
          else
            vim.schedule(function()
              vim.notify("Socrates: Failed to parse JSON response or no comments found", vim.log.levels.WARN)
            end)
          end
        else
          vim.schedule(function()
            vim.notify("Socrates: Unexpected API response format", vim.log.levels.WARN)
          end)
        end
      else
        vim.schedule(function()
          vim.notify(string.format(
            "Socrates: API request failed with status %s", 
            response and response.status or "unknown"
          ), vim.log.levels.ERROR)
        end)
      end

      -- Ensure any UI updates or diagnostics happen on the main thread:
      vim.schedule(function()
        done(comments)  
      end)
    end
  })
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
        local old_lines = {}
        if last_sent_text ~= nil then
          old_lines = vim.split(last_sent_text, "\n")
        end

        local changed_lines = find_changed_lines(old_lines, lines)
        if #changed_lines == 0 then
          return
        end

        -- For large changes, we're less likely to respond
        local change_ratio = math.min(1.0, #changed_lines / #lines)
        
        -- Log information for debugging
        vim.schedule(function()
          vim.notify(string.format(
            "Socrates: Changed lines: %d, Total lines: %d, Change ratio: %.2f, Threshold: %.2f", 
            #changed_lines, #lines, change_ratio, config.response_threshold + change_ratio
          ), vim.log.levels.INFO)
        end)
        
        -- Only proceed with the request if we pass a random threshold check
        -- This ensures we respond much less frequently
        local random_value = math.random()
        if random_value > (config.response_threshold + change_ratio) then
          -- Skip this update but still store the text
          vim.schedule(function()
            vim.notify(string.format(
              "Socrates: Skipping request (random value %.2f > threshold %.2f)", 
              random_value, config.response_threshold + change_ratio
            ), vim.log.levels.INFO)
          end)
          last_sent_text = text
          return
        end
        
        vim.schedule(function()
          vim.notify("Socrates: Sending request to OpenAI", vim.log.levels.INFO)
        end)
        
        request_socratic_dialog_async(lines, changed_lines, config, function(comments)
          if comments and #comments > 0 then
            vim.schedule(function()
              vim.notify(string.format(
                "Socrates: Received %d comments from OpenAI", 
                #comments
              ), vim.log.levels.INFO)
            end)
            set_socratic_diagnostics(bufnr, comments)
          else
            vim.schedule(function()
              vim.notify("Socrates: No comments received from OpenAI", vim.log.levels.INFO)
            end)
            vim.diagnostic.reset(socrates_ns, bufnr)
          end

          -- store the text in last_sent_text *after* we get the response
          last_sent_text = text
        end)
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

