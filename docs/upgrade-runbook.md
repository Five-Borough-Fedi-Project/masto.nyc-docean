# Mastodon upgrade runbook

Written after the v4.6.6 to v4.7.0 upgrade on 2026-08-31. Read it before you
start. The warning about SQL clients in step 6 and the warning about `VERSION=`
in step 8 both record failures from that night.

## Before the window

1. **Check the migration backlog.** Post-deployment migrations went unapplied
   from 2023-08 to 2026-08-31, and nobody noticed until an upgrade failed on
   one of them. `cronjob-migration-status.yaml` checks weekly now. Confirm it
   is green.

2. **Read the release notes for every version between yours and the target.**
   Note anything about long migrations or invalidated sessions.

3. **Count duplicate account URIs** if you are upgrading to 4.7.x:

   ```sql
   SELECT count(*) FROM (
     SELECT uri FROM accounts WHERE uri IS NOT NULL
     GROUP BY uri HAVING count(*) > 1
   ) d;
   ```

   A non-zero result sends `AddUniqueIndexOnAccountsUri` into a row-by-row
   merge across roughly 30 tables, and the upgrade takes hours instead of
   minutes.

4. **Check disk headroom.** Migrations duplicate indexes and rebuild
   materialized views before dropping the originals. Budget a few GiB, more if
   a `statuses` index is involved.

   ```sql
   SELECT pg_size_pretty(pg_database_size(current_database()));
   ```

5. **Let the nightly backup finish.** `postgres-backup` starts at 01:30 UTC and
   runs about an hour. Its `pg_dump` holds a snapshot open, which blocks
   autovacuum from reclaiming and slows WAL recycling. Both of those work
   against a migration. If your window is nowhere near 01:30, take a fresh
   backup instead:

   ```sh
   kubectl -n mastodon create job --from=cronjob/postgres-backup pre-upgrade-backup
   ```

6. **Close every SQL client.** A DBeaver connection left open killed a
   migration 17 minutes into it. DBeaver refreshes its metadata on a timer,
   which takes ACCESS SHARE on tables the migration needs ACCESS EXCLUSIVE on,
   and Postgres resolves the deadlock by cancelling the migration. Disconnect,
   do not merely close the query tab.

## The window

7. **Drain.** `./scale_for_upgrade.sh drain` scales every Mastodon deployment
   to zero, including the consolidated `mastodon-sidekiq-realtime` and
   `mastodon-sidekiq-bulk`.

8. **Migrate.** With the site down you can skip the pre/post split. Upstream
   recommends one pass with post-deployment migrations enabled when services
   are stopped. Apply a Job based on `k8s/migrate/job-migrate-pre.yaml`,
   replacing the command with:

   ```
   unset SKIP_POST_DEPLOYMENT_MIGRATIONS && exec bundle exec rails db:migrate
   ```

   Five things that cost time to learn:

   - **Never pass `VERSION=`.** Rails validates it against real migration
     versions. Pass a value below your current maximum applied version and
     Rails migrates *down*, reverting migrations you have already applied.
   - Migration Jobs must use the direct database port from `masto-direct-db`.
     Mastodon cannot run `db:migrate` through the pgbouncer pool, which runs in
     transaction mode.
   - `[strong_migrations] DANGER: No lock timeout set` is a warning, one per
     migration. Count them for a rough progress bar.
   - Rails wraps each migration in a transaction unless it declares
     `disable_ddl_transaction!`. A failure inside a transactional migration
     rolls back cleanly. A `CONCURRENTLY` index build that already completed
     does not.
   - Job names are immutable. Delete the Job before you re-apply it.

9. **Cut over.** Bump the image tags and apply. Your site runs the new version
   from this point:

   Bump the tag in the two `images:` stanzas, one per cluster, rather than
   editing every manifest:

   ```sh
   sed -i 's/newTag: v4.7.0/newTag: v4.7.1/' \
     k8s/clusters/do-production/kustomization.yaml \
     k8s/clusters/large/kustomization.yaml
   ```

   ```sh
   kubectl --context=do  apply -k k8s/clusters/do-production
   kubectl --context=lab apply -k k8s/clusters/large
   ```

   Check first with `kubectl --context=do diff -k k8s/clusters/do-production`,
   which answers whether the cluster matches the repo in one command.

10. **Fill.** Run `./scale_for_upgrade.sh fill`, then confirm the rollout and
    load the site.

## After

11. Un-suspend whatever you paused, such as `timeline-health-check`.
12. Re-run the migration status check.
13. Expect disk usage to settle above where it started. Autovacuum reclaims the
    dead tuples for reuse but does not return the space to the operating system.
14. Check node memory. `mastodon-web` grows to about 1.1 GiB over a few days of
    serving and pushes a node past 100%, at which point sidekiq pods get
    OOMKilled. Restart it by deleting the pod, never with
    `kubectl rollout restart`. See `docs/cluster-capacity.md`.

## What stays manual

Database migrations stay human-triggered. The v4.7.0 run hit a deadlock, and
the fix was to find the other lock holder, not to retry.
