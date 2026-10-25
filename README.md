# agentic-engineering-course-sandbox

Навчальний пісочний проєкт для курсу з agentic engineering: тут відпрацьовуємо роботу з Claude Code та Anthropic API.

## Що всередині

- `module1/` — робота з токенами та вартістю запитів до Claude:
  - `count_tokens.sh` — підрахунок токенів через `/v1/messages/count_tokens` (різні формати вводу та параметри).
  - `count_tokens_simple.sh` — мінімальна версія того ж скрипта.
  - `calculate_cost.py` — підрахунок токенів і вартості 1000 запитів для Sonnet 4.6.
- `.devcontainer/`, `docker-compose.yml` — ізольований sandbox для Claude Code з firewall (`init-firewall.sh`).
- `CLAUDE.md` — правила роботи агента в цьому репозиторії.

## Вимоги

- змінна середовища `ANTHROPIC_API_KEY` (можна покласти в `.env`, який не комітиться);
- для `calculate_cost.py`: Python 3 і `pip install -r requirements.txt`;
- для sandbox: Docker (або VS Code з Dev Containers).

## Швидкий старт

```bash
export ANTHROPIC_API_KEY=...
./module1/count_tokens_simple.sh "Hello, Claude"
python3 module1/calculate_cost.py --help

# Sandbox без IDE
docker compose run --rm claude
```
