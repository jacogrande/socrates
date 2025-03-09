# SOCRATES DEVELOPMENT GUIDE

## Project Overview
Socrates is a Neovim plugin providing Socratic dialog/commentary on Markdown documents using OpenAI's API.

## Commands
- Install dependencies: `git clone https://github.com/nvim-lua/plenary.nvim ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim`
- Manual testing: Open a markdown file and start typing to see Socratic diagnostics after the debounce period

## Code Style Guidelines
- **Language**: Lua for implementation, minimal VimScript for plugin loading
- **Formatting**: 
  - 2-space indentation
  - Function names: `snake_case`
  - Variables: `snake_case`
  - Clear section headers with dashed separator comments
- **Patterns**:
  - Use `vim.tbl_deep_extend` for config merging
  - Use `pcall` for error handling around JSON parsing
  - Prefer async requests with callbacks over blocking calls
  - Handle nil values in nested API responses
  - Use vim.schedule for UI updates from async callbacks
- **Documentation**: 
  - Add comments explaining complex logic
  - Document parameters in comments when appropriate

## Architecture
- Core functionality in `lua/socrates/init.lua`
- Plugin loading in `plugin/socrates.vim`
- Debounced API calls to avoid spamming OpenAI
- Diff-based processing to only comment on changed lines