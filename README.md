# BusyCal

A macOS utility that mirrors your personal calendar events as "Busy" placeholders in a separate calendar. Share your availability without revealing event details.

## How It Works

BusyCal reads events from a source calendar and creates corresponding "Busy" events in a destination calendar. All event details (title, description, location) are stripped for privacy. It runs automatically every hour via a launchd agent.

**Key features:**
- Handles recurring events correctly via EventKit
- Filters out all-day events, weekends, and non-work hours
- Three-phase sync: create new, update existing, remove orphaned events
- 120-day sync window (30 days back, 90 days forward)

## Requirements

- macOS 13+ (Ventura or later)
- Swift toolchain (Xcode Command Line Tools or full Xcode install)
- Two calendars configured in Apple Calendar (source + destination)

## Setup

### 1. Install

```bash
./scripts/install.sh
```

The install script builds the project, then prompts for configuration values interactively. Press Enter to accept the defaults shown in brackets. On first run, macOS will prompt you to grant Calendar access.

To pre-fill the prompts, set environment variables before running:

```bash
export BUSYCAL_SOURCE_CALENDAR="Personal"
export BUSYCAL_DESTINATION_CALENDAR="Busy"
./scripts/install.sh
```

Or use a `.env` file:

```bash
source .env && ./scripts/install.sh
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `BUSYCAL_SOURCE_CALENDAR` | `Home` | Calendar to mirror from (case-sensitive) |
| `BUSYCAL_SOURCE_ACCOUNT` | _(none)_ | Account name to disambiguate (e.g. `iCloud`) |
| `BUSYCAL_DESTINATION_CALENDAR` | `Busy` | Calendar for placeholder events (case-sensitive) |
| `BUSYCAL_DESTINATION_ACCOUNT` | _(none)_ | Account name to disambiguate (e.g. `Gmail`) |
| `BUSYCAL_TITLE` | `Busy` | Title for mirrored events |
| `BUSYCAL_INCLUDE_ALL_DAY` | `false` | Mirror all-day events |
| `BUSYCAL_FILTER_WEEKENDS` | `true` | Skip Saturday/Sunday events |
| `BUSYCAL_FILTER_NON_WORK_HOURS` | `true` | Only include events during work hours |
| `BUSYCAL_WORK_START_HOUR` | `8` | Work day start (0–23) |
| `BUSYCAL_WORK_END_HOUR` | `18` | Work day end (0–23) |

### 2. Reconfigure

Re-run `./scripts/install.sh` to change configuration. Your previous values are not carried over — use env vars or a `.env` file to persist them.

### 3. Uninstall

```bash
./scripts/uninstall.sh
```

This stops and removes the launchd agent. Existing "Busy" events in your destination calendar are left untouched.

## Logs

```bash
log show --predicate 'subsystem == "com.user.busycal"' --last 1h
```

Or use Console.app and filter by subsystem `com.user.busycal`.
