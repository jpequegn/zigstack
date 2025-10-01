# ZigStack Roadmap - Subcommand System

## Architecture Overview

### Current State
- Single-command CLI: `zigstack [OPTIONS] <directory>`
- All functionality in `src/main.zig` (~2500 lines)
- Flag-based feature selection (--by-date, --by-size, etc.)

### Target State
- Multi-command CLI: `zigstack <COMMAND> [OPTIONS] <directory>`
- Modular architecture with separate command handlers
- Shared core functionality (file analysis, categorization, etc.)

### Proposed Structure
```
src/
├── main.zig              # Entry point, command routing
├── core/
│   ├── file_info.zig     # FileInfo, FileCategory
│   ├── organization.zig  # OrganizationPlan, categorization logic
│   ├── config.zig        # Config, ConfigData parsing
│   └── tracker.zig       # MoveTracker, rollback support
└── commands/
    ├── organize.zig      # Current functionality (default)
    ├── analyze.zig       # Disk usage + content analysis
    ├── dedupe.zig        # Enhanced duplicate management
    ├── archive.zig       # Age-based archiving
    ├── watch.zig         # Daemon mode
    └── workspace.zig     # Developer workspace cleanup
```

## Command Specifications

### 1. `zigstack organize` (Default - Current Functionality)
**Purpose**: Organize files by extension, date, size, or duplicates
**Aliases**: Can be called implicitly without "organize" keyword
**Options**: All current flags maintained

### 2. `zigstack analyze`
**Purpose**: Deep content analysis and reporting
**Features**:
- Disk usage analysis with visualization
- Content-based analysis (image dimensions, video duration, etc.)
- Duplicate detection with detailed reports
- Export to JSON/CSV for further analysis

### 3. `zigstack dedupe`
**Purpose**: Advanced duplicate file management
**Features**:
- Interactive duplicate resolution
- Similarity detection (fuzzy matching)
- Preview before deletion
- Hardlink creation for space savings

### 4. `zigstack archive`
**Purpose**: Age-based file archiving
**Features**:
- Archive files older than N days/months
- Compression options (tar.gz, zip)
- Preserve directory structure or flatten
- Incremental archiving

### 5. `zigstack watch`
**Purpose**: Daemon mode for automatic organization
**Features**:
- Monitor directory for changes
- Auto-organize new files based on rules
- Background process with logging
- Rule-based actions (move, archive, delete)

### 6. `zigstack workspace`
**Purpose**: Developer workspace management
**Features**:
- Detect project types (Node.js, Python, Rust, Zig)
- Clean build artifacts and caches
- Archive inactive projects
- Analyze disk usage by project type

## Implementation Phases

### Phase 1: Foundation (Issues #10-#14)
- Refactor core functionality into modules
- Create command infrastructure
- Implement basic subcommand routing
- Maintain backward compatibility

### Phase 2: Core Commands (Issues #15-#20)
- Implement `organize` command (existing functionality)
- Implement `analyze` command
- Implement `dedupe` command
- Add comprehensive tests

### Phase 3: Advanced Commands (Issues #21-#26)
- Implement `archive` command
- Implement `watch` command
- Implement `workspace` command
- Add integration tests

### Phase 4: Polish (Issues #27-#30)
- Performance optimization
- Documentation updates
- CI/CD improvements
- Release preparation

## Design Decisions

### 1. Backward Compatibility
- `zigstack /path` should still work (implies `organize`)
- All existing flags must continue working
- Migration guide for users

### 2. Shared Code
- Core functionality (file analysis, categorization) shared across commands
- Common options (--verbose, --dry-run) available to all commands
- Consistent error handling and output formatting

### 3. Configuration
- Extend JSON config to support command-specific settings
- Default behaviors per command
- Profile support (e.g., "work", "personal")

### 4. Testing Strategy
- Unit tests for each command module
- Integration tests for command interactions
- Regression tests for backward compatibility
- Performance benchmarks

## Success Metrics
- [ ] All existing tests pass
- [ ] New commands have >80% test coverage
- [ ] Documentation complete for all commands
- [ ] Performance within 10% of current implementation
- [ ] Zero breaking changes for existing users
