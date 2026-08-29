#!/usr/bin/env python3
"""Command-line interface for Lookin's local AI debugging API."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Sequence

from lookin_client import DEFAULT_SERVER_URL, LookinClient, LookinClientError


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lookin",
        description="Inspect and capture the UI currently open in Lookin.",
    )
    parser.add_argument(
        "--server-url",
        help=f"Lookin API base URL (default: LOOKIN_SERVER_URL or {DEFAULT_SERVER_URL})",
    )
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument(
        "--compact", action="store_true", help="Emit compact JSON on stdout"
    )
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("doctor", help="Check Lookin and inspected-app readiness")

    hierarchy = commands.add_parser("hierarchy", help="Export the view hierarchy")
    _add_hierarchy_arguments(hierarchy, default_depth=-1)
    hierarchy.add_argument("--filter-class")

    context = commands.add_parser(
        "context", help="Export an AI-oriented hierarchy and screen summary"
    )
    _add_hierarchy_arguments(context, default_depth=8)

    inspect = commands.add_parser("inspect", help="Inspect one element")
    inspect.add_argument("element_id")

    search = commands.add_parser("search", help="Search elements")
    search.add_argument("query")
    search.add_argument(
        "--type",
        dest="search_type",
        choices=("all", "class", "text", "identifier", "size"),
        default="all",
    )

    relative = commands.add_parser("relative", help="Compare two element frames")
    relative.add_argument("element_id_1")
    relative.add_argument("element_id_2")

    commands.add_parser("reload", help="Refresh the inspected hierarchy")

    image = commands.add_parser("image", help="Save an element's image content")
    _add_asset_arguments(image)

    images = commands.add_parser(
        "images", help="Export image values from every UIImageView as PNG files"
    )
    images.add_argument("--output", type=Path, required=True)

    screenshot = commands.add_parser(
        "screenshot", help="Save an element and descendant screenshot"
    )
    _add_asset_arguments(screenshot)

    capture = commands.add_parser(
        "capture",
        help="Save a consistent screenshot, hierarchy, element details, and manifest",
    )
    capture.add_argument("--output", type=Path, required=True)
    capture.add_argument("--element-id")
    capture.add_argument("--max-depth", type=int, default=8)
    capture.add_argument("--no-reload", action="store_true")
    capture.add_argument("--no-screenshot", action="store_true")
    return parser


def _add_hierarchy_arguments(parser: argparse.ArgumentParser, default_depth: int) -> None:
    parser.add_argument("--max-depth", type=int, default=default_depth)
    parser.add_argument("--element-id")


def _add_asset_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("element_id")
    parser.add_argument("--output", type=Path, required=True)


def _emit(payload: Any, compact: bool = False, stream: Any = sys.stdout) -> None:
    indent = None if compact else 2
    separators = (",", ":") if compact else None
    print(
        json.dumps(
            payload,
            ensure_ascii=False,
            indent=indent,
            separators=separators,
            sort_keys=not compact,
        ),
        file=stream,
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    client = LookinClient(args.server_url, timeout=args.timeout)

    try:
        if args.command == "doctor":
            result = client.health()
        elif args.command == "hierarchy":
            result = client.hierarchy(
                max_depth=args.max_depth,
                filter_class=args.filter_class,
                element_id=args.element_id,
            )
        elif args.command == "context":
            result = client.context(
                max_depth=args.max_depth, element_id=args.element_id
            )
        elif args.command == "inspect":
            result = client.element(args.element_id)
        elif args.command == "search":
            result = client.search(args.query, args.search_type)
        elif args.command == "relative":
            result = client.relative_position(
                args.element_id_1, args.element_id_2
            )
        elif args.command == "reload":
            result = client.reload()
        elif args.command == "image":
            path = client.save_image(args.element_id, args.output)
            result = {"status": "success", "path": str(path)}
        elif args.command == "images":
            result = client.export_all_images(args.output.expanduser().resolve())
        elif args.command == "screenshot":
            path = client.save_screenshot(args.element_id, args.output)
            result = {"status": "success", "path": str(path)}
        elif args.command == "capture":
            result = client.capture(
                args.output,
                element_id=args.element_id,
                max_depth=args.max_depth,
                refresh=not args.no_reload,
                include_screenshot=not args.no_screenshot,
            )
        else:
            raise AssertionError(f"Unhandled command: {args.command}")
    except LookinClientError as error:
        _emit(error.as_dict(), compact=args.compact, stream=sys.stderr)
        return 2

    _emit(result, compact=args.compact)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
