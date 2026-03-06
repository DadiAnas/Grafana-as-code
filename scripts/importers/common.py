"""Shared helpers used by every importer module."""

from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


# =============================================================================
# ANSI Colors
# =============================================================================
class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    NC = "\033[0m"  # No Color


# =============================================================================
# YAML Helpers
# =============================================================================
class QuotedDumper(yaml.SafeDumper):
    """YAML dumper that doesn't use anchors/aliases and quotes string values."""

    def ignore_aliases(self, data: Any) -> bool:
        return True

    def represent_mapping(self, tag: str, mapping: Any, flow_style: bool | None = None) -> yaml.MappingNode:
        """Override to avoid quoting keys."""
        value: list[tuple[yaml.Node, yaml.Node]] = []
        node = yaml.MappingNode(tag, value, flow_style=flow_style)
        if self.alias_key is not None:
            self.represented_objects[self.alias_key] = node
        best_style = True
        if hasattr(mapping, "items"):
            mapping = list(mapping.items())
        for item_key, item_value in mapping:
            # For keys, use plain representation (no quotes)
            if isinstance(item_key, str):
                node_key = self.represent_scalar("tag:yaml.org,2002:str", item_key)
            else:
                node_key = self.represent_data(item_key)
            node_value = self.represent_data(item_value)
            if not (isinstance(node_key, yaml.ScalarNode) and not node_key.style):
                best_style = False
            if not (isinstance(node_value, yaml.ScalarNode) and not node_value.style):
                best_style = False
            value.append((node_key, node_value))
        if flow_style is None:
            if self.default_flow_style is not None:
                node.flow_style = self.default_flow_style
            else:
                node.flow_style = best_style
        return node


def _sanitize_string(data: str) -> str:
    """Sanitize a string by removing/replacing problematic characters."""
    result = []
    for char in data:
        if char in ('\n', '\t'):
            result.append(char)
        elif unicodedata.category(char)[0] == 'C':  # Control characters
            result.append(' ')  # Replace with space
        else:
            result.append(char)
    # Strip leading/trailing whitespace and collapse multiple spaces
    return ' '.join(''.join(result).split())


def _quoted_str_representer(dumper: yaml.Dumper, data: str) -> yaml.ScalarNode:
    """Represent all string values with double quotes for consistency."""
    clean_data = _sanitize_string(data)
    return dumper.represent_scalar("tag:yaml.org,2002:str", clean_data, style='"')


QuotedDumper.add_representer(str, _quoted_str_representer)


def yaml_dump(data: Any, **kwargs: Any) -> str:
    """Dump data to YAML without aliases, with proper string quoting."""
    return yaml.dump(data, Dumper=QuotedDumper, default_flow_style=False, sort_keys=False, **kwargs)


# =============================================================================
# Data Classes
# =============================================================================
@dataclass
class GrafanaClient:
    """Grafana API client."""

    url: str
    auth: str
    current_org_id: int | None = None
    timeout: int = 15

    def _get_auth(self) -> tuple[str, str] | dict[str, str]:
        """Return auth tuple or headers dict."""
        if ":" in self.auth:
            user, password = self.auth.split(":", 1)
            return (user, password)
        return {}

    def _get_headers(self) -> dict[str, str]:
        """Return request headers."""
        headers: dict[str, str] = {}
        if ":" not in self.auth:
            headers["Authorization"] = f"Bearer {self.auth}"
        if self.current_org_id:
            headers["X-Grafana-Org-Id"] = str(self.current_org_id)
        return headers

    def get(self, endpoint: str) -> Any:
        """Make a GET request to the Grafana API."""
        import requests

        url = f"{self.url}{endpoint}"
        auth = self._get_auth() if isinstance(self._get_auth(), tuple) else None
        headers = self._get_headers()

        try:
            resp = requests.get(url, auth=auth, headers=headers, timeout=self.timeout)
            resp.raise_for_status()
            return resp.json()
        except requests.RequestException:
            return None

    def health(self) -> dict[str, Any] | None:
        """Check Grafana health."""
        return self.get("/api/health")


@dataclass
class ImportContext:
    """Context for the import operation."""

    env_name: str
    grafana_url: str
    client: GrafanaClient
    output_dir: Path
    config_dir: Path
    import_dashboards: bool = True
    skip_tf_import: bool = False
    vault_mount: str = "grafana"
    vault_namespace: str = ""

    # Mappings built during import
    org_map: dict[int, str] = field(default_factory=dict)  # org_id -> org_name
    org_ids: list[int] = field(default_factory=list)
    folder_uid_map: dict[str, str] = field(default_factory=dict)  # old_uid -> slug_uid
    folder_path_map: dict[str, str] = field(default_factory=dict)  # old_uid -> nested dir path

    imported_count: int = 0

    # Terraform import commands: list of (resource_address, import_id)
    tf_imports: list[tuple[str, str]] = field(default_factory=list)

    def vault_path(self, *parts: str) -> str:
        """Build a full Vault path: [namespace/]mount/parts..."""
        segments = []
        if self.vault_namespace:
            segments.append(self.vault_namespace)
        segments.append(self.vault_mount)
        segments.extend(parts)
        return "/".join(segments)


# =============================================================================
# Utility Functions
# =============================================================================
def slugify(title: str) -> str:
    """Convert a title to a clean, filesystem-safe slug."""
    s = title.lower().strip()
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"[\s_]+", "-", s)
    s = re.sub(r"-+", "-", s)
    s = s.strip("-")
    return s or "folder"


def parse_json_str(val: str, join_char: str = " ") -> str:
    """Parse a value that may be a JSON array string or a plain string."""
    if isinstance(val, str) and val.startswith("["):
        try:
            items = json.loads(val)
            if isinstance(items, list):
                return join_char.join(str(i) for i in items)
        except (json.JSONDecodeError, TypeError):
            pass
    return val


def safe_filename(title: str) -> str:
    """Make a string safe for use as a filename."""
    return re.sub(r"[\/\\]", "-", title)
