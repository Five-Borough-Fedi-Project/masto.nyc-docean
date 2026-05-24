/**
 * Mastodon load test — compare DO (small) vs homelab (large) origins.
 *
 * Usage:
 *   Against DO origin:
 *     k6 run -e TARGET=https://small.masto.nyc mastodon-loadtest.js
 *
 *   Against homelab origin:
 *     k6 run -e TARGET=https://large.masto.nyc mastodon-loadtest.js
 *
 *   With an API token (enables authenticated endpoints):
 *     k6 run -e TARGET=https://large.masto.nyc -e API_TOKEN=your_token mastodon-loadtest.js
 *
 *   Save results to JSON for comparison:
 *     k6 run --out json=results-large.json -e TARGET=https://large.masto.nyc mastodon-loadtest.js
 */

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const TARGET = __ENV.TARGET || "https://large.masto.nyc";
const API_TOKEN = __ENV.API_TOKEN || "";

const errorRate = new Rate("errors");
const dbHeavyDuration = new Trend("db_heavy_duration", true); // timeline + search endpoints

export const options = {
  // Staged ramp: warmup → steady low → steady medium → spike → cooldown
  stages: [
    { duration: "2m", target: 5 },   // warmup
    { duration: "5m", target: 10 },  // steady low
    { duration: "5m", target: 25 },  // steady medium
    { duration: "3m", target: 50 },  // spike
    { duration: "2m", target: 0 },   // cooldown
  ],
  thresholds: {
    http_req_failed: ["rate<0.01"],           // <1% errors
    http_req_duration: ["p(95)<3000"],        // p95 under 3s
    db_heavy_duration: ["p(95)<4000"],        // DB-heavy paths under 4s
  },
};

// Shared headers — override Host so cloudflared ingress matches masto.nyc
// regardless of which named origin (small/large) we're hitting.
const baseHeaders = {
  Host: "masto.nyc",
  "User-Agent": "k6-mastodon-loadtest/1.0",
  Accept: "application/json",
};

const authHeaders = API_TOKEN
  ? { ...baseHeaders, Authorization: `Bearer ${API_TOKEN}` }
  : baseHeaders;

function get(path, headers, tag) {
  return http.get(`${TARGET}${path}`, {
    headers: headers || baseHeaders,
    tags: { endpoint: tag || path },
  });
}

export default function () {
  const roll = Math.random();

  if (roll < 0.20) {
    // --- Public timeline (DB-heavy, most important for latency comparison) ---
    const res = get("/api/v1/timelines/public?limit=20", baseHeaders, "public_timeline");
    const ok = check(res, {
      "public timeline 200": (r) => r.status === 200,
      "public timeline has posts": (r) => {
        try { return JSON.parse(r.body).length > 0; } catch { return false; }
      },
    });
    errorRate.add(!ok);
    dbHeavyDuration.add(res.timings.duration);

  } else if (roll < 0.35) {
    // --- Instance info (lightweight, good baseline) ---
    const res = get("/api/v2/instance", baseHeaders, "instance");
    const ok = check(res, { "instance 200": (r) => r.status === 200 });
    errorRate.add(!ok);

  } else if (roll < 0.50) {
    // --- About/explore page (nginx-cached static-ish) ---
    const res = get("/explore", { ...baseHeaders, Accept: "text/html" }, "explore");
    const ok = check(res, { "explore 200": (r) => r.status === 200 });
    errorRate.add(!ok);

  } else if (roll < 0.60) {
    // --- Public timeline local only ---
    const res = get("/api/v1/timelines/public?local=true&limit=20", baseHeaders, "local_timeline");
    const ok = check(res, { "local timeline 200": (r) => r.status === 200 });
    errorRate.add(!ok);
    dbHeavyDuration.add(res.timings.duration);

  } else if (roll < 0.70) {
    // --- Search (hits OpenSearch — cross-cloud latency will show here) ---
    const res = get("/api/v2/search?q=mastodon&type=statuses&limit=10", baseHeaders, "search");
    const ok = check(res, { "search 200 or 401": (r) => r.status === 200 || r.status === 401 });
    errorRate.add(!ok);
    dbHeavyDuration.add(res.timings.duration);

  } else if (roll < 0.80) {
    // --- Directory (DB read, paginated) ---
    const res = get("/api/v1/directory?limit=20&order=active", baseHeaders, "directory");
    const ok = check(res, { "directory 200": (r) => r.status === 200 });
    errorRate.add(!ok);
    dbHeavyDuration.add(res.timings.duration);

  } else if (roll < 0.90 && API_TOKEN) {
    // --- Home timeline (authenticated, Redis + DB) ---
    const res = get("/api/v1/timelines/home?limit=20", authHeaders, "home_timeline");
    const ok = check(res, { "home timeline 200": (r) => r.status === 200 });
    errorRate.add(!ok);
    dbHeavyDuration.add(res.timings.duration);

  } else {
    // --- Health check (should always be fast and 200) ---
    const res = get("/health", baseHeaders, "health");
    const ok = check(res, { "health 200": (r) => r.status === 200 });
    errorRate.add(!ok);
  }

  sleep(Math.random() * 2 + 0.5); // 0.5–2.5s think time
}

export function handleSummary(data) {
  const target = TARGET.replace(/https?:\/\//, "").replace(/\./g, "-");
  return {
    [`results-${target}.json`]: JSON.stringify(data, null, 2),
    stdout: textSummary(data),
  };
}

function textSummary(data) {
  const m = data.metrics;
  // k6 uses "med" for p50, not "p(50)"
  const pct = (metric, key) => {
    const v = m[metric] && m[metric].values && m[metric].values[key];
    return v != null ? v.toFixed(0) + "ms" : "n/a";
  };
  const p50 = (metric) => pct(metric, "med");
  const p95 = (metric) => pct(metric, "p(95)");
  const p99 = (metric) => pct(metric, "p(99)");
  const rps = m.http_reqs && m.http_reqs.values ? m.http_reqs.values.rate.toFixed(1) : "n/a";
  const errRate = m.errors && m.errors.values ? (m.errors.values.rate * 100).toFixed(2) + "%" : "n/a";

  return `
Target: ${TARGET}
─────────────────────────────────────
All requests
  p50:  ${p50("http_req_duration")}
  p95:  ${p95("http_req_duration")}
  p99:  ${p99("http_req_duration")}
  rps:  ${rps}

DB-heavy endpoints (timeline/search/directory)
  p50:  ${p50("db_heavy_duration")}
  p95:  ${p95("db_heavy_duration")}
  p99:  ${p99("db_heavy_duration")}

Error rate: ${errRate}
─────────────────────────────────────
`;
}
