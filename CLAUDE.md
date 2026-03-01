# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A macOS calendar privacy utility that creates "Busy" placeholder events from a personal calendar to share availability without revealing sensitive details. Uses Swift with EventKit framework.

## Key Files

- `Sources/BusyCal/main.swift` - Main Swift source (all logic in one file)
- `Package.swift` - Swift Package Manager manifest
- `scripts/install.sh` - Builds and installs launchd agent
- `scripts/uninstall.sh` - Removes launchd agent

## Architecture

### Sync Strategy
1. Fetch source events (EventKit expands recurring instances automatically)
2. Apply filters (all-day, weekends, non-work hours) incrementally
3. Match existing destination events by start/end time
4. Create new / update existing / remove orphaned destination events
5. Date range: 30 days back, 90 days forward

### Configuration
All configuration is via `BUSYCAL_`-prefixed environment variables (read in `Sources/BusyCal/main.swift` via `ProcessInfo`). The install script prompts for values interactively and writes them into the launchd plist's `EnvironmentVariables` dict.

Key variables: `BUSYCAL_SOURCE_CALENDAR`, `BUSYCAL_DESTINATION_CALENDAR`, `BUSYCAL_SOURCE_ACCOUNT`, `BUSYCAL_DESTINATION_ACCOUNT`, `BUSYCAL_TITLE`, `BUSYCAL_INCLUDE_ALL_DAY`, `BUSYCAL_FILTER_WEEKENDS`, `BUSYCAL_FILTER_NON_WORK_HOURS`, `BUSYCAL_WORK_START_HOUR`, `BUSYCAL_WORK_END_HOUR`

## Development Notes

### Building
- Uses Swift Package Manager: `swift build -c release`
- `scripts/install.sh` handles the build and ad-hoc code signing (`codesign -s -`) for EventKit access

### Key Design Decisions
- Event uniqueness is based on start/end time matching
- All event details (title, description, location) are stripped for privacy
- `Set<EKEvent>` uses NSObject identity — works because the same array instances are used throughout a sync
- Filters are applied incrementally (all-day -> weekends -> work hours) for accurate per-filter logging
