# The Complete Guide to Building Skills for Claude

Official Anthropic guide for creating effective skills.

## What is a Skill?

A skill is a folder containing:
- **SKILL.md** (required): Instructions in Markdown with YAML frontmatter
- **scripts/** (optional): Executable code (Python, Bash, etc.)
- **references/** (optional): Documentation loaded as needed
- **assets/** (optional): Templates, fonts, icons used in output

## Core Design Principles

### Progressive Disclosure

Skills use a three-level system:

| Level | When Loaded | Contents |
|-------|-------------|----------|
| 1st (YAML frontmatter) | Always in system prompt | Enough info for Claude to know when to use |
| 2nd (SKILL.md body) | When skill is relevant | Full instructions and guidance |
| 3rd (Linked files) | As needed | Additional files Claude discovers on demand |

### Composability

Claude can load multiple skills simultaneously. Your skill should work well alongside others.

### Portability

Skills work identically across Claude.ai, Claude Code, and API.

## Technical Requirements

### File Structure

```
your-skill-name/
├── SKILL.md              # Required - main skill file
├── scripts/              # Optional - executable code
│   ├── process_data.py
│   └── validate.sh
├── references/           # Optional - documentation
│   ├── api-guide.md
│   └── examples/
└── assets/               # Optional - templates, etc.
    └── report-template.md
```

### Critical Rules

**SKILL.md naming:**
- Must be exactly `SKILL.md` (case-sensitive)
- No variations accepted (SKILL.MD, skill.md, etc.)

**Skill folder naming:**
- Use kebab-case: `notion-project-setup` ✓
- No spaces: `Notion Project Setup` ✗
- No underscores: `notion_project_setup` ✗
- No capitals: `NotionProjectSetup` ✗

**No README.md:**
- Don't include README.md inside your skill folder
- All documentation goes in SKILL.md or references/

### YAML Frontmatter

**Minimal required format:**
```yaml
---
name: your-skill-name
description: What it does. Use when user asks to [specific phrases].
---
```

**Field requirements:**

| Field | Required | Rules |
|-------|----------|-------|
| `name` | Yes | kebab-case only, no spaces/capitals, match folder name |
| `description` | Yes | MUST include what + when, under 1024 chars, no XML tags |
| `license` | No | MIT, Apache-2.0, etc. |
| `compatibility` | No | 1-500 chars, environment requirements |
| `metadata` | No | Custom key-value pairs (author, version, mcp-server) |

**Security restrictions:**
- No XML angle brackets (< >)
- Skills with "claude" or "anthropic" in name are reserved

## Writing Effective Descriptions

**Structure:** `[What it does] + [When to use it] + [Key capabilities]`

**Good examples:**
```yaml
# Specific and actionable
description: Analyzes Figma design files and generates developer handoff documentation. Use when user uploads .fig files, asks for "design specs", "component documentation", or "design-to-code handoff".

# Includes trigger phrases
description: Manages Linear project workflows including sprint planning, task creation, and status tracking. Use when user mentions "sprint", "Linear tasks", "project planning", or asks to "create tickets".

# Clear value proposition
description: End-to-end customer onboarding workflow for PayFlow. Handles account creation, payment setup, and subscription management. Use when user says "onboard new customer", "set up subscription", or "create PayFlow account".
```

**Bad examples:**
```yaml
# Too vague
description: Helps with projects.

# Missing triggers
description: Creates sophisticated multi-page documentation systems.

# Too technical, no user triggers
description: Implements the Project entity model with hierarchical relationships.
```

## Common Skill Use Case Categories

### Category 1: Document & Asset Creation

Creating consistent, high-quality output (documents, presentations, apps, designs, code).

**Key techniques:**
- Embedded style guides and brand standards
- Template structures for consistent output
- Quality checklists before finalizing
- No external tools required

### Category 2: Workflow Automation

Multi-step processes that benefit from consistent methodology.

**Key techniques:**
- Step-by-step workflow with validation gates
- Templates for common structures
- Built-in review and improvement suggestions
- Iterative refinement loops

### Category 3: MCP Enhancement

Workflow guidance to enhance MCP server tool access.

**Key techniques:**
- Coordinates multiple MCP calls in sequence
- Embeds domain expertise
- Provides context users would otherwise need to specify
- Error handling for common MCP issues

## Workflow Patterns

### Pattern 1: Sequential Workflow Orchestration

Use when: Multi-step processes in a specific order.

```markdown
## Workflow: Onboard New Customer

### Step 1: Create Account
Call MCP tool: `create_customer`
Parameters: name, email, company

### Step 2: Setup Payment
Call MCP tool: `setup_payment_method`
Wait for: payment method verification

### Step 3: Create Subscription
Call MCP tool: `create_subscription`
Parameters: plan_id, customer_id (from Step 1)

### Step 4: Send Welcome Email
Call MCP tool: `send_email`
Template: welcome_email_template
```

### Pattern 2: Multi-MCP Coordination

Use when: Workflows span multiple services.

```markdown
### Phase 1: Design Export (Figma MCP)
1. Export design assets from Figma
2. Generate design specifications
3. Create asset manifest

### Phase 2: Asset Storage (Drive MCP)
1. Create project folder in Drive
2. Upload all assets
3. Generate shareable links

### Phase 3: Task Creation (Linear MCP)
1. Create development tasks
2. Attach asset links to tasks
3. Assign to engineering team
```

### Pattern 3: Iterative Refinement

Use when: Output quality improves with iteration.

```markdown
### Initial Draft
1. Fetch data via MCP
2. Generate first draft report
3. Save to temporary file

### Quality Check
1. Run validation script: `scripts/check_report.py`
2. Identify issues

### Refinement Loop
1. Address each identified issue
2. Regenerate affected sections
3. Re-validate
4. Repeat until quality threshold met
```

### Pattern 4: Context-aware Tool Selection

Use when: Same outcome, different tools depending on context.

```markdown
### Decision Tree
1. Check file type and size
2. Determine best storage location:
   - Large files (>10MB): Use cloud storage MCP
   - Collaborative docs: Use Notion/Docs MCP
   - Code files: Use GitHub MCP
   - Temporary files: Use local storage
```

### Pattern 5: Domain-specific Intelligence

Use when: Adding specialized knowledge beyond tool access.

```markdown
### Before Processing (Compliance Check)
1. Fetch transaction details via MCP
2. Apply compliance rules:
   - Check sanctions lists
   - Verify jurisdiction allowances
   - Assess risk level
3. Document compliance decision

### Processing
IF compliance passed:
  - Call payment processing MCP tool
ELSE:
  - Flag for review
  - Create compliance case
```

## Best Practices for Instructions

**Be Specific and Actionable:**
```markdown
# Good
Run `python scripts/validate.py --input {filename}` to check data format.
If validation fails, common issues include:
- Missing required fields (add them to the CSV)
- Invalid date formats (use YYYY-MM-DD)

# Bad
Validate the data before proceeding.
```

**Include error handling:**
```markdown
## Common Issues

### MCP Connection Failed
If you see "Connection refused":
1. Verify MCP server is running
2. Confirm API key is valid
3. Try reconnecting
```

**Reference bundled resources clearly:**
```markdown
Before writing queries, consult `references/api-patterns.md` for:
- Rate limiting guidance
- Pagination patterns
- Error codes and handling
```

## Testing Approach

### 1. Triggering Tests

```
Should trigger:
- "Help me set up a new ProjectHub workspace"
- "I need to create a project in ProjectHub"
- "Initialize a ProjectHub project for Q4 planning"

Should NOT trigger:
- "What's the weather in San Francisco?"
- "Help me write Python code"
```

### 2. Functional Tests

```
Test: Create project with 5 tasks
Given: Project name "Q4 Planning", 5 task descriptions
When: Skill executes workflow
Then:
  - Project created in ProjectHub
  - 5 tasks created with correct properties
  - All tasks linked to project
  - No API errors
```

### 3. Performance Comparison

```
Without skill:
- 15 back-and-forth messages
- 3 failed API calls requiring retry
- 12,000 tokens consumed

With skill:
- 2 clarifying questions only
- 0 failed API calls
- 6,000 tokens consumed
```

## Troubleshooting

### Skill won't upload

| Error | Cause | Solution |
|-------|-------|----------|
| "Could not find SKILL.md" | File not named exactly SKILL.md | Rename to SKILL.md (case-sensitive) |
| "Invalid frontmatter" | YAML formatting issue | Check `---` delimiters, quote closure |
| "Invalid skill name" | Name has spaces or capitals | Use kebab-case |

### Skill doesn't trigger

- Description too generic ("Helps with projects" won't work)
- Missing trigger phrases users would actually say
- Missing relevant file types

**Debug:** Ask Claude "When would you use the [skill name] skill?"

### Skill triggers too often

1. Add negative triggers: `Do NOT use for simple data exploration`
2. Be more specific: `Processes PDF legal documents for contract review`
3. Clarify scope: `Use specifically for online payment workflows`

### Instructions not followed

1. Instructions too verbose → Use bullet points, numbered lists
2. Instructions buried → Put critical instructions at top
3. Ambiguous language → Use explicit validation criteria:
   ```markdown
   CRITICAL: Before calling create_project, verify:
   - Project name is non-empty
   - At least one team member assigned
   - Start date is not in the past
   ```

## Quick Checklist

### Before you start
- [ ] Identified 2-3 concrete use cases
- [ ] Tools identified (built-in or MCP)
- [ ] Planned folder structure

### During development
- [ ] Folder named in kebab-case
- [ ] SKILL.md file exists (exact spelling)
- [ ] YAML frontmatter has `---` delimiters
- [ ] `name` field: kebab-case, no spaces, no capitals
- [ ] `description` includes WHAT and WHEN
- [ ] No XML tags (< >) anywhere
- [ ] Instructions are clear and actionable
- [ ] Error handling included
- [ ] Examples provided
- [ ] References clearly linked

### Before upload
- [ ] Tested triggering on obvious tasks
- [ ] Tested triggering on paraphrased requests
- [ ] Verified doesn't trigger on unrelated topics
- [ ] Functional tests pass
- [ ] Tool integration works (if applicable)

### After upload
- [ ] Test in real conversations
- [ ] Monitor for under/over-triggering
- [ ] Iterate on description and instructions

## Resources

- [Best Practices Guide](https://docs.anthropic.com/skills/best-practices)
- [Skills Documentation](https://docs.anthropic.com/skills)
- [API Reference](https://docs.anthropic.com/api)
- [MCP Documentation](https://modelcontextprotocol.io)
- [Example Skills Repository](https://github.com/anthropics/skills)
