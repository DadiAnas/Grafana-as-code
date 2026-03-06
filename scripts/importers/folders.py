"""Import folders from Grafana."""

from __future__ import annotations

import sys
from datetime import datetime
from typing import Any

from .common import Colors, GrafanaClient, ImportContext, slugify, yaml_dump


def _fetch_all_folders(client: GrafanaClient) -> list[dict[str, Any]]:
    """Fetch ALL folders (including nested subfolders) for the current org.

    Grafana's /api/folders only returns top-level folders.
    We use /api/search?type=dash-folder to get all folders, then normalise
    the response so each entry has 'uid', 'title', and 'parentUid'.
    """
    search_resp = client.get("/api/search?type=dash-folder&limit=5000")
    if not search_resp:
        return []

    folders: list[dict[str, Any]] = []
    for item in search_resp:
        folders.append({
            "uid": item["uid"],
            "title": item["title"],
            "parentUid": item.get("folderUid", ""),
        })
    return folders


def import_folders(ctx: ImportContext) -> None:
    """Import folders from all organizations."""
    print(f"{Colors.BLUE}[3/8]{Colors.NC} Importing folders...")

    # Phase 1: Build global UID mapping and folder path map
    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        folders = _fetch_all_folders(ctx.client)
        if not folders and ctx.client.get("/api/folders?limit=1") is None:
            print(
                f"  {Colors.YELLOW}⚠{Colors.NC} API request failed for org id={org_id} — "
                "skipping folder UID mapping for this org (check auth/connectivity)",
                file=sys.stderr,
            )

        used_slugs: set[str] = set()
        top_level = [f for f in folders if not f.get("parentUid")]
        children = [f for f in folders if f.get("parentUid")]

        for folder in top_level + children:
            old_uid = folder["uid"]
            base_slug = slugify(folder["title"])
            slug = base_slug
            counter = 1
            while slug in used_slugs:
                counter += 1
                slug = f"{base_slug}-{counter}"
            used_slugs.add(slug)
            ctx.folder_uid_map[old_uid] = slug

        # Build parent lookup for this org: old_uid -> parentUid
        parent_lookup = {f["uid"]: f.get("parentUid", "") for f in folders}

        # Resolve full nested directory path for each folder
        def _resolve_path(uid: str) -> str:
            """Recursively build nested path: parent-slug/.../child-slug."""
            slug = ctx.folder_uid_map.get(uid, uid)
            parent_uid = parent_lookup.get(uid, "")
            if parent_uid:
                return f"{_resolve_path(parent_uid)}/{slug}"
            return slug

        for folder in folders:
            ctx.folder_path_map[folder["uid"]] = _resolve_path(folder["uid"])

    ctx.client.current_org_id = None

    # Phase 2: Generate folders.yaml
    all_folders: list[dict[str, Any]] = []
    total_folders = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        folders = _fetch_all_folders(ctx.client)
        if not folders:
            continue

        # Get teams and users for permission mapping
        teams_data = ctx.client.get("/api/teams/search?perpage=1000") or {}
        team_map = {t["id"]: t["name"] for t in teams_data.get("teams", [])}

        users_data = ctx.client.get("/api/org/users?perpage=1000") or []
        user_map = {u["userId"]: u["login"] for u in users_data}

        for folder in folders:
            old_uid = folder["uid"]
            new_uid = ctx.folder_uid_map.get(old_uid, old_uid)
            parent_old = folder.get("parentUid", "")
            parent_new = ctx.folder_uid_map.get(parent_old, parent_old) if parent_old else ""

            folder_entry: dict[str, Any] = {
                "title": folder["title"],
                "uid": new_uid,
                "_comment_original_uid": old_uid,
                "org": org_name,
                "orgId": org_id,
            }

            if parent_new:
                folder_entry["parent_uid"] = parent_new

            # Fetch permissions
            perms = ctx.client.get(f"/api/folders/{old_uid}/permissions") or []
            explicit_perms = [p for p in perms if not p.get("inherited", False) and p.get("permission", 0) > 0]

            perm_names = {1: "View", 2: "Edit", 4: "Admin"}
            permissions: list[dict[str, str]] = []

            for p in explicit_perms:
                perm_str = perm_names.get(p["permission"], str(p["permission"]))
                if p.get("teamId", 0) > 0:
                    team_name = team_map.get(p["teamId"], f"team-{p['teamId']}")
                    permissions.append({"team": team_name, "permission": perm_str})
                elif p.get("userId", 0) > 0:
                    user_login = user_map.get(p["userId"], f"user-{p['userId']}")
                    permissions.append({"user": user_login, "permission": perm_str})
                elif p.get("role", ""):
                    permissions.append({"role": p["role"], "permission": perm_str})

            folder_entry["permissions"] = permissions
            all_folders.append(folder_entry)
            total_folders += 1

            # Track terraform imports for folders
            if not ctx.skip_tf_import:
                dir_path = ctx.folder_path_map.get(old_uid, new_uid)
                tf_key = f"{org_name}/{dir_path}"
                is_subfolder = bool(parent_new)
                ctx.tf_imports.append((
                    f'module.folders.grafana_folder.{"subfolders" if is_subfolder else "folders"}["{tf_key}"]',
                    f"{org_id}:{old_uid}",
                ))
                ctx.tf_imports.append((
                    f'module.folders.grafana_folder_permission.permissions["{tf_key}"]',
                    f"{org_id}:{old_uid}",
                ))

    ctx.client.current_org_id = None

    # Phase 3: Create dashboard directories (nested for subfolders)
    dash_base = ctx.output_dir / "envs" / ctx.env_name / "dashboards"
    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        folders = _fetch_all_folders(ctx.client)
        for folder in folders:
            dir_path = ctx.folder_path_map.get(folder["uid"], ctx.folder_uid_map.get(folder["uid"], folder["uid"]))
            folder_path = dash_base / org_name / dir_path
            folder_path.mkdir(parents=True, exist_ok=True)
            gitkeep = folder_path / ".gitkeep"
            if not gitkeep.exists():
                gitkeep.touch()

    ctx.client.current_org_id = None

    # Write per-org folder files — always create dir+file for every org
    folders_by_org: dict[str, list[dict[str, Any]]] = {}
    for folder_entry in all_folders:
        org = folder_entry.get("org", "__no_org__")
        folders_by_org.setdefault(org, []).append(folder_entry)

    for org_id in ctx.org_ids:
        org_name = ctx.org_map[org_id]
        org_folders = folders_by_org.get(org_name, [])
        org_dir = ctx.config_dir / "folders" / org_name
        org_dir.mkdir(parents=True, exist_ok=True)
        output_file = org_dir / "folders.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n")
            f.write("# NOTE: Folder UIDs have been slugified from the original random Grafana UIDs\n")
            f.write("#       for better readability in both YAML config and directory structure.\n\n")
            f.write(yaml_dump({"folders": org_folders}))
        if org_folders:
            print(f"  {Colors.GREEN}✓{Colors.NC} {len(org_folders)} folder(s) → envs/{ctx.env_name}/folders/{org_name}/folders.yaml")
        else:
            print(f"  {Colors.DIM}  0 folders → envs/{ctx.env_name}/folders/{org_name}/folders.yaml (empty){Colors.NC}")

    print(f"  {Colors.GREEN}✓{Colors.NC} Created {total_folders} folder directories under envs/{ctx.env_name}/dashboards/")
    ctx.imported_count += 1
