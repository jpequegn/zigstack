# ZigStack Documentation

Complete documentation for ZigStack file organization and management tool.

## Table of Contents

### Getting Started
- **[Getting Started Guide](getting-started.md)** - Installation, quick start, and basic concepts
- **[FAQ](FAQ.md)** - Frequently asked questions
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions

### Command Reference
- **[organize](commands/organize.md)** - Organize files by extension, date, size, duplicates
- **[analyze](commands/analyze.md)** - Disk usage analysis and reporting
- **[dedupe](commands/dedupe.md)** - Find and manage duplicate files
- **[archive](commands/archive.md)** - Archive old files automatically
- **[watch](commands/watch.md)** - Monitor and auto-organize directories
- **[workspace](commands/workspace.md)** - Manage developer workspaces

### Tutorials & Guides
- **[Organizing Files](guides/organizing-files.md)** - File organization workflows and best practices
- **[Cleaning Workspaces](guides/cleaning-workspaces.md)** - Developer workspace management
- **[Automation with Watch](guides/automation.md)** - Set up automatic file organization
- **[Advanced Usage](guides/advanced-usage.md)** - Power user tips and tricks

### Reference
- **[Configuration](reference/configuration.md)** - Configuration file format and options
- **[Watch Rules](reference/watch-rules.md)** - Custom rules for watch command
- **[Export Formats](reference/export-formats.md)** - JSON and CSV export specifications

## Quick Links

### Common Tasks
- [Install ZigStack](getting-started.md#installation)
- [Organize a messy folder](guides/organizing-files.md#basic-organization)
- [Find duplicate files](commands/dedupe.md#finding-duplicates)
- [Archive old documents](commands/archive.md#archiving-by-age)
- [Clean up dev workspace](guides/cleaning-workspaces.md#cleaning-node-projects)
- [Set up auto-organization](guides/automation.md#basic-watch-setup)

### By Use Case
- **Home User**: organize, dedupe, archive
- **Developer**: workspace, organize, watch
- **System Admin**: analyze, dedupe, archive, watch
- **Power User**: All commands with custom configuration

## Documentation Structure

```
docs/
├── README.md (this file)
├── getting-started.md
├── FAQ.md
├── troubleshooting.md
├── commands/
│   ├── organize.md
│   ├── analyze.md
│   ├── dedupe.md
│   ├── archive.md
│   ├── watch.md
│   └── workspace.md
├── guides/
│   ├── organizing-files.md
│   ├── cleaning-workspaces.md
│   ├── automation.md
│   └── advanced-usage.md
└── reference/
    ├── configuration.md
    ├── watch-rules.md
    └── export-formats.md
```

## Contributing to Documentation

Documentation improvements are welcome! Please:
1. Keep examples clear and tested
2. Update command help text if behavior changes
3. Add new use cases to guides
4. Keep FAQ updated with common questions

## Getting Help

- Read the [Getting Started Guide](getting-started.md) for basics
- Check the [FAQ](FAQ.md) for common questions
- See [Troubleshooting](troubleshooting.md) for issues
- Open a GitHub issue for bugs or feature requests
