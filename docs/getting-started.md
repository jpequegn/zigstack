# Getting Started with ZigStack

Welcome to ZigStack! This guide will help you install, configure, and start using ZigStack to organize your files efficiently.

## What is ZigStack?

ZigStack is a powerful command-line file organization tool that helps you:
- **Organize files** automatically by extension, date, size, and more
- **Analyze disk usage** with detailed breakdowns and visualizations
- **Find duplicates** and reclaim disk space
- **Archive old files** automatically based on age
- **Watch directories** for automatic organization
- **Manage developer workspaces** and clean up build artifacts

## Installation

### Prerequisites

- [Zig](https://ziglang.org/download/) 0.13.0 or later (0.15.1 recommended)
- Operating System: macOS, Linux, or Windows

### Build from Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/zigstack.git
   cd zigstack
   ```

2. **Build the project:**
   ```bash
   zig build
   ```

3. **The executable will be created in `zig-out/bin/zigstack`**

4. **(Optional) Add to your PATH:**

   **macOS/Linux:**
   ```bash
   # Add to ~/.bashrc, ~/.zshrc, or ~/.profile
   export PATH="$PATH:/path/to/zigstack/zig-out/bin"

   # Or create an alias
   alias zigstack="/path/to/zigstack/zig-out/bin/zigstack"
   ```

   **Windows:**
   ```powershell
   # Add to your PATH environment variable or create an alias
   Set-Alias -Name zigstack -Value "C:\path\to\zigstack\zig-out\bin\zigstack.exe"
   ```

### Verify Installation

```bash
zigstack --version
```

You should see the version information displayed.

## Quick Start

### 1. Basic File Organization

Let's start with a simple example. Suppose you have a messy Downloads folder:

```bash
# Preview what zigstack would do (no changes made)
zigstack organize ~/Downloads
```

This command analyzes your Downloads folder and shows how files would be organized by category (Documents, Images, Videos, etc.).

### 2. Actually Organize Files

When you're ready to organize:

```bash
# Create directories and move files
zigstack organize --move ~/Downloads
```

Your files will now be organized into category folders!

### 3. Analyze Disk Usage

Want to see what's taking up space?

```bash
# See disk usage breakdown
zigstack analyze ~/Documents
```

This shows you which categories of files are using the most space.

### 4. Find Duplicate Files

Reclaim space by finding duplicates:

```bash
# Find duplicate files
zigstack dedupe ~/Downloads
```

### 5. Clean Up Your Workspace

If you're a developer:

```bash
# Scan your projects
zigstack workspace scan ~/Code

# Clean up build artifacts from inactive projects
zigstack workspace cleanup --strategy moderate ~/Code
```

## Common Workflows

### Daily Downloads Organization

Set up automatic organization for your Downloads folder:

```bash
# Watch Downloads and organize new files automatically
zigstack watch ~/Downloads
```

### Monthly Archive Workflow

Archive old documents monthly:

```bash
# Archive documents older than 6 months
zigstack archive --older-than 6mo --dest ~/Archive ~/Documents
```

### Developer Workspace Maintenance

Keep your development folder clean:

```bash
# Weekly scan
zigstack workspace scan ~/Code

# Monthly cleanup of inactive projects
zigstack workspace cleanup --strategy moderate --inactive-only ~/Code
```

## Understanding the Commands

ZigStack provides six main commands:

| Command | Purpose | Common Use |
|---------|---------|------------|
| `organize` | Organize files by category | Clean up messy folders |
| `analyze` | Disk usage analysis | Find space hogs |
| `dedupe` | Find duplicate files | Reclaim disk space |
| `archive` | Archive old files | Long-term storage |
| `watch` | Auto-organize files | Maintain organization |
| `workspace` | Manage dev projects | Clean build artifacts |

## Next Steps

- Read the [Command Reference](commands/) for detailed documentation on each command
- Explore [Tutorials](guides/) for common workflows
- Check the [FAQ](FAQ.md) for frequently asked questions
- Review [Configuration](reference/configuration.md) for customization options

## Getting Help

- Use `zigstack --help` to see all available commands
- Use `zigstack <command> --help` for command-specific help
- See the [Troubleshooting Guide](troubleshooting.md) for common issues
- Open an issue on GitHub for bugs or feature requests

## Safety Features

ZigStack is designed with safety in mind:

- **Dry-run mode by default**: Most commands preview changes before making them
- **Rollback support**: File move operations can be rolled back on errors
- **Conflict resolution**: Automatic file renaming when conflicts occur
- **Backup recommendations**: Always backup important files before bulk operations

## Quick Reference

```bash
# Organize files
zigstack organize --move /path/to/directory

# Analyze disk usage
zigstack analyze /path/to/directory

# Find duplicates
zigstack dedupe /path/to/directory

# Archive old files
zigstack archive --older-than 6mo --dest ~/Archive /path

# Watch directory
zigstack watch /path/to/directory

# Clean workspace
zigstack workspace cleanup --dry-run ~/Code
```

Happy organizing! 🎉
