-- Purpose: Manage rendering feedback as extmarks in the buffer, and remove
-- stale feedback when lines are edited.

local M = {}

-- A table that tracks all feedback for each buffer:
-- feedback_state[bufnr] = { [commentId] = { lineRange, extmark_id, etc. }, ... }
local feedback_state = {}

-- The namespace used for these virtual text extmarks
local NS = vim.api.nvim_create_namespace("my_second_person_ns")

---Render feedback from the LLM in the current buffer. Clears old feedback
---and creates new extmarks for each feedback entry.
---
---@param bufnr number
---@param feedback_list table List of JSON objects describing the feedback
---  Example item:
---  {
---    "lineRange": [20,24],
---    "title": "This is a bad predicate",
---    "description": "You’re trying to use this argument to support..."
---  }
function M.render_feedback(bufnr, feedback_list)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  feedback_state[bufnr] = {}

  for idx, feedback in ipairs(feedback_list) do
    local startLine = feedback.lineRange and feedback.lineRange[1] or 0
    local endLine   = feedback.lineRange and feedback.lineRange[2] or 0
    local title     = feedback.title or "No Title"
    local desc      = feedback.description or ""

    -- If your LLM returns 1-based line numbers, you may want: startLine = startLine - 1
    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, NS, startLine, 0, {
      virt_text = { { "⚠ " .. title, "ErrorMsg" } },
      virt_text_pos = "eol",
      user_data = {
        description = desc,
        lineRange = { startLine, endLine },
      },
    })

    feedback_state[bufnr][idx] = {
      lineRange = { startLine, endLine },
      extmark_id = extmark_id,
      title = title,
      description = desc,
    }
  end
end

---Remove or update feedback if lines have changed in a region that overlaps
---an existing feedback item. In this simple approach, we remove the feedback
---entirely if it intersects the changed lines.
---
---@param bufnr number
---@param changed_tick number
---@param start_line number
---@param old_lines_count number
---@param new_lines_count number
function M.handle_lines_changed(bufnr, changed_tick, start_line, old_lines_count, new_lines_count)
  local state = feedback_state[bufnr]
  if not state then return end

  local changed_range_end = start_line + old_lines_count - 1

  for comment_id, fb in pairs(state) do
    local fb_start = fb.lineRange[1]
    local fb_end   = fb.lineRange[2]

    -- Check overlap
    if not (changed_range_end < fb_start or start_line > fb_end) then
      -- We have overlap => remove that feedback
      vim.api.nvim_buf_del_extmark(bufnr, NS, fb.extmark_id)
      state[comment_id] = nil
    end
  end
end

-- Optional: clear feedback if buffer detaches or other housekeeping
function M.clear_feedback(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  feedback_state[bufnr] = nil
end

return M
