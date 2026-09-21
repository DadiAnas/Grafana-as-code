# PostgreSQL (Crunchy / PGO) — High Availability & Backup

> **Scope.** This page describes the high-availability and backup/restore design of our PostgreSQL service running on Red Hat OpenShift, provisioned and operated by the **Crunchy Postgres Operator (PGO v5)**.
> **Audience.** SRE / DBA / on-call engineers.
> **Status:** _TODO (Draft / Reviewed)_ · **Owner:** _TODO_ · **Last updated:** _TODO_

---

## 1. Overview

The database is deployed as a Crunchy `PostgresCluster` custom resource. PGO continuously reconciles the desired state: it runs the PostgreSQL instances, manages streaming replication and automatic failover (via Patroni), and drives all backup, WAL archiving and restore operations through **pgBackRest**.

The design follows the **3-2-1 backup principle**: backups are kept on two different media (an in-cluster volume and off-site object storage), with one copy off-site, and both repositories retain WAL so we can perform point-in-time recovery (PITR).

- **Cluster name:** `<cluster-name>`
- **Namespace:** `<namespace>` (e.g. `postgres-prod`)
- **OpenShift project / environment:** _TODO_
- **PGO version:** _TODO_ · **PostgreSQL major version:** _TODO_

> _Diagrams to embed on this page:_ HA & Backup topology, Monitoring pipeline, Restore/PITR flow.

---

## 2. High Availability

### 2.1 Topology

The cluster runs **three PostgreSQL instances**: one **primary** (read/write) and **two replicas** (read-only, hot standby). Each instance is a separate Pod with its own `pgdata` PVC, so a single node or volume failure never takes more than one instance offline.

| Role | Pod | Access | Storage |
|------|-----|--------|---------|
| Primary | `<cluster>-instance-1` | read / write | dedicated PVC |
| Replica 1 | `<cluster>-instance-2` | read-only | dedicated PVC |
| Replica 2 | `<cluster>-instance-3` | read-only | dedicated PVC |

### 2.2 Replication

The primary streams Write-Ahead Log (WAL) to both replicas using PostgreSQL **streaming replication**. By default replication is **asynchronous** (low write latency; a very small window of in-flight transactions could be lost on a hard primary failure).

- Replication mode: **_TODO: async (default) or synchronous_**
- TLS for replication is provisioned automatically by PGO (handled by the `replication-cert-copy` container in each instance Pod).

### 2.3 Automatic failover

HA is managed by **Patroni**, embedded in the PostgreSQL (`database`) container of each instance Pod. Patroni monitors instance health and the leader lease. If the primary becomes unavailable:

1. Patroni detects the lost leader lease.
2. A healthy replica is **promoted** to primary.
3. PGO/Patroni repoint the cluster **Services** so the primary endpoint follows the new leader.
4. The former primary (when it returns) rejoins as a replica.

Applications connect through the cluster **Service** (the primary/`-primary` service for writes, the replica service for reads), so failover does **not** require an application config change.

### 2.4 Instance Pod internals

Each instance Pod contains the following containers (as seen in the OpenShift console):

- **Init containers:** `postgres-startup`, `nss-wrapper-init`
- **Containers:** `database` (PostgreSQL + Patroni), `pgbackrest` and `pgbackrest-config` (backup sidecar), `replication-cert-copy` (replication TLS), `exporter` (`crunchy-postgres-exporter`, metrics — see the Monitoring page)

---

## 3. Backup

### 3.1 pgBackRest with a dedicated repo host

Backups are handled by **pgBackRest**. A **dedicated repo host Pod** (`<cluster>-repo-host-0`) owns the repositories; the `pgbackrest` sidecar in each instance Pod ships WAL and backup data to it. A dedicated repo host is required because we use a volume-backed repository (repo1).

### 3.2 Repositories (3-2-1)

| Repo | Type | Location | Purpose |
|------|------|----------|---------|
| **repo1** | Volume (PVC / host volume) | In-cluster | Fast, low-RTO local restore for routine recovery |
| **repo2** | S3-compatible | **IBM Cloud Object Storage (COS)** | Off-site copy; survives full cluster / datacenter loss; long-term retention; DR rebuild |

Both repositories receive base backups **and** archived WAL, which is what enables PITR from either source.

### 3.3 WAL archiving

The primary continuously archives WAL segments to pgBackRest (`archive_command`). Archived WAL is the basis for both crash recovery on the replicas and for replaying transactions during a point-in-time restore.

### 3.4 Backup types & schedule

pgBackRest supports three backup types, scheduled by PGO as CronJobs:

- **Full** — a complete copy of the cluster.
- **Differential** — changes since the last full.
- **Incremental** — changes since the last backup of any type.

| Repo | Full | Differential | Incremental | Retention |
|------|------|--------------|-------------|-----------|
| repo1 (host) | _TODO e.g. weekly_ | _TODO e.g. daily_ | _TODO_ | _TODO e.g. 7–14 days_ |
| repo2 (COS) | _TODO_ | _TODO_ | _TODO_ | _TODO e.g. 30+ days_ |

> Schedules and retention are defined under `spec.backups.pgbackrest.repos[*].schedules` and the pgBackRest `retention-*` options in the `PostgresCluster` manifest. Keep this table in sync with the manifest.

---

## 4. Restore & Point-in-Time Recovery (PITR)

### 4.1 Recovery targets

pgBackRest restores to a chosen target via the `--type` option:

- **default** — replay all available WAL (latest).
- **time** — PITR to a timestamp: `--target="YYYY-MM-DD HH:MM:SS"`.
- **immediate** — stop as soon as the backup is consistent.
- **set** — restore a specific backup label (`--set=...`).
- **lsn / xid / name** — stop at a specific LSN, transaction id, or named restore point.

Select the source repository with `--repo=1` (host) or `--repo=2` (COS).

### 4.2 Two restore patterns

**A — In-place restore (destructive).** Restores **the existing cluster** by setting `spec.backups.pgbackrest.restore` and applying the restore annotation. Use only when intentionally rolling the live cluster back.

**B — Restore into a new cluster (non-destructive) — preferred.** Provision a **fresh** `PostgresCluster` that bootstraps from a repository using `spec.dataSource.pgbackrest`. This is the safe default for PITR and DR: the original cluster is untouched and you cut over only after validation.

> **Standard:** _TODO — confirm team policy. Recommended: pattern B for production; pattern A is "break-glass" only._

### 4.3 High-level restore steps

1. Choose the **source repo** (repo1 for speed, repo2/COS for full DR) and the **recovery target**.
2. Trigger the restore (pattern A or B) — PGO launches a pgBackRest restore **Job**.
3. pgBackRest rebuilds the `pgdata` volume: delta restore of base backup (full → diff → incr), then fetches the WAL needed to reach the target.
4. PostgreSQL replays WAL to the target and is **promoted** to the new primary.
5. Replicas are re-provisioned from the new primary; Services repoint; applications reconnect.
6. **Verify:** `SELECT now();`, replication lag, row counts / checksums against expectations.

---

## 5. RPO / RTO

| Metric | Target | Notes |
|--------|--------|-------|
| **RPO** (data loss window) | _TODO_ | Async replication + continuous WAL archiving. Effectively bounded by WAL archive frequency. |
| **RTO (local, repo1)** | _TODO_ | Fast on-cluster restore. |
| **RTO (DR, repo2/COS)** | _TODO_ | Full rebuild from off-site; larger due to object-storage transfer. |
| **Failover time (HA)** | _TODO (seconds)_ | Automatic Patroni promotion; no app reconfiguration. |

---

## 6. Monitoring & Alerting

Database health is collected by the `crunchy-postgres-exporter` sidecar, scraped by Grafana Alloy, stored in Grafana Mimir, visualised in Grafana, and alerted on via Grafana unified alerting → Microsoft Teams (`#Alerting` for prod/preprod, `#Alerting-np` for int/dev).

> See the dedicated **Monitoring & Alerting** page for details: _TODO link_.

---

## 7. Operational quick reference

> Replace `<cluster>` / `<namespace>` accordingly. Validate against our actual manifests before running.

**Check cluster / instance health**
```
oc -n <namespace> get postgrescluster <cluster>
oc -n <namespace> get pods -l postgres-operator.crunchy.io/cluster=<cluster>
```

**Check backups**
```
oc -n <namespace> exec -it <cluster>-repo-host-0 -- pgbackrest info
```

**Trigger a manual (one-off) backup** — annotate the cluster (PGO runs a backup Job):
```
oc -n <namespace> annotate postgrescluster <cluster> \
  postgres-operator.crunchy.io/pgbackrest-backup="$(date)" --overwrite
```

**PITR (pattern A, in-place)** — set `spec.backups.pgbackrest.restore` (repoName + options such as `--type=time --target=...`), then:
```
oc -n <namespace> annotate postgrescluster <cluster> \
  postgres-operator.crunchy.io/pgbackrest-restore="$(date)" --overwrite
```

> The exact spec blocks for backups, schedules, repo2/COS credentials and restore live in our GitOps repo: _TODO link to manifests_.

---

## 8. References

- Crunchy Postgres Operator (PGO) documentation — _TODO link_
- pgBackRest documentation — _TODO link_
- Our `PostgresCluster` manifests (GitOps) — _TODO link_
- Diagrams (source) — _TODO link / attachments_
