# Timeline Health Check

A Docker container that checks the health of a Mastodon instance's timeline by verifying that recent posts exist. If the timeline is fresh (has posts within a specified threshold), it sends a heartbeat to a monitoring service.

## Purpose

This container is designed to run as a Kubernetes CronJob to monitor the health of a Mastodon instance. It:

1. Connects to the specified Mastodon instance
2. Fetches the latest post from the public timeline via `/api/v1/timelines/public`
3. Checks if the post is within the freshness threshold
4. If fresh, sends a GET request to a heartbeat URL (e.g., BetterStack, Healthchecks.io)

## Usage

### Command Line Arguments

```bash
python -m app.health_check \
  --hostname masto.nyc \
  --freshness 60 \
  --heartbeat-url https://uptime.betterstack.com/api/v1/heartbeat/xxx
```

### Environment Variables

All arguments can also be set via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `MASTODON_HOSTNAME` | The Mastodon instance hostname (e.g., masto.nyc) | Required |
| `FRESHNESS_THRESHOLD` | Maximum age in seconds for posts to be considered fresh | 60 |
| `HEARTBEAT_URL` | URL to GET when timeline is healthy | Required |

### Docker

```bash
# Build
docker build -t timeline-health .

# Run with environment variables
docker run \
  -e MASTODON_HOSTNAME=masto.nyc \
  -e FRESHNESS_THRESHOLD=60 \
  -e HEARTBEAT_URL=https://uptime.betterstack.com/api/v1/heartbeat/xxx \
  timeline-health

# Run with command line arguments
docker run timeline-health \
  --hostname masto.nyc \
  --freshness 60 \
  --heartbeat-url https://uptime.betterstack.com/api/v1/heartbeat/xxx
```

## Mastodon API

The tool uses the REST API endpoint `/api/v1/timelines/public?remote=false&only_media=false&limit=1` to fetch the latest post. This endpoint is publicly accessible (no authentication required) and returns an array of [Status](https://docs.joinmastodon.org/entities/Status/) objects with a `created_at` timestamp in ISO 8601 format.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Timeline is fresh, heartbeat sent successfully |
| 1 | Timeline is stale, or heartbeat failed |

### Deploying

```bash
# Apply the public configmap
kubectl apply -f kubernetes/cronjobs/configmap-timeline-health.yaml

# Apply the private configmap (edit private-configmap-timeline-health.yaml with your actual heartbeat URL first)
kubectl apply -f kubernetes/cronjobs/private-configmap-timeline-health.yaml

# Apply the cronjob
kubectl apply -f kubernetes/cronjobs/timeline-health-check.yaml
```
