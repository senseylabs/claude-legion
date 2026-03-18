# Current Plugin Workflow

Snapshot of how claude-legion works as of March 2026, documented before redesigning it.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Outer tmux session (user's terminal)                   │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Neovim                                           │  │
│  │  (claude-legion plugin loaded)                    │  │
│  │                                                   │  │
│  │  Manages instances via vim.fn.system("tmux ...")   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌ tmux display-popup ─────────────────────────────┐    │
│  │                                                  │    │
│  │  Inner tmux (socket: claude-legion)              │    │
│  │  Session: claude-legion-<project-hash>           │    │
│  │                                                  │    │
│  │  Window 1: Claude Code instance "claude"         │    │
│  │  Window 2: Claude Code instance "refactor"       │    │
│  │  Window 3: Plain shell "shell"                   │    │
│  │  ...                                             │    │
│  │                                                  │    │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Two Tmux Layers

The plugin operates across two separate tmux layers:

1. **Outer tmux** — The user's normal tmux session where Neovim runs. The plugin installs hooks and keybindings here (popup toggle key, `after-select-window` hook for auto-reopen).

2. **Inner tmux** — A dedicated tmux server on socket `claude-legion` (`tmux -L claude-legion`). This is completely separate from the user's tmux. All Claude Code processes and shell instances live here as windows in a project-scoped session.

The popup bridges the two: `tmux display-popup` in the outer tmux runs `tmux attach-session` against the inner tmux server.

## Instance Lifecycle

### Creation
- `ClaudeCodeNew` or `<leader>an` creates a new tmux window in the inner server
- The window runs `claude` CLI (or a plain shell for `ClaudeTerminal`)
- Each window gets custom tmux options: `@claude_name`, `@claude_type`, `@claude_persistent`
- First instance also creates the session with `status off`, `base-index 1`, and keybindings

### Display
- Instances are shown via `tmux display-popup` (default 90% width/height)
- The popup attaches to the inner tmux session, showing the selected window
- `Alt-1` through `Alt-9` switch between windows inside the popup (inner tmux keybindings)
- Dismiss with `Alt-g` (configurable) — this is bound as `detach-client` in the inner tmux

### Toggle behavior
- `ClaudeCode` / `<leader>ac` toggles: if no instance exists, creates one; otherwise shows the current instance in the popup
- When the popup is closed (via detach), the outer tmux keybinding for `Alt-g` reopens it
- The `after-select-window` hook auto-reopens the popup when switching outer tmux windows (so it follows you across tmux windows)

### Persistence
- By default, all instances are **ephemeral** — killed when Neovim exits (`VimLeavePre` autocmd)
- Pinning an instance (`s` in Telescope, or `ClaudeCodePersist`) sets `@claude_persistent=1`
- Persistent instances survive Neovim exit; on next Neovim start, `reconnect()` re-adopts them
- `persist_all()` pins/unpins all instances at once

### Cleanup
- `VimLeavePre` kills all non-persistent windows, then kills the session if nothing remains
- Popup hooks and outer tmux keybindings are cleaned up on exit

## Project Isolation

Sessions are scoped by project directory:
- Session name = `claude-legion-` + 8-char hash of `vim.fn.getcwd()`
- Multiple Neovim instances in different projects get independent sets of Claude Code instances
- Same project in multiple Neovim instances shares the same tmux session (reconnect on startup)

## Instance Management (Telescope Picker)

The Telescope picker (`<leader>aa` / `ClaudeCodeSelect`) is the main management UI:

| Key | Action |
|-----|--------|
| `Enter` | Open selected instance in popup |
| `a` | Create new Claude Code instance |
| `t` | Create new plain shell instance |
| `x` | Kill selected instance |
| `s` | Toggle pin (persistent) on selected |
| `S` | Toggle pin on all instances |
| `r` | Rename selected instance |
| `J` / `K` | Reorder instances (swap window positions) |

The picker shows a live terminal preview (with ANSI color rendering) of the selected instance via `capture-pane`.

After each action, the picker refreshes in-place (re-opens with cursor on the affected instance).

## Sending Text to Instances

- Visual select text, then `<leader>as` / `:'<,'>ClaudeCodeSend`
- Single-line text: sent via `send-keys`
- Multi-line text: written to a temp file, loaded into tmux paste buffer, then pasted

## Worktree Management

Separate from instances, the plugin manages git worktrees:

- `ClaudeWorktreeCreate` — prompts for branch name and base, creates worktree inside the bare repo directory, opens a new **outer** tmux window at that path
- `ClaudeWorktreeList` — Telescope picker to open or delete worktrees
- Worktrees open in outer tmux windows (not the inner claude-legion server) — they're regular terminal sessions for editing, not Claude Code instances

## File Auto-Reload

When switching back from the popup to Neovim:
- `FocusGained` and `BufEnter` autocommands trigger `checktime`
- This picks up files modified by Claude Code while the popup was active
- `hide()` also explicitly calls `checktime` when closing the popup

## Quick Switch

With `quick_switch = true` (default):
- `Alt-1` through `Alt-9` in Neovim jump directly to instance N (by window index)
- Inside the popup, the same keys are handled by inner tmux to switch windows

## What's Missing / Pain Points (pre-redesign)

- Instances are tied to a single Neovim instance's lifecycle (non-persistent ones die with Neovim)
- No way to see instance output without opening the popup
- No structured communication between instances (only manual text sending)
- Worktrees and instances are separate concepts with no linking
- No way to run an instance headless / in background and get notified on completion
- State is entirely in tmux window options — no persistent database or file-based state
