# Socrates

Socrates is a Neovim plugin that uses the OpenAI API to provide Socratic dialog and line-by-line commentary as you write Markdown documents. The plugin debounces requests to the API (so they only happen every couple of seconds), tracks changes in your buffer to only request commentary on newly updated lines, and attaches GPT’s comments as [Neovim diagnostics][nvim-diagnostic-docs].

> **DISCLAIMER**: This plugin interacts with a paid third-party service (OpenAI). Use responsibly.

---

## Features

- **Line-by-line Socratic comments** in the form of Neovim diagnostics.
- **Debouncing** to avoid spamming the API on every keystroke.
- **Diff-based** commentary: only changed lines get annotated.
- Works seamlessly with your existing `.md` files and note-taking workflow.

---

## Requirements

1. **Neovim** version 0.8+ (for Lua support and built-in diagnostics).
2. **[plenary.nvim][plenary.nvim]** for HTTP requests.
3. An **OpenAI API key** (e.g., `sk-...`). You can store this in an environment variable `OPENAI_API_KEY`, or pass it directly in your config.

---

## Installation

You can install Socrates using your favorite plugin manager. Two examples are [lazy.nvim][lazy.nvim] and [packer.nvim][packer.nvim].

### Using lazy.nvim

```lua
{
  "your-username/socrates",  -- Replace with your actual GitHub or repo
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("socrates").setup({
      -- Your custom config goes here
      -- openai_api_key = "sk-xxxxxx", -- or rely on OPENAI_API_KEY env var
      -- model = "gpt-3.5-turbo",
      -- events = { "TextChangedI", "TextChanged" },
      -- debounce_ms = 2000,
    })
  end
}
```

### Using packer.nvim

```lua
use({
  "your-username/socrates",  -- Replace with your actual GitHub or repo
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("socrates").setup({
      -- openai_api_key = "sk-xxxxxx",
      -- model = "gpt-3.5-turbo",
      -- events = { "TextChangedI", "TextChanged" },
      -- debounce_ms = 2000,
    })
  end,
})
```

> **Note**: If you prefer not to check your API key into a config file, be sure to set the environment variable `OPENAI_API_KEY` instead.

---

## Basic Configuration

Below are the main config options you can override:

| Field            | Type      | Default                             | Description                                                                                             |
| ---------------- | --------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `openai_api_key` | `string`  | `os.getenv("OPENAI_API_KEY")`       | Your OpenAI API key. If left blank, the plugin will look for the `OPENAI_API_KEY` environment variable. |
| `model`          | `string`  | `"gpt-3.5-turbo"`                   | Which OpenAI model to use for the chat completions.                                                     |
| `events`         | `table`   | `{ "TextChangedI", "TextChanged" }` | The auto commands that will trigger Socrates requests.                                                  |
| `debounce_ms`    | `integer` | `2000`                              | How many milliseconds to wait before sending a new request to GPT, to avoid spamming the API.           |

Example config:

```lua
require("socrates").setup({
  openai_api_key = "sk-your-api-key-here",
  model = "gpt-3.5-turbo",
  events = { "TextChangedI", "TextChanged" },
  debounce_ms = 2000,
})
```

---

## Usage

1. **Open a Markdown file** (`*.md`).
2. Start typing or editing. After you’ve paused for about 2 seconds (default debounce), Socrates will:
   - Collect your buffer text.
   - Compute the changed lines since the last request.
   - Ask GPT to provide Socratic commentary **only** for those changed lines.
   - Parse GPT’s JSON response and create a Neovim diagnostic for each line.
3. **View diagnostics** in one of the following ways:
   - Hover over the line (`:lua vim.diagnostic.open_float()` or set up an autocmd for `CursorHold`).
   - Use the built-in diagnostic commands like `:lua vim.diagnostic.goto_next()` or `:Telescope diagnostics`.
   - Or open the diagnostics panel (`:lua vim.diagnostic.setqflist()`).

---

## Tips and Notes

- **Large Documents**: If your `.md` files are extremely large, you might exceed token limits or face slow responses. Consider chunking or summarizing the text in a future enhancement.
- **Multiple Buffers**: This simple version tracks only a single `last_sent_text` global. If you switch between multiple `.md` buffers frequently, you can easily adapt the code to cache `last_sent_text` per buffer.
- **Fallback Handling**: Sometimes GPT might not strictly follow the JSON schema. Consider adding fallback logic or better error handling in production.
- **API Costs**: Remember that each request consumes tokens. Keep an eye on usage. Debouncing helps reduce unnecessary calls.

---

## Contributing

1. Fork the repository and create your feature branch (`git checkout -b feature/foo`).
2. Make changes and write tests.
3. Commit your changes (`git commit -am 'Add some feature'`).
4. Push to the branch (`git push origin feature/foo`).
5. Create a new Pull Request.

---

## License

This plugin is released under the [MIT License](LICENSE).

---

**Happy Socratic note-taking!**

[nvim-diagnostic-docs]: https://neovim.io/doc/user/lsp.html#diagnostics
[plenary.nvim]: https://github.com/nvim-lua/plenary.nvim
[lazy.nvim]: https://github.com/folke/lazy.nvim
[packer.nvim]: https://github.com/wbthomason/packer.nvim
