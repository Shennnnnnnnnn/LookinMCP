#!/usr/bin/env python3
"""Lookin stdio MCP adapter backed by the shared local HTTP client."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Callable

import mcp.server.stdio
from mcp.server import Server
from mcp.types import TextContent, Tool

from lookin_client import LookinClient, LookinClientError


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("lookin-mcp")
app = Server(
    "lookin-mcp-server",
    version="1.0.0",
    instructions=(
        "Use get_status when Lookin readiness is uncertain. For UI reproduction, "
        "prefer one capture_ui_context call so screenshot and hierarchy describe "
        "the same UI state. Use export_all_images for original UIImageView assets. "
        "Keep hierarchy queries bounded by element_id or "
        "max_depth. Reload only before final validation or capture. File-producing "
        "tools write only to the directory supplied by the user."
    ),
)
client = LookinClient()


def _schema(
    properties: dict[str, Any] | None = None, required: list[str] | None = None
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "type": "object",
        "properties": properties or {},
        "additionalProperties": False,
    }
    if required:
        result["required"] = required
    return result


@app.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="get_status",
            description=(
                "Preflight Lookin and report whether an inspected hierarchy is ready. "
                "Call first when UI state is uncertain or another Lookin tool fails."
            ),
            inputSchema=_schema(),
        ),
        Tool(
            name="get_ui_context",
            description=(
                "Get an AI-oriented UI snapshot with hierarchy, root IDs, counts, and "
                "focused details. Prefer this for UI reproduction or broad diagnosis."
            ),
            inputSchema=_schema(
                {
                    "max_depth": {
                        "type": "integer",
                        "default": 8,
                        "description": "Maximum depth. Use -1 only when necessary.",
                    },
                    "element_id": {
                        "type": "string",
                        "description": "Optional component root OID.",
                    },
                }
            ),
        ),
        Tool(
            name="get_hierarchy",
            description=(
                "Get class, text, frame, visibility, and child relationships. Scope "
                "by element_id or max_depth to control response size."
            ),
            inputSchema=_schema(
                {
                    "max_depth": {
                        "type": "integer",
                        "default": -1,
                        "description": "Maximum depth; -1 means unlimited.",
                    },
                    "filter_class": {
                        "type": "string",
                        "description": "Optional case-insensitive class filter.",
                    },
                    "element_id": {
                        "type": "string",
                        "description": "Optional subtree root OID.",
                    },
                }
            ),
        ),
        Tool(
            name="get_element_info",
            description=(
                "Inspect one element's frame, text, colors, fonts, borders, radius, "
                "hierarchy links, and effective constraints."
            ),
            inputSchema=_schema(
                {"element_id": {"type": "string", "description": "Element OID."}},
                ["element_id"],
            ),
        ),
        Tool(
            name="get_relative_position",
            description=(
                "Compare two root-coordinate axis-aligned frames and return stable "
                "relation, touching, minimum-distance, overlap-area, and coverage fields."
            ),
            inputSchema=_schema(
                {
                    "element_id_1": {"type": "string"},
                    "element_id_2": {"type": "string"},
                },
                ["element_id_1", "element_id_2"],
            ),
        ),
        Tool(
            name="search_elements",
            description="Find element OIDs by text, class, identifier, or size.",
            inputSchema=_schema(
                {
                    "query": {"type": "string"},
                    "search_type": {
                        "type": "string",
                        "enum": ["all", "class", "text", "identifier", "size"],
                        "default": "all",
                    },
                },
                ["query"],
            ),
        ),
        Tool(
            name="reload_view",
            description=(
                "Refresh from the inspected app. Call once before a final capture or "
                "after changing the target UI."
            ),
            inputSchema=_schema(),
        ),
        Tool(
            name="save_image",
            description="Save the image content owned by an image element.",
            inputSchema=_schema(
                {
                    "element_id": {"type": "string"},
                    "directory": {"type": "string", "default": "."},
                    "filename": {"type": "string"},
                },
                ["element_id"],
            ),
        ),
        Tool(
            name="export_all_images",
            description=(
                "Export image values from every UIImageView or subclass in the current "
                "hierarchy as PNG files; nil and failed items are returned as errors."
            ),
            inputSchema=_schema(
                {"directory": {"type": "string"}},
                ["directory"],
            ),
        ),
        Tool(
            name="export_screenshot",
            description=(
                "Save the rendered screenshot for an element and descendants. Use "
                "the returned absolute path as visual evidence."
            ),
            inputSchema=_schema(
                {
                    "element_id": {"type": "string"},
                    "directory": {"type": "string"},
                    "filename": {"type": "string"},
                },
                ["element_id", "directory"],
            ),
        ),
        Tool(
            name="capture_ui_context",
            description=(
                "Create a synchronized UI reproduction bundle after one refresh. "
                "Writes screenshot.png, context.json, element.json, and manifest.json."
            ),
            inputSchema=_schema(
                {
                    "directory": {"type": "string"},
                    "element_id": {
                        "type": "string",
                        "description": "Optional component root OID.",
                    },
                    "max_depth": {"type": "integer", "default": 8},
                    "refresh": {"type": "boolean", "default": True},
                },
                ["directory"],
            ),
        ),
    ]


@app.call_tool()
async def call_tool(name: str, arguments: Any) -> list[TextContent]:
    args = arguments or {}
    try:
        if name == "get_status":
            result = await _run(client.health)
        elif name == "get_ui_context":
            result = await _run(
                client.context,
                max_depth=args.get("max_depth", 8),
                element_id=args.get("element_id"),
            )
        elif name == "get_hierarchy":
            result = await _run(
                client.hierarchy,
                max_depth=args.get("max_depth", -1),
                filter_class=args.get("filter_class"),
                element_id=args.get("element_id"),
            )
        elif name == "get_element_info":
            result = await _run(client.element, args["element_id"])
        elif name == "get_relative_position":
            result = await _run(
                client.relative_position,
                args["element_id_1"],
                args["element_id_2"],
            )
        elif name == "search_elements":
            result = await _run(
                client.search, args["query"], args.get("search_type", "all")
            )
        elif name == "reload_view":
            result = await _run(client.reload)
        elif name == "save_image":
            directory = Path(args.get("directory", "."))
            filename = args.get("filename") or f"element_{args['element_id']}.png"
            path = await _run(
                client.save_image, args["element_id"], directory / filename
            )
            result = {"status": "success", "path": str(path)}
        elif name == "export_all_images":
            result = await _run(client.export_all_images, args["directory"])
        elif name == "export_screenshot":
            directory = Path(args["directory"])
            filename = args.get("filename") or f"screenshot_{args['element_id']}.png"
            path = await _run(
                client.save_screenshot, args["element_id"], directory / filename
            )
            result = {"status": "success", "path": str(path)}
        elif name == "capture_ui_context":
            result = await _run(
                client.capture,
                args["directory"],
                element_id=args.get("element_id"),
                max_depth=args.get("max_depth", 8),
                refresh=args.get("refresh", True),
            )
        else:
            result = {"status": "error", "message": f"Unknown tool: {name}"}
    except (KeyError, TypeError) as error:
        result = {
            "status": "error",
            "message": f"Invalid arguments for {name}: {error}",
        }
    except LookinClientError as error:
        result = error.as_dict()
    except Exception as error:
        logger.exception("Lookin tool failed: %s", name)
        result = {"status": "error", "message": str(error)}

    return [
        TextContent(
            type="text",
            text=json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True),
        )
    ]


async def _run(call: Callable[..., Any], *args: Any, **kwargs: Any) -> Any:
    return await asyncio.to_thread(call, *args, **kwargs)


async def main() -> None:
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        logger.info("Starting Lookin MCP stdio adapter for %s", client.server_url)
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options(),
        )


if __name__ == "__main__":
    asyncio.run(main())
