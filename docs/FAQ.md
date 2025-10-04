# Frequently Asked Questions (FAQ)

## General Questions

### What is ZigStack?
ZigStack is a command-line tool written in Zig for organizing, analyzing, and managing files. It provides six commands for different file management tasks: organize, analyze, dedupe, archive, watch, and workspace.

### Is ZigStack safe to use?
Yes! ZigStack is designed with safety in mind:
- Most commands run in dry-run mode by default (no changes made)
- File moves support automatic rollback on errors
- Conflicts are resolved by renaming files (no overwrites)
- You can always preview what will happen before making changes

### What operating systems are supported?
ZigStack works on:
- macOS (tested on 10.15+)
- Linux (all major distributions)
- Windows (Windows 10+)

### Do I need to know Zig to use ZigStack?
No! ZigStack is a command-line tool that you use from your terminal. You don't need to know Zig programming.

## Installation & Setup

### How do I install ZigStack?
See the [Getting Started Guide](getting-started.md#installation) for detailed installation instructions. Briefly:
1. Install Zig 0.13.0 or later
2. Clone the repository
3. Run `zig build`
4. Use `./zig-out/bin/zigstack`

### Can I install ZigStack globally?
Yes! Add the binary to your PATH or create an alias:
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:/path/to/zigstack/zig-out/bin"
```

### How do I update ZigStack?
```bash
cd /path/to/zigstack
git pull
zig build
```

## Using ZigStack

### How do I preview changes before making them?
Most commands run in preview/dry-run mode by default. Use `--move` or `--delete` flags to actually make changes:
```bash
# Preview only
zigstack organize ~/Downloads

# Actually move files
zigstack organize --move ~/Downloads
```

### Can I undo file organization?
ZigStack doesn't have a built-in undo feature, but:
- Always run in dry-run mode first to preview
- Keep backups of important files
- File move operations have automatic rollback on errors

### What file types does ZigStack support?
ZigStack works with all file types. It categorizes files into:
- Documents (PDF, TXT, DOC, etc.)
- Images (JPG, PNG, GIF, etc.)
- Videos (MP4, AVI, MKV, etc.)
- Audio (MP3, WAV, FLAC, etc.)
- Archives (ZIP, TAR, GZ, etc.)
- Code (JS, PY, ZIG, RS, etc.)
- Data (JSON, XML, CSV, etc.)
- Configuration (INI, YAML, TOML, etc.)
- Other (unknown extensions)

### Can I customize file categories?
Yes! Create a custom `config.json` file:
```bash
zigstack organize --config my-config.json --move ~/path
```

See [Configuration Reference](reference/configuration.md) for details.

## Commands

### What's the difference between organize and watch?
- **organize**: One-time organization of existing files
- **watch**: Continuously monitors a directory and organizes new files automatically

### How do I stop the watch command?
Press `Ctrl+C` to stop watching. (Daemon mode with PID file support is planned.)

### Does dedupe actually delete files?
By default, no! It runs in dry-run mode. Use `--delete` or `--hardlink` to actually remove duplicates:
```bash
zigstack dedupe --auto keep-newest --delete ~/Downloads
```

### What does workspace cleanup remove?
It removes build artifacts and dependencies based on strategy:
- **conservative**: Only obvious temporary files (*.pyc, __pycache__)
- **moderate**: Build artifacts + common caches (node_modules if old)
- **aggressive**: All build artifacts and dependencies

See [workspace command docs](commands/workspace.md) for details.

### How does archive determine file age?
It uses the file's modification time by default. You specify age like:
- `1d` = 1 day
- `7d` = 7 days
- `1mo` = 1 month
- `6mo` = 6 months
- `1y` = 1 year

## Performance

### How fast is ZigStack?
Performance varies by command and options:
- **organize**: >1000 files/sec for basic organization
- **analyze**: >1000 files/sec without --content flag
- **dedupe**: ~500 files/sec (depends on file sizes and hashing)

### Can I process large directories?
Yes! ZigStack handles large directories efficiently:
- Use `--recursive` with `--max-depth` to control recursion
- Use `--min-size` to filter small files
- Memory-efficient hashing for duplicates

### How much memory does ZigStack use?
Typically <100MB for most operations. Large directory scans may use more.

## Troubleshooting

### Permission denied errors
Ensure you have read/write permissions:
```bash
# Check permissions
ls -la /path/to/directory

# Fix if needed (Linux/macOS)
chmod u+rw /path/to/directory/*
```

### Files not organizing as expected
Check:
1. File extension is recognized (see default categories above)
2. Use `--verbose` flag for detailed output
3. Try with a small test directory first

### Watch command not working
Common issues:
1. Directory path is incorrect
2. No write permissions
3. Rules file syntax error (use `--validate-rules`)

### Duplicate detection seems slow
This is normal for large files:
- Hashing large files takes time
- Use `--min-size` to skip small files
- Results are accurate (SHA-256 hashing)

## Advanced Usage

### Can I use ZigStack in scripts?
Yes! All commands support:
- Exit codes (0 = success, non-zero = error)
- `--json` output for parsing
- `--verbose` for detailed logging

### How do I export results?
Use `--json` or `--format` flags:
```bash
# Export analysis as JSON
zigstack analyze --json --output report.json ~/path

# Export duplicates as CSV
zigstack dedupe --format csv --output dupes.csv ~/path
```

### Can I run multiple commands at once?
Yes, but be careful with concurrent file operations:
```bash
# Safe: Different directories
zigstack organize ~/Downloads &
zigstack analyze ~/Documents

# Risky: Same directory
# Don't do this - may cause conflicts
```

### How do I organize only specific file types?
Use `--categories` flag (archive command) or custom config:
```bash
# Archive only videos and images
zigstack archive --older-than 6mo --categories "videos,images" --dest ~/Archive ~/media
```

## Contributing

### How can I contribute?
- Report bugs on GitHub
- Request features
- Submit pull requests
- Improve documentation
- Share your use cases

### Where's the source code?
[GitHub repository](https://github.com/yourusername/zigstack)

## Still Have Questions?

- Check the [Troubleshooting Guide](troubleshooting.md)
- Read command-specific docs in [commands/](commands/)
- Open an issue on GitHub
