# TimeWatcher

A git-based time tracker that watches your filesystem for changes and automatically records work activity. No cloud services needed — syncs across machines via git.

## How it works

1. **Watch** — Run `tw watch` in your project directory. TimeWatcher monitors file changes and logs each event as a JSON file.
2. **Report** — Run `tw report` to see your activity for the day. Events are grouped into stretches of continuous work per project.
3. **Sync** — The data directory is a git repo. Push/pull to share activity across machines.

Each file change creates an event with a timestamp, repo name, hashed file path, and event type. Rapid saves to the same file are debounced (1 event per minute), but editing different files produces separate events.

Reports show stretches of activity by expanding each event into a 10-minute window (5 min before, 5 min after). Overlapping windows merge into a single stretch.

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

# Markdown format (for pasting into notes, PRs, etc.)
tw report --md
```

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

The data directory is automatically initialized as a git repo and commits are made as events are recorded. To sync across machines:

```sh
cd ~/.local/share/time_watcher
git remote add origin <your-private-repo>
git push -u origin main
```

On another machine, clone into the same path and TimeWatcher will pick it up.

## Development

```sh
mix test              # Run tests
mix format            # Format code
mix credo --strict    # Lint
mix dialyzer          # Type checking
```

## License

MIT
