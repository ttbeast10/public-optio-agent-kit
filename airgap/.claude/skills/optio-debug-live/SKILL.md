---
name: optio-debug-live
description: Inspect the running Optio on Rancher — API/web pod health, API logs, agent repo pods, a failing task's state history and logs in Postgres, queue state in Redis. Read-only checks first. Use when a deployed Optio misbehaves and you need evidence before touching code.
---

# Debug the running Optio (Rancher)

Take `NS` (namespace) and `REL` (Helm release) from `docs/airgap/site-facts.md`.
Everything below is read-only. Ask the user before deleting, restarting or editing anything.
Never print secret values (`printenv` only the variable you need; never `env` or `get secret -o yaml`).

## 1. Is the control plane healthy?

```bash
kubectl -n "$NS" get pods -o wide
kubectl -n "$NS" logs deploy/"$REL"-api -c api --since=30m | grep -iE "error|warn" | tail -40
kubectl -n "$NS" logs deploy/"$REL"-api -c web --since=30m | tail -20
kubectl -n "$NS" exec deploy/"$REL"-api -c api -- printenv GITLAB_HOSTS OPTIO_OUTBOUND_ALLOWED_HOSTS
```

## 2. Agent pods

```bash
kubectl -n "$NS" get pods -l managed-by=optio -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.containers[0].image
kubectl -n "$NS" describe pod <pod> | tail -30          # ImagePullBackOff, OOMKilled, scheduling
kubectl -n "$NS" logs <pod> --tail=80                   # repo-init.sh output: clone/auth/TLS errors
```

## 3. One task, from the database (bundled Postgres; for an external DB use its psql)

```bash
PG="kubectl -n $NS exec deploy/$REL-postgres -- psql -U <db user> -d <db name> -c"
$PG "SELECT id, kind, state, agent_type, left(error_message,160) AS err, updated_at FROM tasks ORDER BY updated_at DESC LIMIT 15;"
$PG "SELECT from_state, to_state, trigger, left(message,120), created_at FROM task_events WHERE task_id='<id>' ORDER BY created_at;"
$PG "SELECT log_type, left(content,200), timestamp FROM task_logs WHERE task_id='<id>' ORDER BY timestamp DESC LIMIT 40;"
$PG "SELECT pool, pool_key, pod_name, state, active_count, left(error_message,120) FROM agent_pods ORDER BY updated_at DESC LIMIT 20;"
```

User and DB name: `postgresql.auth.username` / `postgresql.auth.database` in the Helm values.
`tasks` holds every run (`kind` = `repo` or `standalone`).

## 4. Stuck in `queued`

Limits: `OPTIO_MAX_CONCURRENT` (global, default 5) and the repo's `maxConcurrentTasks`. Count what holds slots:
`$PG "SELECT state, count(*) FROM tasks WHERE state IN ('queued','provisioning','running') GROUP BY state;"`
Code: `apps/api/src/workers/task-worker.ts`, `apps/api/src/services/agent-pod-pool.ts`.

## 5. Map the evidence to code

Take the error text and grep it in source (it is usually a literal):
`grep -rn "<distinctive part of the message>" apps/api/src packages --include=*.ts | grep -v test`
Then follow the symptom table in root `CLAUDE.md`.

## Report

```
Where it fails: API | web | agent pod | DB | Redis
Evidence: <command> → <output line, secrets removed>
Code location: <file:line>
Next step: <config change | code fix via the debug skill | rebuild>
```
