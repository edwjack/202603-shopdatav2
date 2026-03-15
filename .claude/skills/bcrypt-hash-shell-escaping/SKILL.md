---
id: bcrypt-hash-shell-escaping
name: bcrypt-hash-shell-escaping
description: Bash shells mangle bcrypt hashes containing $ and ! characters — use Python or hex escapes to write clean JSON/SQL
source: session-2026-02-02-tripapproval-seed-data
triggers:
  - "bcrypt"
  - "password hash"
  - "Bad escaped character in JSON"
  - "shell escaping"
  - "seed data"
  - "Admin123!"
quality: high
---

# Bcrypt Hashes Corrupted by Shell Escaping

## The Insight

Bcrypt hashes contain `$` characters (e.g., `$2a$10$...`) which bash interprets as variable expansion. Passwords containing `!` get mangled by bash history expansion even inside single quotes in some shell configurations. When writing seed data or testing APIs with curl, these characters silently corrupt the data, causing authentication failures that are extremely hard to debug.

## Why This Matters

- `$2a$10$xxx` becomes empty string or partial value (bash variable expansion)
- `Admin123!` becomes `Admin123\!` (bash history expansion adds backslash)
- JSON payload with `\!` causes `Bad escaped character in JSON at position N` server errors
- `printf` and `echo` both mangle `!` in different ways
- The bcrypt hash in the database won't match, so `bcrypt.compare()` returns false silently

## Recognition Pattern

- "Bad escaped character in JSON" errors from API
- `bcrypt.compare()` returns false for known-correct passwords
- Seed data with bcrypt hashes inserted via shell commands
- API testing with curl where password contains `!` or `$`

## The Approach

1. **For seed SQL files**: Generate the bcrypt hash with Node.js (`bcrypt.hash()`), then verify it (`bcrypt.compare()`) in the same script before copying to SQL
2. **For curl API testing**: Never use bash for JSON with `!` or `$`. Use Python `requests` library instead, or write JSON to file using `python3 -c` with hex escapes
3. **For writing files with `!`**: Use `python3 -c` with `\x21` hex escape instead of literal `!`

## Example

```bash
# BROKEN: bash mangles ! even in single quotes
curl -d '{"password":"Admin123!"}' ...
# Result: "Bad escaped character in JSON"

# BROKEN: printf adds backslash
printf '{"password":"Admin123!"}' > /tmp/req.json
# Result: {"password":"Admin123\!"}

# WORKS: Python hex escape bypasses shell entirely
python3 -c "
with open('/tmp/req.json','w') as f:
    f.write('{\"email\":\"admin@oracle.com\",\"password\":\"Admin123\x21\"}')
"
curl -d @/tmp/req.json ...

# WORKS: Python requests library (best for API testing)
python3 -c "
import requests
r = requests.post('http://localhost:3091/api/auth/login',
    json={'email':'admin@oracle.com','password':'Admin123!'})
print(r.json())
"
```
