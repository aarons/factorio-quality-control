# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Factorio mod called "Quality Control" that automatically changes machine quality over time based on manufacturing hours. The mod tracks how long machines have been producing items and applies quality upgrades or downgrades based on configurable settings.

## Engineering Principles

Keep code clear to understand for other engineers. Clarity is more important than brevity or clever solutions.

Correct use of factorio's API is vital; it's very important to validate assumptions about the API because it changes over time.

IMPORTANT: The API documentation is available via context7 with this library ID: "context7/lua-api_factorio-stable"

## Architecture

### Core Files
- `control.lua` - Main mod logic handling quality changes, machine tracking, and event handlers
- `settings.lua` - Mod settings definitions for quality direction, timing, and notifications
- `info.json` - Mod metadata including name, version, dependencies, and Factorio version requirements
- `locale/en/locale.cfg` - Localization strings for settings and alert messages

### Development Cycle

- Read the entire control.lua file for logic or debugging purposes; it's small and can be fully understood easily.
- After making changes, the engineer will manage testing and validation.


