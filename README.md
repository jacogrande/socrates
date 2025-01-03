# Socrates

A Neovim plugin that serves as a second-person “writing companion” for Markdown files. Socrates integrates with OpenAI’s GPT-4 (or GPT-4o) API to provide continuous feedback on your prose. As you type, Socrates sends your buffer content to OpenAI and inserts virtual text annotations (inline) about suggested improvements, warnings, or any other GPT-generated commentary.

> **Note**: This is a reference implementation. You’ll likely want to adapt it for your specific workflow (e.g., partial text updates, custom feedback formats, chunking for large docs, etc.).

---

## Features

1. **Real-time Feedback**  
   After a short debounce, your Markdown buffer is sent to GPT for feedback, which then appears inline.

2. **Inline Annotations**  
   Comments are displayed as virtual text on the affected lines.

3. **Automatic Removal of Stale Feedback**  
   If you change a line overlapping an existing comment’s range, that comment is removed.

4. **OpenAI Integration**  
   Uses the OpenAI Chat Completions endpoint (`https://api.openai.com/v1/chat/completions`). The user must supply an API key in their config.

5. **Optional Side Pane**  
   You can open a side pane (`:MarkdownFeedbackOpen`) for notes, logs, or expansions.

---

## Installation

Below is an example using [**lazy.nvim**](https://github.com/folke/lazy.nvim).

1. **Add the plugin to your Lazy config** (e.g., `~/.config/nvim/lua/plugins/socrates.lua`):

   ```lua
   return {
     {
       -- Replace with your own repo or local path
       "yourusername/socrates",
       ft = { "markdown" },
       config = function()
         require("socrates").setup({
           openai_api_key = "YOUR_OPENAI_API_KEY",
           temperature = 0.7,
           debounce_ms = 1500,
         })
       end,
     },
   }
   ```

2. **Install**: Run `:Lazy sync` and restart Neovim.

3. **Open a Markdown file** (`.md`). Once open, Socrates will attach automatically.

---

## Configuration

You can pass a configuration table to `setup()`. The defaults (with their typical usage) are:

```lua
require("socrates").setup({
  openai_api_key = "YOUR_OPENAI_API_KEY", -- Required
  temperature = 0.7,                      -- Customizable, affects GPT “creativity”
  debounce_ms = 1000,                     -- Delay between typed changes and GPT requests (in ms)
})
```

- **`openai_api_key`** (Required): Your OpenAI secret key (e.g., `sk-...`).
- **`temperature`**: GPT “creativity” level (0.0 = deterministic, 1.0 = more creative).
- **`debounce_ms`**: Wait time in milliseconds after you stop typing before sending the buffer content to GPT.

> **Security Note**: Keep your API key safe. Don’t commit it to a public repo.

---

## Usage

1. **Open a Markdown file**: Socrates automatically attaches and watches for changes.
2. **Type**: After you pause for `debounce_ms`, Socrates sends your entire buffer to the OpenAI endpoint.
3. **Observe**: The plugin inserts GPT’s suggestions or warnings as inline annotations on relevant lines.
4. **Editing**: If you modify lines that overlap an existing comment, that comment is removed (to prevent stale feedback).
5. **Side Pane**: Optionally open a side pane with `:MarkdownFeedbackOpen`. The inline feedback still appears in the main buffer.

---

## The Three Lua Files

This plugin is split into three main files inside the `lua/socrates/` directory:

1. **`api.lua`**

   - Handles sending data to the OpenAI API via `curl` (`jobstart`).
   - Expects a JSON response containing a `choices` array; we extract `choices[1].message.content`.
   - Passes the raw GPT content back to the plugin for parsing.

2. **`feedback.lua`**

   - Renders GPT feedback inline using Neovim `extmarks`.
   - Removes stale feedback when lines overlap changes.

3. **`init.lua`**
   - The plugin’s “entry point.”
   - Exposes `setup()` for config, sets up autocmds for `FileType markdown`, debounces LLM requests, and calls `feedback` methods.

---

## Common Pitfalls & Fixes

### 1. `E5560: nvim_buf_get_lines must not be called in a lua loop callback`

Neovim disallows certain buffer API calls (like `nvim_buf_get_lines`) from _within_ the `on_lines` event. **Fix** this by wrapping the call in `vim.schedule()`, so the function runs _after_ the current event:

```lua
-- WRONG:
-- local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)  -- inside on_lines callback

-- CORRECT:
vim.schedule(function()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- ...
end)
```

### 2. Large Document Issues

OpenAI has token limits; if your file is large, you may exceed them. Strategies include:

- Only sending changed lines + surrounding context.
- Summarizing prior content.

### 3. API Costs & Rate Limits

Calls to GPT can be expensive if you type quickly. Adjust `debounce_ms` or implement chunk-based strategies to reduce usage.

---

## Feedback Format

We assume GPT’s output is a **JSON array** of objects:

```json
[
  {
    "lineRange": [20, 24],
    "title": "Potential fallacy",
    "description": "You rely on an unsubstantiated claim here..."
  },
  ...
]
```

- **`lineRange`**: `[startLine, endLine]`, 0- or 1-based depending on your prompt/instructions.
- **`title`**: Short message, displayed inline.
- **`description`**: Longer explanation.

Socrates uses this data to place inline warnings on your buffer. If the lines are 1-based in GPT’s output, you may need to subtract 1 before calling `vim.api.nvim_buf_set_extmark`.

---

## Commands

- `:MarkdownFeedbackOpen`  
  Opens a vertical split “GPT_Feedback” buffer. Useful for notes or plugin logs.

---

## License & Contributing

- **License**: MIT.
- **Contributions**: PRs, issues, and suggestions welcome.

**Happy Writing!**
