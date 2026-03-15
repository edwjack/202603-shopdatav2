---
name: skill-creator
description: Comprehensive guide for creating effective skills for Claude. Use when Claude needs to create a new skill, update or improve an existing skill, package a skill for distribution, or understand skill development best practices. Helps with skill structure, frontmatter, bundled resources (scripts, references, assets), progressive disclosure patterns, and the complete skill creation workflow.
---

# Skill Creator

Guide for creating effective skills — modular packages that extend Claude's capabilities with specialized knowledge, workflows, and tools.

## Core Principles

### Concise is Key

Context window is shared. Only add context Claude doesn't already have. Prefer concise examples over verbose explanations.

### Degrees of Freedom

- **High freedom** (text instructions): Multiple valid approaches, context-dependent decisions
- **Medium freedom** (pseudocode/scripts with params): Preferred pattern exists, some variation OK
- **Low freedom** (specific scripts): Fragile operations, consistency critical, exact sequence required

### Skill Structure

```
skill-name/
├── SKILL.md              (required - frontmatter + instructions)
├── scripts/              (optional - executable code)
├── references/           (optional - docs loaded as needed)
└── assets/               (optional - files used in output)
```

**Storage location:** `~/.claude/skills/<skill-name>/`

### Naming Convention

Skill names use **kebab-case** consistently:

| Field | Format | Example |
|-------|--------|--------|
| Directory name | `kebab-case` | `sqlcl-no-native-binds/` |
| `name:` in frontmatter | `kebab-case` | `name: sqlcl-no-native-binds` |
| `id:` (if used) | `kebab-case` | `id: sqlcl-no-native-binds` |

**Rules:**
- Use lowercase letters, numbers, and hyphens only
- `name` and `id` must match (prefer `name` only, `id` is optional)
- Directory name should match `name`
- Human-readable titles go in the `# Heading`, not in frontmatter


### Bundled Resources

| Type | Purpose | When to Include |
|------|---------|-----------------|
| `scripts/` | Deterministic, reusable code (Python/Bash) | Same code rewritten repeatedly |
| `references/` | Documentation loaded into context as needed | Domain knowledge, schemas, API docs |
| `assets/` | Files used in output (templates, icons) | Output requires specific files |

Do NOT create: README.md, CHANGELOG.md, INSTALLATION_GUIDE.md, or other auxiliary files.

### Progressive Disclosure

1. **Metadata** (name + description) — always in context (~100 words)
2. **SKILL.md body** — loaded when skill triggers (<5k words, <500 lines)
3. **Bundled resources** — loaded as needed by Claude

Split content into reference files when approaching 500 lines. Always reference split files from SKILL.md with clear descriptions of when to read them.

## Skill Creation Process

### Step 1: Understand with Concrete Examples

Ask the user:
- What functionality should the skill support?
- Can you give examples of how it would be used?
- What triggers should activate this skill?

Skip only when usage patterns are already clearly understood.

### Step 2: Plan Reusable Contents

For each example, identify:
1. What scripts would avoid rewriting the same code?
2. What references would avoid rediscovering the same information?
3. What assets would avoid recreating the same boilerplate?

### Step 3: Initialize the Skill

Create the skill directory manually:

```bash
mkdir -p ~/.claude/skills/<skill-name>/{scripts,references,assets}
```

Then create `SKILL.md` with frontmatter template.

### Step 4: Edit the Skill

For design patterns and workflow guidance, see:
- [references/official-guide.md](references/official-guide.md) — comprehensive Anthropic official guide (patterns, troubleshooting, checklist)
- [references/workflows.md](references/workflows.md) — sequential workflows, conditional logic
- [references/output-patterns.md](references/output-patterns.md) — template and example patterns

**Frontmatter rules:**
- `name`: Skill name
- `description`: What it does + when to use it. This is the primary trigger mechanism.
- No other fields in frontmatter.
- Always write in English.

**Body rules:**
- Use imperative/infinitive form
- Keep under 500 lines
- Move detailed reference material to `references/` files

### Step 5: Package the Skill

Distribute as zip or copy the skill directory directly.

### Step 6: Iterate

Use the skill on real tasks → notice struggles → update SKILL.md or resources → test again.

## Fetch Latest Docs

Before implementing skills that use external libraries, fetch latest docs via Context7:

```
1. mcp__context7__resolve-library-id(libraryName)
2. mcp__context7__get-library-docs(libraryId, topic)
```

### Required Skill Sections for Context7

Every skill using external libraries MUST include:

**Front section (after Purpose):**
```markdown
## Fetch Latest Docs
Before using this skill, fetch latest docs via Context7:
- libraryName: "library-name"
- context7CompatibleLibraryID: "/owner/repo"
- topic: relevant topic (optional)
```

**End section:**
```markdown
## Fallback
If not found in Context7, check `.claude/references/commondocs.md#library-name`.
```

### Popular Library IDs

| Library | ID |
|---------|-----|
| Next.js | /vercel/next.js |
| React | /facebook/react |
| shadcn/ui | /shadcn-ui/ui |
| Tailwind CSS | /tailwindlabs/tailwindcss |
| Node.js | /nodejs/node |
| Anthropic SDK | /anthropics/anthropic-sdk-python |

### Context7 Verification

After creating a skill, test Context7 integration:
1. `resolve-library-id` finds the library
2. `query-docs` returns relevant docs/examples
3. On failure: add fallback to `commondocs.md`

## Environment Reference

- **Oracle ADB 26ai** via MCP (`oracle` server — SQLcl `-mcp` mode)
- **Wallet:** `/home/opc/Wallet_JK26aiAppCT.zip`
- **Skills location:** `~/.claude/skills/`

## Fallback

If not found in Context7, check `.claude/references/commondocs.md`.
