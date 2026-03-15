---
name: context7
description: Fetch up-to-date documentation for any library or framework using Context7. Use when you need to look up API docs, installation guides, usage examples, or configuration options for technologies like Node.js, Next.js, React, Rails, Oracle, shadcn/ui, or any other library.
---

# Context7 - Library Documentation Fetcher

## Purpose

Provide real-time access to official documentation for libraries, frameworks, and tools. Use whenever accurate, up-to-date information is needed about installation, API references, configuration, usage examples, or best practices.

## MCP Setup (One-time)

```bash
claude mcp add --header "CONTEXT7_API_KEY: <your-api-key>" --transport http context7 https://mcp.context7.com/mcp
```

Verify: `claude mcp list`

## How to Use

### Step 1: Resolve Library Name

```
mcp__context7__resolve-library-id({ "libraryName": "library-name" })
```

### Step 2: Fetch Documentation

```
mcp__context7__get-library-docs({
  "context7CompatibleLibraryID": "/library/id",
  "topic": "specific topic (optional)"
})
```

## Usage Tips

- **"use context7"**: Add to prompt for explicit invocation
- **Slash syntax**: Directly specify as /vercel/next.js, /rails/rails format
- **Version specification**: Include version number for specific version docs
- **topic parameter**: Filter docs by specific topic

## Popular Library IDs

| Library | libraryName | context7CompatibleLibraryID |
|---------|-------------|----------------------------|
| Next.js | nextjs | /vercel/next.js |
| React | react | /facebook/react |
| shadcn/ui | shadcn-ui | /shadcn-ui/ui |
| Tailwind CSS | tailwindcss | /tailwindlabs/tailwindcss |
| Rails | rails | /rails/rails |
| Node.js | nodejs | /nodejs/node |
| Supabase | supabase | /supabase/supabase |
| Anthropic SDK | anthropic | /anthropics/anthropic-sdk-python |
| Oracle | oracle | (resolve first) |

## Common Use Cases

### Installation Guide
```
1. Resolve: { "libraryName": "nodejs" }
2. Fetch: { "context7CompatibleLibraryID": "/nodejs/node", "topic": "installation linux" }
```

### API Reference
```
1. Resolve: { "libraryName": "nextjs" }
2. Fetch: { "context7CompatibleLibraryID": "/vercel/next.js", "topic": "app router" }
```

### Configuration
```
1. Resolve: { "libraryName": "tailwindcss" }
2. Fetch: { "context7CompatibleLibraryID": "/tailwindlabs/tailwindcss", "topic": "configuration" }
```

## Available MCP Tools

| Tool | Description |
|------|-------------|
| `mcp__context7__resolve-library-id` | Find library identifier by name |
| `mcp__context7__get-library-docs` | Fetch documentation for a library |

## Fallback

If not found in Context7, check `.claude/references/commondocs.md#library-name`.
