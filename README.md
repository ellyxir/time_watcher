# TimeWatcher

A git-based time tracker that watches your filesystem for changes and automatically records work activity. No cloud services needed — syncs across machines via git.

## Why

I do consulting work for different clients. I often work in short bursts, so I can't easily use a Toggl-like solution where you click on and off. I take breaks all the time or get distracted. I really needed a system that would automatically track my work for me.

TimeWatcher does this by watching directories you specify and recording file activity. As long as two activities are close together (within the cooldown window — 5 minutes by default), they're considered consecutive work time. Modifying, adding, or removing a file all count as "work".

Hope you find it helpful!

## How it works

1. **Watch** — Run `tw watch` in your project directory. TimeWatcher monitors file changes and logs each event as a JSON file.
2. **Report** — Run `tw report` to see your activity for the day. Events are grouped into stretches of continuous work per project.
3. **Sync** — The data directory is a git repo. Push/pull to share activity across machines.

Each file change creates an event with a timestamp, repo name, hashed file path, and event type. Rapid saves to the same file are debounced (1 event per minute), but editing different files produces separate events.

Reports show stretches of continuous activity. Events within the merge window (10 minutes by default) are grouped into the same stretch. The reported duration is the actual time between the first and last event in each stretch. A single isolated event doesn't produce a stretch since it can't establish a duration.

## Install

### Nix

```sh
nix profile install git+https://codeberg.org/ellyxir/time_watcher
```

### From source

Requires Elixir 1.18+.

```sh
git clone https://codeberg.org/ellyxir/time_watcher.git && cd time_watcher
mix deps.get
MIX_ENV=prod mix release time_watcher
```

This builds the release at `_build/prod/rel/time_watcher/`. The `tw` command lives inside it:

```sh
# Run directly from the build
_build/prod/rel/time_watcher/bin/tw report

# Or symlink it onto your PATH
ln -s "$(pwd)/_build/prod/rel/time_watcher/bin/tw" ~/.local/bin/tw
```

## Usage

### Start the watcher daemon

```sh
# Watch the current directory (runs in background)
tw watch

# Watch specific directories
tw watch ~/projects/app1 ~/projects/app2

# Verbose mode: run in foreground, print events as they happen
tw watch -v
```

Without `-v`, the daemon runs in the background and you can close the terminal.
With `-v`, it stays in the foreground and prints each file change as it's recorded — useful for debugging or seeing activity in real-time. Press Ctrl+C to stop.

### Manage watched directories

While the daemon is running, you can add or remove directories:

```sh
# List currently watched directories
tw list

# Add a directory to the running watcher
tw add ~/projects/app3

# Remove a directory from the watcher
tw remove ~/projects/app1
```

### View a report

```sh
# Today's activity
tw report

# Specific date
tw report 2026-02-25

# Last 7 days
tw report --days 7

# Specific date range
tw report --from 2026-02-20 --to 2026-02-27

# Markdown format (for pasting into notes, PRs, etc.)
tw report --md

# Custom cooldown (minutes of inactivity that still count as continuous work)
tw report --cooldown 15

# Combine options
tw report --days 7 --md --cooldown 10
tw report --from 2026-02-20 --to 2026-02-27 --md --cooldown 10
```

The default cooldown is 5 minutes — if you stop editing for more than 5 minutes, it's treated as a break. Use `--cooldown` to adjust this threshold.

The `--days N` flag shows activity for the last N days (including today). The `--from DATE --to DATE` flags let you specify an explicit date range. Days with no activity are silently skipped.

Example output:

```
Activity for 2026-02-25:

  09:12 - 10:45  my_app    (1h 33m)
  13:00 - 14:20  my_app    (1h 20m)
  14:30 - 15:10  docs_site (0h 40m)

Total: 3h 33m
```

With `--md`:

```markdown
## Activity for 2026-02-25

| Time | Project | Duration |
|------|---------|----------|
| 09:12 - 10:45 | my_app | 1h 33m |
| 13:00 - 14:20 | my_app | 1h 20m |
| 14:30 - 15:10 | docs_site | 0h 40m |

**Total: 3h 33m**
```

### Reset events

Delete recorded events when you want to clear your history:

```sh
# Delete today's events
tw reset

# Delete events for a specific date
tw reset 2026-02-25

# Delete all events
tw reset --all
```

Deletions are staged in git but not committed. Run `tw commit` afterward to finalize:

```sh
tw reset 2026-02-25
tw commit -m "remove feb 25 data"
```

### Decode file paths

File paths are stored as hashes for privacy. On the same machine where events were recorded, you can decode them back to actual paths:

```sh
# Decode today's events for a repo
tw decode ~/projects/my_app

# Decode events for a specific date
tw decode ~/projects/my_app 2026-02-25
```

Example output:

```
Events for my_app on 2026-02-25:

  [09:12:34] modified lib/my_app/server.ex
  [09:15:22] modified test/my_app/server_test.exs
  [09:18:01] created lib/my_app/client.ex

Decoded 3/3 file paths
```

This works by hashing all files in the repo directory and matching against the stored hashes. Files that have been deleted or renamed since the event won't be decoded. Note: decoding can be slow on large repositories since every file must be hashed.

### Version

```sh
tw --version
tw -V
```

## Data storage

Events are stored as JSON files in `~/.local/share/time_watcher/`, organized by date:

```
~/.local/share/time_watcher/
  2026-02-25/
    1740000000_hostname_1.json
    1740000120_hostname_2.json
  2026-02-26/
    ...
```

Filenames follow the pattern `{timestamp}_{hostname}_{unique}.json`:
- **timestamp** — Unix timestamp in seconds when the event occurred
- **hostname** — machine name, for distinguishing events when syncing across machines
- **unique** — incrementing integer to prevent collisions if multiple events occur in the same second

Each event file contains:

```json
{
  "timestamp": 1740000000,
  "repo": "my_app",
  "hashed_path": "a1b2c3...",
  "event_type": "modified"
}
```

File paths are SHA-256 hashed for privacy — the actual filenames you edit are never stored.

### Syncing with git

The data directory can be version-controlled with git to sync across machines. Use `tw commit` to commit your event data:

```sh
# Commit current event data
tw commit

# Commit with a custom message
tw commit -m "end of day sync"
```

To set up syncing:

```sh
cd ~/.local/share/time_watcher
git init  # if not already a repo
git remote add origin <your-private-repo>
tw commit
git push -u origin main
```

On another machine, clone into the same path and TimeWatcher will pick it up.

## Configuration file

TimeWatcher can be configured via a config file at `~/.config/time_watcher/config.exs` (or `$XDG_CONFIG_HOME/time_watcher/config.exs` if set).

### Available options

- **dirs** — list of directories to watch by default
- **verbose** — enable verbose event logging (requires `-v` flag to see output)
- **cooldown** — default cooldown in minutes for reports
- **ignore_patterns** — list of glob patterns for filenames to ignore (e.g., temp files created by editors or tools)

### Example config

```elixir
import Config

config :time_watcher,
  dirs: ["~/projects/client_a", "~/projects/client_b"],
  verbose: false,
  cooldown: 10,
  ignore_patterns: [".watchman-cookie-*", "*.swp", "*~"]
```

The `ignore_patterns` option is useful for filtering out noise from tools that create temporary files. Common patterns:

- `.watchman-cookie-*` — Phoenix/watchman live reload check files
- `*.swp`, `*.swo` — Vim swap files
- `*~` — Backup files from various editors
- `.#*` — Emacs lock files

### CLI override

Command-line flags always override config values:

```sh
# Config has verbose: false, but -v overrides it
tw watch -v

# Config has cooldown: 10, but --cooldown overrides it
tw report --cooldown 5

# Config has dirs set, but explicit dirs override them
tw watch ~/other/project
```

## Development

```sh
mix test              # Run tests
mix format            # Format code
mix credo --strict    # Lint
mix dialyzer          # Type checking
```

## License

Apache 2.0
