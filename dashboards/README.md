# Dashboards Directory Structure

Place your Grafana dashboard JSON files here using this convention:

```
dashboards/
├── shared/                          # Deployed to ALL environments
│   └── <Organization Name>/         # Must match an org name from organizations.yaml
│       └── <folder-uid>/            # Creates a folder in Grafana with this UID
│           ├── dashboard1.json
│           └── subfolder/           # Creates a nested subfolder
│               └── dashboard2.json
│
└── <environment>/                   # Deployed ONLY to this specific environment
    └── <Organization Name>/
        └── <folder-uid>/
            └── dashboard.json
```

## Example

```
dashboards/
├── shared/
│   └── Main Organization/
│       └── infrastructure/
│           ├── node-exporter.json
│           └── kubernetes/
│               └── cluster.json
│
└── myenv/
    └── Main Organization/
        └── debug/
            └── debug-dashboard.json
```

## How it works

1. **Folders are auto-discovered** from the directory tree — no need to declare them anywhere.
2. **Permissions are optional** — define them in `config/shared/folders.yaml` if needed.
3. **Environment override** — dashboards in `<env>/` override shared ones (by filename).
4. **Export from Grafana** — use the Grafana UI to export dashboards as JSON and drop them here.
