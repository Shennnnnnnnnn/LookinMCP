#!/usr/bin/env python3
"""Shared HTTP client for Lookin's local AI debugging API."""

from __future__ import annotations

import base64
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


DEFAULT_SERVER_URL = "http://127.0.0.1:10086"


class LookinClientError(RuntimeError):
    """An actionable error returned by Lookin or its local transport."""

    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        details: Any = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.details = details

    def as_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {"status": "error", "message": str(self)}
        if self.status_code is not None:
            result["status_code"] = self.status_code
        if self.details is not None:
            result["details"] = self.details
        return result


class LookinClient:
    def __init__(self, server_url: str | None = None, timeout: float = 15.0) -> None:
        configured_url = server_url or os.environ.get(
            "LOOKIN_SERVER_URL", DEFAULT_SERVER_URL
        )
        self.server_url = configured_url.rstrip("/")
        self.timeout = timeout

    def _request_json(
        self,
        path: str,
        *,
        query: Mapping[str, Any] | None = None,
        method: str = "GET",
        body: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        filtered_query = {
            key: str(value)
            for key, value in (query or {}).items()
            if value is not None
        }
        url = f"{self.server_url}{path}"
        if filtered_query:
            url = f"{url}?{urlencode(filtered_query)}"

        request_data = None
        headers: dict[str, str] = {}
        if body is not None:
            request_data = json.dumps(
                body, ensure_ascii=False, separators=(",", ":")
            ).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = Request(url, data=request_data, headers=headers, method=method)
        try:
            with urlopen(request, timeout=self.timeout) as response:
                raw = response.read()
                status_code = response.status
        except HTTPError as error:
            raw = error.read()
            details = _decode_json_or_text(raw)
            message = _error_message(details, f"Lookin returned HTTP {error.code}")
            raise LookinClientError(
                message, status_code=error.code, details=details
            ) from error
        except URLError as error:
            raise LookinClientError(
                f"Cannot reach Lookin at {self.server_url}. "
                "Open Lookin and enable AI Integration in Settings."
            ) from error

        payload = _decode_json_or_text(raw)
        if not isinstance(payload, dict):
            raise LookinClientError(
                "Lookin returned a non-object JSON response",
                status_code=status_code,
                details=payload,
            )
        if payload.get("status") == "error" or payload.get("error"):
            raise LookinClientError(
                _error_message(payload, "Lookin could not complete the request"),
                status_code=status_code,
                details=payload,
            )
        return payload

    def health(self) -> dict[str, Any]:
        return self._request_json("/health")

    def hierarchy(
        self,
        *,
        max_depth: int = -1,
        filter_class: str | None = None,
        element_id: str | None = None,
    ) -> dict[str, Any]:
        return self._request_json(
            "/api/hierarchy",
            query={
                "max_depth": max_depth,
                "filter_class": filter_class,
                "element_id": element_id,
            },
        )

    def element(self, element_id: str) -> dict[str, Any]:
        return self._request_json(f"/api/element/{element_id}")

    def relative_position(
        self, element_id_1: str, element_id_2: str
    ) -> dict[str, Any]:
        return self._request_json(
            "/api/relative_position",
            query={
                "element_id_1": element_id_1,
                "element_id_2": element_id_2,
            },
        )

    def reload(self) -> dict[str, Any]:
        return self._request_json("/api/reload", method="POST")

    def search(self, query: str, search_type: str = "all") -> dict[str, Any]:
        return self._request_json(
            "/api/search",
            query={"query": query, "search_type": search_type},
        )

    def context(
        self,
        *,
        max_depth: int = 8,
        element_id: str | None = None,
    ) -> dict[str, Any]:
        return self._request_json(
            "/api/context",
            query={"max_depth": max_depth, "element_id": element_id},
        )

    def save_image(self, element_id: str, output_path: str | Path) -> Path:
        payload = self._request_json(f"/api/element/{element_id}/image")
        return _write_base64_asset(payload, output_path)

    def save_screenshot(self, element_id: str, output_path: str | Path) -> Path:
        payload = self._request_json(f"/api/element/{element_id}/screenshot")
        return _write_base64_asset(payload, output_path)

    def export_all_images(self, directory: str | Path) -> dict[str, Any]:
        return self._request_json(
            "/api/images/export",
            method="POST",
            body={"directory": str(directory)},
        )

    def capture(
        self,
        output_directory: str | Path,
        *,
        element_id: str | None = None,
        max_depth: int = 8,
        refresh: bool = True,
        include_screenshot: bool = True,
    ) -> dict[str, Any]:
        output_dir = Path(output_directory).expanduser().resolve()
        output_dir.mkdir(parents=True, exist_ok=True)

        reload_result = self.reload() if refresh else None
        context = self.context(max_depth=max_depth, element_id=element_id)
        target_id = element_id or _first_root_id(context)

        context_path = output_dir / "context.json"
        _write_json(context_path, context)

        files: dict[str, str] = {"context": str(context_path)}
        if target_id:
            element_path = output_dir / "element.json"
            _write_json(element_path, self.element(target_id))
            files["element"] = str(element_path)

        if include_screenshot:
            if not target_id:
                raise LookinClientError(
                    "No root element is available for screenshot capture"
                )
            screenshot_path = self.save_screenshot(
                target_id, output_dir / "screenshot.png"
            )
            files["screenshot"] = str(screenshot_path)

        manifest = {
            "schema_version": 1,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "server_url": self.server_url,
            "target_element_id": target_id,
            "max_depth": max_depth,
            "refreshed": refresh,
            "reload": reload_result,
            "files": files,
        }
        manifest_path = output_dir / "manifest.json"
        _write_json(manifest_path, manifest)
        manifest["files"]["manifest"] = str(manifest_path)
        return manifest


def _decode_json_or_text(raw: bytes) -> Any:
    text = raw.decode("utf-8", errors="replace")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


def _error_message(payload: Any, fallback: str) -> str:
    if isinstance(payload, dict):
        for key in ("message", "error"):
            value = payload.get(key)
            if isinstance(value, str) and value:
                return value
    return fallback


def _write_base64_asset(payload: Mapping[str, Any], output_path: str | Path) -> Path:
    encoded = payload.get("data")
    if not isinstance(encoded, str) or not encoded:
        raise LookinClientError("Lookin response did not contain image data")
    try:
        data = base64.b64decode(encoded, validate=True)
    except ValueError as error:
        raise LookinClientError("Lookin returned invalid base64 image data") from error

    path = Path(output_path).expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


def _write_json(path: Path, payload: Mapping[str, Any]) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _first_root_id(context: Mapping[str, Any]) -> str | None:
    summary = context.get("summary")
    if isinstance(summary, dict):
        root_ids = summary.get("root_element_ids")
        if isinstance(root_ids, list) and root_ids:
            root_id = root_ids[0]
            if isinstance(root_id, str) and root_id:
                return root_id

    hierarchy = context.get("hierarchy")
    if isinstance(hierarchy, list) and hierarchy:
        first = hierarchy[0]
        if isinstance(first, dict):
            root_id = first.get("oid")
            if isinstance(root_id, str) and root_id:
                return root_id
    return None
