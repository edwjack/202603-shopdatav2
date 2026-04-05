# shopdatav2 - Project Instructions

## Project Info

| Item | Value |
|------|-------|
| Project | 202603-shopdatav2 |
| Created | 2026-03-15 |
| Based On | 202602-shopdata (architecture migrated to Scrapling) |
| Database | Oracle ADB 26ai (dedicated schema) |
| App Port | 3210 (Rails serves frontend+backend) |
| Scraper Port | 3211 (Python FastAPI + Scrapling) |
| Port Block | 19 (3210-3219) |
| Oracle Schema | PROJ3SHDV2 |
| Oracle Connection | 202603-shopdatav2 |
| GitHub Remote | https://github.com/edwjack/202603-shopdatav2.git |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Rails 8.0 (Turbo + Stimulus) |
| Frontend | Turbo + Stimulus + Tailwind CSS |
| Database (primary) | Oracle ADB 26ai via oracle_enhanced adapter |
| Database (queue/cache/cable) | SQLite sidecar (Solid Queue/Cache/Cable) |
| Background Jobs | Solid Queue |
| Caching | Solid Cache |
| Real-time | Solid Cable |
| AI/LLM | Claude API (claude-opus-4-6) |
| Scraping | Python microservice (Scrapling - stealth scraping framework) |
| Testing | Rails Test + Brakeman |

## Commands
```bash
bin/dev              # Start all (Rails + Tailwind + Jobs + Scraper)
bin/rails server     # Rails server only (port 3210)
bundle exec brakeman # Security scan
```

## Database
- Schema: `PROJ3SHDV2` | Connection: `202603-shopdatav2`
- Use PROJ3SHDV2 schema only. Confirm DDL/DML. Double-confirm DROP/TRUNCATE.


## Environment Variables

| Variable | Description |
|----------|-------------|
| ORACLE_PASSWORD | Oracle PROJ3SHDV2 schema password |
| MOCK_EXTERNAL_APIS | Set to 'true' for development (default) |
| ANTHROPIC_API_KEY | Claude API key for AI analysis |
| SHOPIFY_SHOP_DOMAIN | Shopify store domain |
| SHOPIFY_ACCESS_TOKEN | Shopify Admin API token |

