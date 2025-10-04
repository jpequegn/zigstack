# Command Reference

Detailed documentation for all ZigStack commands.

## Available Commands

- **[organize](organize.md)** - Organize files by extension, date, size, or duplicates
- **[analyze](analyze.md)** - Disk usage analysis with detailed breakdowns
- **[dedupe](dedupe.md)** - Find and manage duplicate files
- **[archive](archive.md)** - Archive old files based on age
- **[watch](watch.md)** - Monitor directory and auto-organize files
- **[workspace](workspace.md)** - Manage developer workspace projects

## Command Patterns

All commands follow the same pattern:
```bash
zigstack <command> [OPTIONS] <directory>
```

### Common Options

Most commands support these common flags:
- `-h, --help` - Display command-specific help
- `-V, --verbose` - Enable detailed logging
- `-d, --dry-run` - Preview changes without making them

### Getting Help

```bash
# See all commands
zigstack --help

# Get command-specific help
zigstack organize --help
zigstack analyze --help
zigstack dedupe --help
zigstack archive --help
zigstack watch --help
zigstack workspace --help
```

## Quick Reference

| Command | Primary Use | Default Mode | Requires Dest |
|---------|-------------|--------------|---------------|
| organize | File categorization | Dry-run | No |
| analyze | Disk usage | Read-only | No |
| dedupe | Find duplicates | Dry-run | No |
| archive | Age-based archiving | Dry-run | Yes (--dest) |
| watch | Auto-organization | Active | No |
| workspace | Dev cleanup | Dry-run | No |

## See Also

- [Getting Started Guide](../getting-started.md)
- [Tutorials](../guides/)
- [FAQ](../FAQ.md)
- [Troubleshooting](../troubleshooting.md)
