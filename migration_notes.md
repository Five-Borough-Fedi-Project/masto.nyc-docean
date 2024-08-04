## Persistent Data

### Postgres

Moving from on-prem postgres to DOcean means that some shortcuts I took early on in the deployment will need to be addressed, as well as some major upgrades steps (v15 -> v16). 

After running [pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html) on the original brick and mortar Crunchy DB, and then [pg_restore](https://www.postgresql.org/docs/current/app-pgrestore.html) on the new one, some issues came about. These were the commands I was attempting to get to work.

On the source DB: 

`pg_dump -Fc -h 10.43.224.197 -U postgres mastodon_production > /media/seano/md0/System/8_2_pgdump.sql`

On the destination DB:

`PGOPTIONS="-c statement_timeout=0" pg_restore -h our-db.d.db.ondigitalocean.com -p 25060 -U doadmin -d mastodon_production -c --if-exists  --no-owner --role=mastodon /media/seano/md0/System/8_2_pgdump.sql`

#### DOcean User Permissions

It seems that [nothing we have access to gets superuser](https://docs.digitalocean.com/products/databases/postgresql/how-to/manage-users-and-databases/). That means I'll have to face my prior self's lazy sins of "give everything admin" and actually practice meaningful RBAC.

#### Public Schema permissions

When trying to `pg_restore`, I got a ton of these types of errors:

```sql
pg_restore: error: could not execute query: ERROR:  permission denied for schema public
Command was: CREATE SEQUENCE public.custom_filter_keywords_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
```

It appears that I'll need to fix some [public schema permissions](https://stackoverflow.com/questions/67276391/why-am-i-getting-a-permission-denied-error-for-schema-public-on-pgadmin-4). I performed the steps in that post:

```sql
GRANT ALL ON SCHEMA public TO mastodon;
ALTER DATABASE mastodon_production OWNER TO mastodon;
```

And it seemed to get rid of those errors.


#### Missing Extensions / other errors

I got some errors for missing extensions references too. I remember installing `pgaudit`, but not `aiiven`. I don't believe either of them are required for mastodon to run.

```sql
pg_restore: error: could not execute query: ERROR:  required extension "aiven_extras" is not installed
HINT:  Use CREATE EXTENSION ... CASCADE to install required extensions too.
Command was: CREATE EXTENSION IF NOT EXISTS pgaudit WITH SCHEMA public;


pg_restore: error: could not execute query: ERROR:  extension "pgaudit" does not exist
Command was: COMMENT ON EXTENSION pgaudit IS 'provides auditing functionality';
```

Once the restore finished, the only additional errors that were provided were:

```sql
pg_restore: error: could not execute query: ERROR:  role "_crunchypgbouncer" does not exist
Command was: GRANT USAGE ON SCHEMA pgbouncer TO _crunchypgbouncer;


pg_restore: error: could not execute query: ERROR:  role "_crunchypgbouncer" does not exist
Command was: REVOKE ALL ON FUNCTION pgbouncer.get_auth(username text) FROM PUBLIC;
GRANT ALL ON FUNCTION pgbouncer.get_auth(username text) TO _crunchypgbouncer;
```

Which is to be expected - we are moving to a non-crunchydb cluster.


#### Resource Sizing

So with our original B&M setup, there was a large pool of hardware resources to tap into- we weren't going to hit that ceiling anytime soon. BUT, cloud compute is expensive. As of the migration date, our PG DB was using:

- 40gb Storage
- 3gb RAM

All in all, for the Crunchy DB cluster, it was looking something like this:

```sh
❯ k -n mastodon top pod
NAME                                           CPU(cores)   MEMORY(bytes)            
crunchy-mastodon-mastodon-clj6-0               330m         8397Mi          
crunchy-mastodon-mastodon-vt55-0               20m          85Mi            
crunchy-mastodon-pgbouncer-868b6856f4-7qpck    24m          3Mi             
crunchy-mastodon-pgbouncer-868b6856f4-gnm66    13m          9Mi             
crunchy-mastodon-repo-host-0                   3m           507Mi 
pgo-6fc489c7df-5d247                           1m           51Mi
```

And `pg_database_size` returned 39GB:

```sql
mastodon_production=# SELECT datname as db_name, pg_size_pretty(pg_database_size('mastodon_production')) as db_usage FROM pg_database;
       db_name       | db_usage 
---------------------+----------
 template1           | 39 GB
 template0           | 39 GB
 postgres            | 39 GB
 mastodon_production | 39 GB
(4 rows)
```

Which is pretty scary. We will only be really afford a [single node Postgres cluster](https://www.digitalocean.com/pricing/managed-databases#postgresql) in DOcean, which feels like it will definitely take a performance and reliability hit to what we are coming from 😓. I'm going to start with the tier3 `db-s-2vcpu-4gb` ($48/mo) and pray that can get us off the ground. If we DO end up needing an instance with ~8gb memory, then it will run us around $100/month for just the postgres DB. Yikes


#### pg_restore Timeouts

Trying to pipe 7gigs through a `pg_restore` had the restore timing out a lot. I added the env settings listed [here](https://stackoverflow.com/a/9235991) and it seemed to push it through. I was on the brink of spinning up a VM in DOCean to do this, but I really didn't want to.


#### fin

The whole thing took around an hour to transfer.


### Redis

#### Data Transfer

Unfortunately, the redis at home has TLS disabled, and you can't get to the raw DB files in a DOcean managed redis cluster. That's fine, I recon, as it's one of the reasons we are pushing for this (simplicity and ignorance). It does make migrating the data in our B&M redis cluster a bit more difficult, though. Our options are:

There are two ways to do this: the MIGRATE command and via replication, the latter being an option that is touted as having no downtime (meh, it's inevitable for us). However, neither will work out of the box. In order for MIGRATE to work, both of the servers will either have to be on TLS or not on TLS- there is no mismatching allowed. I would run something like:

`redis-cli -a "localpass" --raw KEYS '*' | xargs redis-cli -a "localpass" MIGRATE mastodon-redis-production-do.ondigitalocean.com 25061 "" 0 5000 COPY AUTH2 default remotepass KEYS`

And it should copy the keys from a local cluster to a remote one. Unfortunately, there is no way to say that the remote db has TLS enabled without using an env variable and setting it for the source DB as well. There is an [SSL argument in the terraform resource](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs/resources/database_redis_config#ssl), but flipping it doesn't seem to do anything.

The "migration tool" DOcean offers is jut replication, I think. But the redis db needs to be open to the internet, and that would take a significant amount of network wrangling on its own. I think when migration day comes, we'll decide on how to proceed.

