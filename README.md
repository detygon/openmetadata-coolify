# OpenMetadata — Coolify Deployment

OpenMetadata 1.12.x deployed via Docker Compose on Coolify (git repo build mode).

## Architecture

```
openmetadata-mysql        — MySQL 8 metadata store (+ Airflow DB)
openmetadata-elasticsearch — Elasticsearch 7.16 search index
openmetadata-es-setup     — one-shot: creates vector_search_index
openmetadata-migrate      — one-shot: runs DB migrations
openmetadata-server       — OpenMetadata API + UI (:8585)
openmetadata-ingestion    — Airflow-based ingestion service (:8080)
```

All services communicate over Coolify's internal network (no exposed ports needed except `openmetadata-server`).

## Prerequisites

- Coolify instance with Docker Compose support
- Git repository accessible from Coolify (GitLab, GitHub, or self-hosted)
- At least **6 GB RAM** on the target server (Elasticsearch + OpenMetadata JVM are memory-heavy)

## Coolify Setup

### 1. Create a new resource

In Coolify → **Projects** → **New Resource** → **Docker Compose** → **Git Repository**.

| Field | Value |
|-------|-------|
| Repository | your repo URL |
| Branch | `main` (or `develop` for staging) |
| Compose file path | `openmetadata/docker-compose.yml` |
| Build pack | Docker Compose |

### 2. Configure environment variables

In the resource's **Environment Variables** tab, set the following. Mark sensitive values as **Secret**.

#### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `MYSQL_ROOT_PASSWORD` | MySQL root password | `change-me-root` |
| `MYSQL_USER` | App DB user | `openmetadata` |
| `MYSQL_PASSWORD` | App DB password | `change-me-app` |
| `AIRFLOW_PASSWORD` | Airflow admin password | `change-me-airflow` |
| `OPENMETADATA_SERVER_URL` | Public URL of the server | `https://openmetadata.example.com` |

#### Optional (with defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTHORIZER_ADMIN_PRINCIPALS` | `[admin]` | Comma-separated admin usernames |
| `AUTHENTICATION_PROVIDER` | `basic` | Auth provider (`basic`, `google`, `okta`, …) |
| `AIRFLOW_USERNAME` | `admin` | Airflow admin username |
| `OPENMETADATA_HEAP_OPTS` | `-Xmx2G -Xms2G` | OpenMetadata JVM heap |

### 3. Expose the server port

In Coolify → resource → **Ports** tab, map:

```
8585 → 8585   (OpenMetadata UI + API)
```

Do **not** expose ports `9200` (Elasticsearch) or `3306` (MySQL) publicly.

### 4. Deploy

Click **Deploy**. Coolify pulls the repo and runs `docker compose up`.

First-time startup order:
1. MySQL and Elasticsearch start and pass health checks (~30–60s)
2. `openmetadata-migrate` runs DB migrations and exits
3. `openmetadata-es-setup` creates the vector index and exits
4. `openmetadata-server` starts (~2 min for JVM warm-up)
5. `openmetadata-ingestion` (Airflow) starts (~3 min)

Total cold-start time: **~5–8 minutes**.

### 5. First login

Navigate to `https://<your-domain>`.

Default credentials:
- **Username:** `admin@open-metadata.org`
- **Password:** `admin`

Change the admin password immediately after first login.

## Redeploy / Updates

To update to a new OpenMetadata version:

1. Update the image tags in [docker-compose.yml](docker-compose.yml) (`openmetadata/server:X.Y.Z`, `openmetadata/ingestion:X.Y.Z`, `openmetadata/db:X.Y.Z`)
2. Push to the tracked branch
3. Trigger a redeploy in Coolify (or enable auto-deploy on push)

Coolify will run `docker compose up -d --pull always`, which:
- Pulls new images
- Restarts changed containers
- Leaves volumes intact

## GitLab CI Integration (optional)

To trigger a Coolify redeploy from the CI pipeline, add the webhook call to `.gitlab-ci.yml`:

```yaml
deploy-openmetadata:staging:
  stage: deploy
  image: curlimages/curl:latest
  script:
    - 'curl -s -f -X GET "${COOLIFY_WEBHOOK_OPENMETADATA}" -H "Authorization: Bearer ${COOLIFY_API_TOKEN}"'
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
      changes:
        - openmetadata/**/*
```

Required CI/CD variables:
- `COOLIFY_API_TOKEN` — Coolify API token (masked)
- `COOLIFY_WEBHOOK_OPENMETADATA` — Coolify deploy webhook URL for this resource (masked)

## Data Persistence

All state is in Docker named volumes:

| Volume | Contents |
|--------|----------|
| `openmetadata_mysql_data` | MySQL databases (metadata + Airflow) |
| `openmetadata_es_data` | Elasticsearch indices |
| `openmetadata_dag_configs` | Generated Airflow DAG configs |
| `openmetadata_dag_tmp` | Airflow tmp files |

Coolify preserves volumes across redeployments. To reset all state, delete the volumes manually on the host.

## Troubleshooting

**Server stuck at startup**

Check migration completed successfully:
```bash
docker logs openmetadata-migrate
```

**Elasticsearch red/unhealthy**

The host `vm.max_map_count` must be at least `262144`:
```bash
# On the Coolify host (as root)
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
```

**Ingestion / Airflow not connecting to server**

`openmetadata-ingestion` depends on `openmetadata-server` being healthy. On slow hosts the 3-minute `start_period` may not be enough. Check logs:
```bash
docker logs openmetadata-ingestion
```

**PIPELINE_SERVICE_CLIENT_VERIFY_SSL parse error**

Already handled in this compose file. If you see a Jackson enum error referencing `PIPELINE_SERVICE_CLIENT_VERIFY_SSL`, verify the env var is set to `no-ssl` (no quotes) in both `openmetadata-migrate` and `openmetadata-server`.
