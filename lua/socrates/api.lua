-- Purpose: Send the user’s buffer text to OpenAI GPT-4 (or GPT-4o) completions API
-- and retrieve the generated content. We assume the response is in a format
-- that your plugin can parse (JSON array of feedback objects).

local M = {}

---Send a single user message to the OpenAI Chat Completions endpoint using GPT-4o.
---Use the user-provided config to set the API key, temperature, etc.
---
---@param text string The user’s Markdown text (the entire buffer).
---@param config table Plugin config containing openai_api_key, temperature, etc.
---@param callback function A callback with signature function(err, result).
---  `err` is nil on success, or a string describing the error.
---  `result` is the raw content from OpenAI (a string that presumably contains JSON).
function M.send_to_openai(text, config, callback)
  local url = "https://api.openai.com/v1/chat/completions"
  local api_key = config.openai_api_key or ""
  if api_key == "" then
    callback("No OpenAI API key set in plugin config.", nil)
    return
  end

  -- Build the JSON payload for the chat/completions endpoint
  local payload = {
    model = "gpt-4o-mini",
    messages = {
      {
        role = "system",
        content = [[
        You are a writing feedback assistant. 
        Given a Markdown text, you analyze it and respond ONLY with a JSON array of feedback objects in the format:
        [
          {
            "lineRange": [startLine, endLine],
            "title": "Short Title",
            "description": "Detailed Explanation"
          },
          ...
        ]
      ]]
      },
      {
        role = "user",
        content = text,  -- the user’s Markdown content
      }
    },
    temperature = config.temperature or 0.7,
  }
  local json_payload = vim.json.encode(payload)

  -- Prepare headers
  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. api_key,
  }

  -- Build the curl command
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

  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      local body = table.concat(data, "\n")
      if body and #body > 0 then
        -- OpenAI returns a JSON object with a top-level "choices" array
        -- We'll parse out choices[1].message.content
        local ok, decoded = pcall(vim.json.decode, body)
        if not ok or not decoded or not decoded.choices then
          callback("Invalid JSON from OpenAI", nil)
          return
        end
        local choice = decoded.choices[1]
        if not choice or not choice.message or not choice.message.content then
          callback("No content in OpenAI response", nil)
          return
        end
        callback(nil, choice.message.content)
      end
    end,
    on_stderr = function(_, data, _)
      -- Optionally handle stderr logs here
    end,
    on_exit = function(_, code, _)
      if code ~= 0 then
        callback("HTTP request failed with exit code " .. code, nil)
      end
    end,
  })

  if job_id <= 0 then
    callback("Failed to start job for OpenAI request.", nil)
  end
end

return M
