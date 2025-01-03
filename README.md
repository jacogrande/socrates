# Socrates

A Neovim plugin that provides feedback on your Markdown writing in real time—like having another person reviewing your text as you type. The plugin continuously sends your buffer content to a Large Language Model (LLM) API, receives feedback in JSON format, and displays comments inline via virtual text. You can optionally open a side pane for note-taking or reviewing logs.

> **Note:** This is a reference implementation or scaffold. You’ll likely want to adapt it to your own needs (e.g., use a robust HTTP library, handle large documents, or integrate with specific LLM endpoints).

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
  - [Using lazy.nvim](#using-lazynvim)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Commands](#commands)
- [Feedback JSON Format](#feedback-json-format)
- [Implementation Details](#implementation-details)
- [Roadmap / Ideas](#roadmap--ideas)

---

## Features

1. **Automatic Markdown Buffer Detection**  
   The plugin attaches itself to Markdown files, so it only runs when you open a `.md` file.

2. **LLM Integration**  
   Continuously sends your current buffer to a configured LLM endpoint (e.g., GPT-like models) after a short debounce.

3. **Inline Comments**  
   Feedback is displayed inline as virtual text (via Neovim `extmarks`), making suggestions visible in context.

4. **Automatic Removal of Stale Feedback**  
   If the user edits lines that overlap with existing feedback, that feedback is removed to avoid confusion.

5. **Side Pane**  
   An optional side pane can be opened with a command. Use it for logging, note-taking, or potential expansions (like a conversation window).

---

## Installation

You can install **socrates** using any Neovim plugin manager. Below is an example with [lazy.nvim](https://github.com/folke/lazy.nvim).

### Using lazy.nvim

1. Add this plugin to your plugin specs. For instance, create or edit `~/.config/nvim/lua/plugins/socrates.lua`:

   ```lua
   return {
     {
       -- Replace with your own repo or local path
       "jacogrande/socrates",
       ft = { "markdown" },
       config = function()
         require("socrates").setup({
           llm_api_url = "https://your-llm-api.example.com",
           api_headers = {
             ["Content-Type"] = "application/json",
             -- ["Authorization"] = "Bearer YOUR_API_KEY",
           },
           debounce_ms = 1500,
         })
       end,
     },
   }
   ```

2. Run `:Lazy sync` to install.

3. Open a Markdown file (`.md`)—the plugin will attach and start watching your buffer.

---

## Configuration

Use the plugin’s `setup` function to configure behavior:

```lua
require("socrates").setup({
  llm_api_url = "https://your-llm-api.example.com",
  api_headers = {
    ["Content-Type"] = "application/json",
    -- ["Authorization"] = "Bearer YOUR_API_KEY",
  },
  debounce_ms = 1500,
})
```

- **`llm_api_url`**: The URL of your LLM API endpoint.
- **`api_headers`**: Table of additional request headers (for tokens, content type, etc.).
- **`debounce_ms`**: Milliseconds to wait after user stops typing before sending a request (helps prevent API spam).

---

## Usage

1. **Open a Markdown file**.  
   Once open, the plugin automatically attaches, tracks your edits, and sends your text to the configured LLM endpoint.

2. **See inline feedback**.  
   Feedback from the LLM is displayed inline as virtual text on the indicated lines.

3. **Remove or update**.  
   If you edit lines overlapping feedback, that feedback is automatically removed. If you type more, new feedback will be fetched on the next debounce.

4. **Open side pane**.  
   You can open an additional vertical pane for logs or notes with:
   ```vim
   :MarkdownFeedbackOpen
   ```
   By default, it just shows a placeholder. You could customize to display more info or even a conversation log.

### Commands

- **`:MarkdownFeedbackOpen`**  
  Opens a vertical split with a scratch buffer titled “GPT_Feedback.” Use it for your notes, plugin logs, or expansions.

---

## Feedback JSON Format

The LLM is expected to respond with a JSON array, where each element looks like:

```json
{
  "lineRange": [20, 24],
  "title": "This is a bad predicate",
  "description": "You're trying to use this argument to support your thesis, but it's a bad argument..."
}
```

- **`lineRange`**: A two-element list `[startLine, endLine]` specifying which lines the feedback applies to.
  - **Important**: In the plugin example, lines are used zero-based internally. You may need to adjust by -1 if your API returns 1-based indices.
- **`title`**: A short summary or heading for the issue/suggestion.
- **`description`**: A more in-depth explanation of the feedback.

---

## Implementation Details

**Core Files**

- **`lua/socrates/init.lua`**: Main plugin logic.
  - **`setup()`**: Configures and sets up autocmds for Markdown detection.
  - **Autocommands**: Trigger attachment to `.md` buffers, hooking into `nvim_buf_attach` to watch text changes.
  - **HTTP Requests**: Uses a simple `curl` command via `vim.fn.jobstart` for demonstration. In a real deployment, consider [plenary.curl](https://github.com/nvim-lua/plenary.nvim) or a dedicated HTTP client.
  - **Rendering Feedback**: Creates virtual text for each feedback item and stores them in a state table.
- **`plugin/socrates.vim`**: Calls the `setup()` function on Neovim startup (or when the plugin is loaded).

**How it Works**

1. The plugin attaches to any buffer with filetype `markdown`.
2. Every time you type, the plugin debounces for a set number of milliseconds. Once the timer elapses, it gathers the entire buffer content and sends it to your configured LLM endpoint.
3. When the LLM responds with feedback objects, the plugin renders them in the buffer using virtual text.
4. If you change lines that overlap existing feedback, that feedback is removed automatically to avoid stale messages.

---

## Roadmap / Ideas

- **Selective feedback**: Instead of sending the entire buffer, only send changed lines or a context around them (reduce API usage).
- **Floating Windows**: Expand feedback in a popup on hover or keystroke, rather than purely inline text.
- **Conversations**: Retain conversation context in a hidden buffer or side pane for Q&A with the LLM.
- **Sign Icons**: Place icons in the sign column or gutter (like diagnostics).
- **Customization**: Let users configure color highlights, formatting of feedback, or map custom commands for toggling suggestions.

---

**Enjoy your socratic writing assistant!** If you run into issues or want to propose improvements, feel free to open an issue or a pull request on this repository. Happy writing!
