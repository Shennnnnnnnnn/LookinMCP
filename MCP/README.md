# Lookin AI Integration

Lookin exposes the UI currently open in the macOS inspector to AI tools through three interfaces that share the same local data source:

- Streamable HTTP MCP for assistants and IDEs.
- A dependency-free `lookin` CLI for scripts and terminal agents.
- The repository skill at `.agents/skills/lookin-ui-debug` for repeatable debugging and UI reproduction.

Both local servers are disabled by default and bind only to `127.0.0.1`. Enable **AI Integration** in Lookin Settings before using any interface.

## Architecture

```text
Lookin hierarchy and screenshots
            |
            v
Local AI API (127.0.0.1:10086)
       |                 |
       v                 v
Native HTTP MCP      CLI / stdio MCP adapter
(configurable port)  (shared lookin_client.py)
```

The local API is the single capability layer. MCP and CLI do not implement independent hierarchy parsing, which keeps their output and errors consistent.

## CLI

The CLI requires Python 3.10 or newer and uses only the standard library:

```bash
./bin/lookin doctor
./bin/lookin search "Sign in" --type text
./bin/lookin inspect <element-id>
./bin/lookin relative <first-element-id> <second-element-id>
./bin/lookin hierarchy --element-id <element-id> --max-depth 3
```

For AI-assisted UI reproduction, create one synchronized capture:

```bash
./bin/lookin capture --output .lookin-capture
```

The capture refreshes once and writes:

```text
.lookin-capture/
|-- manifest.json
|-- context.json
|-- element.json
`-- screenshot.png
```

Use `--element-id <oid>` for a component-level capture, `--max-depth <n>` to bound hierarchy output, or `--no-reload` to preserve a transient UI state.

Set `LOOKIN_SERVER_URL` or pass `--server-url` when the API does not use its default address:

```bash
LOOKIN_SERVER_URL=http://127.0.0.1:10086 ./bin/lookin doctor
```

## MCP

The preferred MCP endpoint is the native Streamable HTTP server shown in Lookin Settings:

```bash
codex mcp add lookin --url http://127.0.0.1:47199/mcp
```

The MCP tools are optimized around two workflows:

- Focused debugging: `search_elements`, `get_element_info`, `get_relative_position`, and bounded `get_hierarchy` calls.
- UI reproduction: `get_ui_context` or `capture_ui_context`, followed by focused element inspection when needed.

`get_status` reports whether Lookin is reachable and whether an inspected hierarchy is ready. The previous `modify_element_attribute` placeholder is no longer advertised because it never performed a mutation.

### stdio compatibility

Clients that require stdio can use the Python adapter:

```bash
python3 -m pip install -r MCP/requirements.txt
python3 MCP/lookin_mcp_server.py
```

Example configuration:

```json
{
  "mcpServers": {
    "lookin": {
      "command": "python3",
      "args": ["/absolute/path/to/Lookin/MCP/lookin_mcp_server.py"],
      "env": {
        "LOOKIN_SERVER_URL": "http://127.0.0.1:10086"
      }
    }
  }
}
```

## Skill

Codex discovers the project skill automatically when launched inside this repository. Invoke it explicitly with:

```text
$lookin-ui-debug
```

The skill prefers connected Lookin MCP tools and falls back to `./bin/lookin`. It requires screenshot and hierarchy evidence from the same capture before making pixel-level UI claims.

## Local API

The shared client uses these endpoints:

| Endpoint | Purpose |
| --- | --- |
| `GET /health` | Service and inspected-hierarchy readiness |
| `GET /api/context` | Bounded hierarchy, root IDs, counts, and focused details |
| `GET /api/hierarchy` | Full or scoped view tree |
| `GET /api/element/:oid` | Detailed UI attributes and constraints |
| `GET /api/relative_position` | Absolute-frame relationship between two elements |
| `GET /api/search` | Text, class, identifier, or size search |
| `POST /api/reload` | Refresh from the inspected app |
| `GET /api/element/:oid/image` | Image content as base64 PNG |
| `GET /api/element/:oid/screenshot` | Rendered element subtree as base64 PNG |

Hierarchy and screenshot calls operate on Lookin's current inspection state. Reload before a final comparison, and avoid mixing artifacts captured before and after UI changes.
