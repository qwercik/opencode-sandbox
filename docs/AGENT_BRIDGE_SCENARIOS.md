# Agent-bridge w scenariuszach wieloprojektowych

## Problem

Pracując nad jednym projektem, agent-bridge jest zdefiniowany w jego `compose.yml`.
Podczas pracy nad kilkoma projektami jednocześnie (np. `rowerek` + `auth`) bridge musi
mieć dostęp do kontenerów ze wszystkich tych projektów.

Nie chcemy modyfikować oryginalnych `compose.yml` poszczególnych projektów.

## Rozwiązanie: folder scenariusza

Dla każdej kombinacji projektów tworzymy osobny folder z symlinkami:

```
~/projects/razem/
├── rowerek  ->  ../rowerek     # symlink do projektu
├── auth     ->  ../auth        # symlink do projektu
├── compose.yml                  # definiuje tylko agent-bridge
├── .env.agent                   # konfiguracja bridge'a
└── .opencode/
    └── opencode.json            # MCP → host.docker.internal:4321
```

## Pliki

### compose.yml

```yaml
services:
  agent-bridge:
    image: ghcr.io/qwercik/opencode-sandbox-docker-bridge:latest
    ports: [4321:4321]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    env_file: .env.agent
```

### .env.agent

```
AGENT_BRIDGE_API_KEY=<taki-sam-klucz>
AGENT_BRIDGE_ALLOWED_CONTAINERS=rowerek,auth,www,database
AGENT_BRIDGE_PORT=4321
```

`AGENT_BRIDGE_ALLOWED_CONTAINERS` używa nazw serwisów (np. `rowerek`, `auth`),
a nie pełnych nazw kontenerów — bridge rozpoznaje je po labelce
`com.docker.compose.service`, co działa niezależnie od sufiksu (`.1`, `.2` itd.).

Jeśli dwa projekty mają serwisy o tej samej nazwie (np. oba mają `database`),
użyj pełnych nazw kontenerów, np. `rowerek-database-1,auth-database-1`.

### .opencode/opencode.json

```json
{
  "mcp": {
    "agent-bridge": {
      "type": "remote",
      "url": "http://host.docker.internal:4321/mcp",
      "headers": {
        "Authorization": "Bearer {env:AGENT_BRIDGE_API_KEY}"
      },
      "enabled": true
    }
  }
}
```

## Workflow

```bash
# 1. Odpal dev kontenery (osobne projekty, niezmienione)
cd ~/projects/rowerek && docker compose up -d
cd ~/projects/auth    && docker compose up -d

# 2. Odpal shared bridge (folder scenariusza)
cd ~/projects/razem && docker compose up -d

# 3. Uruchom sandbox z configem scenariusza
cd ~/projects/razem && opencode-sandbox
```

## Jak to działa

1. **Sandbox** (opencode CLI) startuje z `razem/` i czyta `razem/.opencode/opencode.json`
   → MCP łączy się z bridge'em przez `host.docker.internal:4321`
2. **'opencode-sandbox'** sam rozwiązuje symlinki w `razem/` i montuje je jako bind mounty
   → w sandboxie widać pliki `rowerek/` i `auth/`
3. **Bridge** ma Docker socketa → może `docker exec` do dowolnego kontenera na hoście,
   niezależnie od sieci Dockerowych
4. Zagnieżdżone `.opencode/` (np. `rowerek/.opencode/`) są ignorowane — opencode
   używa tylko tego z katalogu roboczego (`razem/.opencode/`)

## Uwagi

- Dev kontenery muszą być uruchomione **przed** sandboxem (lub równolegle)
- Wszystkie scenariusze mogą współdzielić ten sam `AGENT_BRIDGE_API_KEY`
  lub mieć własne — zależy od preferencji
- Każda kombinacja projektów = osobny folder z własnym zestawem symlinków