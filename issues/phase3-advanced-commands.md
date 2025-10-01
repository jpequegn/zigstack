# Phase 3: Advanced Commands - GitHub Issues

## Issue #21: Implement 'archive' Command - Basic Functionality

**Title**: Create age-based file archiving command

**Description**:
Implement command to archive old files based on modification time, with support for compression and directory structure preservation.

**Tasks**:
- [ ] Create `src/commands/archive.zig`
- [ ] Implement age filtering (older than N days/months/years)
- [ ] Add directory structure preservation options
- [ ] Implement file copying to archive location
- [ ] Add dry-run mode to preview archive
- [ ] Support filtering by file type/category
- [ ] Add progress reporting for large archives
- [ ] Write comprehensive tests

**Command Interface**:
```bash
zigstack archive --older-than 6mo --dest ~/Archive /path
# Archives files older than 6 months to ~/Archive
#
# Found 456 files older than 6 months (2.3 GB)
# Archive destination: /Users/user/Archive/2024-01-15/
#
# Archiving:
#   Documents: 123 files (450 MB)
#   Images: 234 files (1.2 GB)
#   Videos: 45 files (650 MB)
#   Other: 54 files (20 MB)
#
# [=========>          ] 45% (210/456 files)
```

**Options**:
- `--older-than <DURATION>`: Age threshold (1d, 7d, 1mo, 6mo, 1y)
- `--dest <PATH>`: Archive destination directory
- `--preserve-structure`: Keep original directory structure
- `--flatten`: Flatten all files into destination
- `--move`: Move instead of copy (remove from source)
- `--categories <LIST>`: Only archive specific categories
- `--min-size <SIZE>`: Only archive files above size

**Time Parsing**:
- Support formats: "7d", "1mo", "6mo", "1y", "30d"
- Calculate timestamp threshold from current time
- Use modification time (mtime) by default

**Acceptance Criteria**:
- Correctly identifies files by age
- Archive preserves file metadata
- Progress reporting is accurate
- Dry-run shows accurate preview
- Tests cover various time ranges

**Estimated Effort**: 6-8 hours

**Dependencies**: Phase 1 complete

**Labels**: command, archive, enhancement, feature

---

## Issue #22: Implement 'archive' Command - Compression

**Title**: Add compression support to archive command

**Description**:
Extend archive command to support creating compressed archives (tar.gz, zip) for efficient storage.

**Tasks**:
- [ ] Add tar.gz archive creation
- [ ] Add zip archive creation (if Zig std supports)
- [ ] Implement compression level options
- [ ] Calculate compression ratio and savings
- [ ] Handle large files efficiently (streaming)
- [ ] Add archive naming strategies
- [ ] Test compression with various file types
- [ ] Document compression behavior

**Compression Interface**:
```bash
zigstack archive --compress tar.gz --older-than 1y ~/Documents
# Creates: ~/Archive/documents-2024-01-15.tar.gz
#
# Archiving 234 files (1.2 GB)...
# Compressed to 456 MB (62% savings)
```

**Options**:
- `--compress <FORMAT>`: Archive format (tar.gz, zip, none)
- `--compression-level <1-9>`: Compression level
- `--archive-name <NAME>`: Custom archive filename
- `--split-size <SIZE>`: Split archives larger than size

**Compression Strategy**:
- Use Zig's std.compress for gzip
- Consider external zip library if needed
- Stream files to avoid memory pressure
- Calculate checksums for verification

**Acceptance Criteria**:
- Archives created correctly
- Compression ratios are reasonable
- Large files handled efficiently
- Archive format is standard and extractable
- Tests verify archive integrity

**Estimated Effort**: 6-8 hours

**Dependencies**: Issue #21

**Labels**: command, archive, enhancement, feature, compression

---

## Issue #23: Implement 'watch' Command - Basic Monitoring

**Title**: Create file system monitoring daemon

**Description**:
Implement a daemon mode that monitors directories for changes and automatically applies organization rules.

**Tasks**:
- [ ] Create `src/commands/watch.zig`
- [ ] Implement file system event monitoring
- [ ] Detect new files, modifications, deletions
- [ ] Apply organization rules automatically
- [ ] Add logging to file for audit trail
- [ ] Implement graceful shutdown (SIGTERM/SIGINT)
- [ ] Add PID file management
- [ ] Write tests for watch functionality

**Command Interface**:
```bash
zigstack watch --rules watch-rules.json ~/Downloads
# Watching ~/Downloads for changes...
# Rules loaded: 5 rules from watch-rules.json
# Log: ~/.local/share/zigstack/watch.log
# PID: 12345
#
# [2024-01-15 10:30:15] New file: photo.jpg -> organized to ~/Downloads/images/
# [2024-01-15 10:31:22] New file: document.pdf -> organized to ~/Downloads/documents/
# [2024-01-15 10:32:45] 45 files processed, 0 errors
```

**Watch Rules Format** (JSON):
```json
{
  "rules": [
    {
      "name": "Organize new files",
      "trigger": "file_created",
      "action": "organize",
      "options": {"by_category": true}
    },
    {
      "name": "Archive old downloads",
      "trigger": "periodic",
      "interval": "daily",
      "action": "archive",
      "filter": {"older_than": "30d"},
      "options": {"dest": "~/Archive", "move": true}
    }
  ]
}
```

**Options**:
- `--rules <FILE>`: Rules configuration file
- `--daemon`: Run as background daemon
- `--log <FILE>`: Log file path
- `--interval <DURATION>`: Check interval for periodic rules

**Platform Considerations**:
- macOS: Use FSEvents API (kqueue)
- Linux: Use inotify
- Abstract platform differences in Zig std.fs.Watch

**Acceptance Criteria**:
- Reliably detects file system changes
- Rules apply correctly
- Daemon mode works stably
- Logging is comprehensive
- Graceful shutdown preserves state

**Estimated Effort**: 8-10 hours

**Dependencies**: Phase 1 and Phase 2 complete

**Labels**: command, watch, enhancement, feature, daemon, advanced

---

## Issue #24: Implement 'watch' Command - Advanced Rules

**Title**: Add advanced rule engine to watch command

**Description**:
Extend watch command with sophisticated rule matching and conditional actions.

**Tasks**:
- [ ] Implement pattern matching (glob patterns)
- [ ] Add conditional rules (if-then logic)
- [ ] Support chained actions
- [ ] Add rate limiting to prevent overload
- [ ] Implement rule priorities
- [ ] Add rule testing/validation mode
- [ ] Create rule examples and templates
- [ ] Document rule syntax thoroughly

**Advanced Rules**:
```json
{
  "rules": [
    {
      "name": "Organize work documents",
      "trigger": "file_created",
      "match": {"pattern": "*.pdf", "path_contains": "work"},
      "conditions": [
        {"size_gt": "100KB"},
        {"time_of_day": "09:00-17:00"}
      ],
      "actions": [
        {"organize": {"by_category": true, "by_date": true}},
        {"tag": {"tags": ["work", "pdf"]}}
      ],
      "priority": 10
    }
  ]
}
```

**Rule Features**:
- **Triggers**: file_created, file_modified, file_deleted, periodic
- **Matchers**: glob patterns, regex, size ranges, date ranges
- **Conditions**: file properties, time-based, custom predicates
- **Actions**: organize, archive, move, delete, tag, run_command
- **Priority**: Higher priority rules run first

**Acceptance Criteria**:
- Pattern matching works correctly
- Conditional logic evaluated accurately
- Actions execute in correct order
- Rule validation catches errors
- Documentation includes examples

**Estimated Effort**: 6-8 hours

**Dependencies**: Issue #23

**Labels**: command, watch, enhancement, feature, advanced, rules

---

## Issue #25: Implement 'workspace' Command - Project Detection

**Title**: Create developer workspace management command

**Description**:
Implement command to analyze and manage developer workspaces, detecting project types and build artifacts.

**Tasks**:
- [ ] Create `src/commands/workspace.zig`
- [ ] Implement project type detection (Node.js, Python, Rust, Zig, etc.)
- [ ] Identify build artifacts and caches
- [ ] Calculate disk usage per project
- [ ] Detect inactive projects (no recent commits/modifications)
- [ ] Generate workspace report
- [ ] Add interactive cleanup mode
- [ ] Write tests with sample projects

**Command Interface**:
```bash
zigstack workspace scan ~/Code
# Workspace Analysis: ~/Code
# ==========================
#
# Projects Found: 47
#
# By Type:
#   Node.js: 23 projects (12 GB, 8 inactive)
#   Python:  12 projects (3 GB, 2 inactive)
#   Rust:     8 projects (5 GB, 3 inactive)
#   Zig:      4 projects (1 GB, 0 inactive)
#
# Disk Usage:
#   Source code:        2.1 GB
#   Dependencies:      15.3 GB (node_modules, venv, target/)
#   Build artifacts:    4.2 GB (zig-cache, build/, dist/)
#   Git repositories:   1.8 GB (.git/)
#
# Cleanup Potential: 19.5 GB from inactive projects
```

**Project Detection**:
- **Node.js**: package.json, node_modules/
- **Python**: requirements.txt, setup.py, venv/, __pycache__/
- **Rust**: Cargo.toml, target/
- **Zig**: build.zig, zig-cache/, zig-out/
- **Go**: go.mod, go.sum
- **Java**: pom.xml, gradle.build, target/, build/

**Acceptance Criteria**:
- Accurately detects common project types
- Correctly identifies build artifacts
- Inactive project detection is configurable
- Report is comprehensive and actionable
- Tests include sample project structures

**Estimated Effort**: 7-9 hours

**Dependencies**: Phase 1 complete

**Labels**: command, workspace, enhancement, feature, developer

---

## Issue #26: Implement 'workspace' Command - Cleanup Actions

**Title**: Add interactive cleanup to workspace command

**Description**:
Extend workspace command with cleanup capabilities for build artifacts, dependencies, and inactive projects.

**Tasks**:
- [ ] Implement safe cleanup of build artifacts
- [ ] Add dependency cleanup (with warnings)
- [ ] Implement project archiving
- [ ] Add selective cleanup (by project type)
- [ ] Create cleanup strategies (conservative, moderate, aggressive)
- [ ] Add restore functionality for cleanup undo
- [ ] Implement dry-run mode
- [ ] Write tests for cleanup operations

**Cleanup Interface**:
```bash
zigstack workspace cleanup ~/Code
# Interactive Workspace Cleanup
# =============================
#
# [1] Clean build artifacts (4.2 GB)
#     - Zig: zig-cache/, zig-out/ in 4 projects
#     - Node.js: dist/, build/ in 23 projects
#     - Rust: target/ in 8 projects
#
# [2] Clean dependencies (15.3 GB) ⚠️ Requires reinstall
#     - Node.js: node_modules/ in 23 projects
#     - Python: venv/ in 12 projects
#
# [3] Archive inactive projects (8.5 GB, 12 projects)
#     - Not modified in 6+ months
#     - Move to ~/Archive/projects/
#
# Select cleanup actions [1-3, all, none]:
```

**Cleanup Strategies**:
- **Conservative**: Only build artifacts, safe to remove
- **Moderate**: Build artifacts + inactive project dependencies
- **Aggressive**: All cleanable items including active dependencies

**Safety Features**:
- Always dry-run first
- Require confirmation for dependency cleanup
- Create restore points for undo
- Never delete source code

**Acceptance Criteria**:
- Cleanup is safe and predictable
- Dependencies cleaned only with confirmation
- Restore functionality works correctly
- Different strategies behave as documented
- Tests verify cleanup without data loss

**Estimated Effort**: 6-8 hours

**Dependencies**: Issue #25

**Labels**: command, workspace, enhancement, feature, developer, cleanup

---

## Phase 3 Summary

**Total Estimated Effort**: 45-59 hours
**Total Issues**: 6 (Issues #21-26)

**Implementation Order**:
1. Issue #21 (archive basic) - New command foundation
2. Issue #22 (archive compress) - Extend archive
3. Issue #23 (watch basic) - Most complex command
4. Issue #24 (watch rules) - Extend watch
5. Issue #25 (workspace detect) - Developer-focused command
6. Issue #26 (workspace cleanup) - Extend workspace

**Deliverables**:
- 3 new advanced commands (archive, watch, workspace)
- Full watch daemon with rule engine
- Developer workspace management
- Comprehensive test coverage
- Complete documentation

**Risk Assessment**:
- **High Complexity**: Watch command requires file system APIs
- **Platform Differences**: File system monitoring varies by OS
- **Testing Challenges**: Daemon and long-running processes
- **Mitigation**: Incremental development, platform abstraction, comprehensive tests
