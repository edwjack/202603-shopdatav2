# shopdatav2 - Project Instructions

## Project Info

| Item | Value |
|------|-------|
| Project | 202603-shopdatav2 |
| Created | 2026-03-15 |
| Based On | 202602-shopdata (architecture migrated to Scrapling) |
| Database | Oracle ADB 26ai (dedicated schema) |
| App Port | 3190 (Rails serves frontend+backend) |
| Scraper Port | 3191 (Python FastAPI + Scrapling) |
| Port Block | 19 (3190-3199) |
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

## Directory Structure

```
app/
  models/          # ActiveRecord models (Oracle primary)
  controllers/     # Rails controllers
  views/           # ERB templates with Turbo + Stimulus
  jobs/            # Solid Queue background jobs
  services/        # Business logic (Claude API, Shopify, etc.)
  javascript/
    controllers/   # Stimulus controllers
config/
  database.yml     # Oracle primary + SQLite sidecar
  solid_queue.yml  # Queue worker config
  recurring.yml    # Job schedules
  oracle_wallet/   # Oracle ADB wallet (gitignored)
db/
  migrate/         # Oracle table migrations
  queue_migrate/   # Solid Queue SQLite migrations
  cache_migrate/   # Solid Cache SQLite migrations
  cable_migrate/   # Solid Cable SQLite migrations
  seeds.rb         # Initial data
scraper/           # Python scraping microservice
  main.py          # FastAPI on port 3191
  parsers/         # HTML parsing modules (Scrapling-based)
docs/              # PRD, screenshots, decisions
scripts/           # Dev scripts
```

## Commands

```bash
bin/dev              # Start all (Rails + Tailwind + Jobs + Scraper)
bin/rails server     # Rails server only (port 3190)
bin/rails console    # Rails console
bin/rails db:migrate # Run Oracle migrations
bin/rails db:seed    # Load seed data
bundle exec brakeman # Security scan
```

## Database Rules

- DDL/DML 실행 전 반드시 사용자 확인을 받는다
- DROP, TRUNCATE 등 파괴적 작업은 이중 확인한다
- Use the project's dedicated Oracle schema only (PROJ3SHDV2)

## MCP Database Access

DB 작업은 항상 MCP `oracle` 서버의 도구를 사용한다. Wallet zip 파일은 extract 불필요.

### 연결 방법

```
1. mcp__oracle__connect(connection_name="202603-shopdatav2")
2. 연결 실패 시 → mcp__oracle__run-sqlcl(sqlcl="connect -name 202603-shopdatav2")
3. 그래도 실패 시 → MCP oracle 서버 재시작 필요 (사용자에게 안내)
```

### 사용 가능한 도구

| Tool | Purpose |
|------|---------|
| `list-connections` | 저장된 연결 목록 확인 |
| `connect` | 연결 접속 (connection: `202603-shopdatav2`) |
| `run-sql` | SQL 실행 (SELECT, DML) |
| `run-sqlcl` | SQLcl 명령 실행 (connect, DDL 등) |
| `schema-information` | 현재 스키마 메타데이터 조회 |

### 연결 문제 해결

MCP Oracle 서버는 세션이 끊어질 수 있다 (ORA-17008: Closed connection):
1. `connect` 도구로 재연결 시도
2. 실패 시 `run-sqlcl`로 `connect -name 202603-shopdatav2` 실행
3. 그래도 실패하면 사용자에게 MCP 서버 재시작 요청

### Rules

- DDL/DML 실행 전 반드시 사용자 확인을 받는다
- DROP, TRUNCATE 등 파괴적 작업은 이중 확인한다

## Environment Variables

| Variable | Description |
|----------|-------------|
| ORACLE_PASSWORD | Oracle PROJ3SHDV2 schema password |
| MOCK_EXTERNAL_APIS | Set to 'true' for development (default) |
| ANTHROPIC_API_KEY | Claude API key for AI analysis |
| SHOPIFY_SHOP_DOMAIN | Shopify store domain |
| SHOPIFY_ACCESS_TOKEN | Shopify Admin API token |

## Port Allocation

This project uses port block 19:
- App (Rails): 3190
- Scraper (Python FastAPI + Scrapling): 3191
- WebSocket/Cable: 3192
- Range: 3190-3199
