# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-legion is a Neovim plugin (pure Lua, no build step) that manages multiple Claude Code terminal instances within tmux popup windows. It supports persistent instances, git worktree management, and project-scoped sessions.

## Development

No build, test, or lint commands exist. The plugin is loaded directly by Neovim's plugin system. To test changes, reload Neovim or use the auto-reload mechanism (file changes trigger `luafile` via autocommands in `init.lua`).

**Dependencies:** Neovim, tmux, git, `claude` CLI. Optional: telescope.nvim.

## Architecture

All source is under `lua/`. The plugin has two module trees:

- **`lua/claude-legion/`** — Core plugin modules:
  - `init.lua` — Entry point. Registers 8 user commands (`ClaudeCode`, `ClaudeCodeNew`, `ClaudeCodeSelect`, `ClaudeCodeSend`, `ClaudeCodeKill`, `ClaudeCodePersist`, `ClaudeWorktreeCreate`, `ClaudeWorktreeList`), sets up keymaps, and wires autocommands.
  - `config.lua` — Default configuration and `setup()` merge logic. Sessions are scoped per project via directory path hashing.
  - `terminal.lua` — Instance lifecycle (create/toggle/kill/send). Manages state table of Claude Code instances. Handles auto-reconnect to orphaned tmux sessions.
  - `status.lua` — Status detection for Claude Code and shell instances. Parses pane titles, detects input prompts via content matching, and provides `build_instance_list()` for batched status resolution.
  - `tmux.lua` — All tmux interaction via `vim.fn.system()`. Uses a dedicated socket (`-L claude-legion`). Manages popup display, window CRUD, and persistent markers via tmux window options (`@claude_persistent`, `@claude_name`).
  - `worktree.lua` — Git worktree creation/deletion/listing with tmux window integration.
  - `picker.lua` — Fallback instance picker using `vim.ui.select` when Telescope is unavailable.

- **`lua/telescope/_extensions/claude_code.lua`** — Telescope extension with two pickers (instances, worktrees). Provides keyboard-driven actions (create, kill, pin, rename, reorder) and refreshes results in-place.

### Key Design Patterns

- **Tmux as the runtime**: All Claude Code processes live in tmux windows under a dedicated session, not Neovim terminals. The plugin shells out to `tmux` for all process management.
- **Project isolation**: Session names include an MD5 hash of the project path, so multiple projects can run simultaneously without collision.
- **Persistent vs ephemeral**: Instances can be "pinned" (persistent), surviving Neovim exit. On next startup, the plugin reconnects to orphaned persistent windows.
- **Popup-based UI**: Claude Code is displayed via `tmux display-popup` attached to the current terminal, with configurable width/height (default 90%).
