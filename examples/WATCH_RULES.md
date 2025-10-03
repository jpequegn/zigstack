# ZigStack Watch Rules Documentation

This document describes the advanced rule system for the `zigstack watch` command.

## Overview

The watch command can be configured with JSON-based rules that provide sophisticated file organization logic including:

- **Pattern Matching**: Glob patterns, path matching, extension matching
- **Conditional Logic**: Size filters, time-based conditions, file age
- **Chained Actions**: Multiple actions per rule
- **Priority Ordering**: Rules execute in priority order (0-100, higher first)
- **Rate Limiting**: Prevent rule overload

## Rule Structure

A rule file is a JSON document with the following structure:

```json
{
  "rules": [
    {
      "name": "Rule Name",
      "trigger": "file_created",
      "match": { /* matchers */ },
      "conditions": [ /* conditions */ ],
      "actions": [ /* actions */ ],
      "priority": 50
    }
  ]
}
```

### Rule Components

#### 1. Name (Required)
A descriptive name for the rule.

```json
"name": "Organize Work PDFs"
```

#### 2. Trigger (Required)
When the rule should be evaluated:

- `file_created` - When a new file is detected
- `file_modified` - When a file is modified
- `file_deleted` - When a file is deleted
- `periodic` - On periodic checks (not yet implemented)

```json
"trigger": "file_created"
```

#### 3. Match (Optional)
Pattern matchers for files:

```json
"match": {
  "pattern": "*.pdf",              // Glob pattern
  "path_contains": "work",         // Path must contain string
  "extension": ".pdf"              // Specific extension
}
```

**Glob Pattern Examples:**
- `*.pdf` - All PDF files
- `doc*.txt` - Files starting with "doc" and ending with ".txt"
- `file?.pdf` - Files like "file1.pdf", "fileA.pdf", etc.
- `*work*.doc` - Files containing "work" in the name

#### 4. Conditions (Optional)
Additional filters that must all be true:

```json
"conditions": [
  {
    "size_gt": "100KB"      // File size greater than
  },
  {
    "size_lt": "10MB"       // File size less than
  },
  {
    "time_of_day": "09:00-17:00"  // Current time within range
  },
  {
    "age_gt": 86400         // File age greater than (seconds)
  },
  {
    "age_lt": 604800        // File age less than (seconds)
  }
]
```

**Size Formats:**
- `100B` - Bytes
- `5KB` - Kilobytes
- `10MB` - Megabytes
- `1GB` - Gigabytes

**Age Formats:**
Age is specified in seconds:
- 1 hour = 3600
- 1 day = 86400
- 1 week = 604800
- 30 days = 2592000

#### 5. Actions (Required)
Actions to execute when rule matches:

```json
"actions": [
  {
    "organize": {
      "by_category": true,
      "by_date": false,
      "by_size": false
    }
  },
  {
    "move": {
      "destination": "~/Archive/work"
    }
  },
  {
    "archive": {
      "destination": "~/Archive",
      "compress": true
    }
  },
  {
    "log": {
      "message": "Custom log message"
    }
  }
]
```

#### 6. Priority (Optional, default: 50)
Priority for rule execution (0-100, higher priority runs first):

```json
"priority": 80
```

## Examples

### Example 1: Basic Organization

```json
{
  "rules": [
    {
      "name": "Organize PDFs",
      "trigger": "file_created",
      "match": {
        "extension": ".pdf"
      },
      "actions": [
        {
          "organize": {
            "by_category": true
          }
        }
      ],
      "priority": 80
    }
  ]
}
```

### Example 2: Conditional Organization

```json
{
  "rules": [
    {
      "name": "Organize Large Videos",
      "trigger": "file_created",
      "match": {
        "pattern": "*.{mp4,avi,mkv}"
      },
      "conditions": [
        {
          "size_gt": "100MB"
        }
      ],
      "actions": [
        {
          "organize": {
            "by_category": true
          }
        },
        {
          "log": {
            "message": "Large video organized"
          }
        }
      ],
      "priority": 90
    }
  ]
}
```

### Example 3: Work Hours Rule

```json
{
  "rules": [
    {
      "name": "Organize Work Documents During Business Hours",
      "trigger": "file_created",
      "match": {
        "pattern": "*.pdf",
        "path_contains": "work"
      },
      "conditions": [
        {
          "size_gt": "100KB"
        },
        {
          "time_of_day": "09:00-17:00"
        }
      ],
      "actions": [
        {
          "organize": {
            "by_category": true,
            "by_date": true
          }
        }
      ],
      "priority": 100
    }
  ]
}
```

## Usage

### Basic Usage

```bash
# Watch with rules file
zigstack watch --rules watch-rules.json ~/Downloads

# Validate rules before running
zigstack watch --validate-rules --rules watch-rules.json

# Watch with rules and verbose output
zigstack watch --rules watch-rules.json --verbose ~/Downloads
```

### Validation

The `--validate-rules` flag checks your rules file for:

- Empty rule names
- Invalid priority values (must be 0-100)
- Missing required actions
- Invalid size formats
- Invalid time formats

```bash
zigstack watch --validate-rules --rules my-rules.json
```

## Rule Execution Flow

1. **File Event**: A file is created, modified, or deleted
2. **Rule Filtering**: Rules matching the event trigger are selected
3. **Priority Sorting**: Rules are sorted by priority (highest first)
4. **Pattern Matching**: Each rule's matcher is evaluated
5. **Condition Evaluation**: All conditions must be true
6. **Action Execution**: Actions are executed in order
7. **Rate Limiting**: If configured, execution is throttled

## Best Practices

1. **Use Specific Matchers**: Be as specific as possible to avoid unintended matches
2. **Set Appropriate Priorities**: Critical rules should have higher priorities
3. **Test Rules First**: Use `--validate-rules` before deployment
4. **Start Simple**: Begin with basic rules and add complexity as needed
5. **Use Logging Actions**: Add log actions for debugging
6. **Consider Performance**: Avoid overly complex patterns on high-volume directories

## Limitations

Current limitations (may be addressed in future versions):

- No regex pattern support (only glob patterns)
- Periodic trigger not yet implemented
- Delete and archive actions queue but don't execute yet
- No rule reloading without restart
- Rate limiting not yet configurable via JSON

## Template Rules

See the example files in this directory:

- `watch-rules-basic.json` - Simple organization rules
- `watch-rules-advanced.json` - Complex conditional rules with time-based logic

## Troubleshooting

**Rules not matching:**
- Check the pattern syntax (glob, not regex)
- Verify file paths contain expected strings
- Enable `--verbose` to see rule matching details

**Validation errors:**
- Check JSON syntax is valid
- Verify all required fields are present
- Ensure size/time formats are correct

**Performance issues:**
- Reduce check interval with `--interval`
- Use more specific matchers to reduce evaluations
- Consider adding rate limits to frequently-matched rules
