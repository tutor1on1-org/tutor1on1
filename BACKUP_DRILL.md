# Backup Restore Drill
Last updated: 2026-02-27

## Goal
Verify backups are restorable and usable for service recovery before a real incident.

## Frequency
- Run at least monthly.
- Run after major schema migrations.

## Prerequisites
- Access to a recent backup artifact (`.sql` dump or snapshot export).
- Isolated restore target (never restore over production directly).
- MySQL client tools (`mysql`, `mysqldump`) available on restore target.
- API binary and env file available for post-restore smoke checks.

## Drill Procedure
1. Select backup artifact
- Choose latest successful backup and one older backup (at least 7 days old).
- Record artifact paths and timestamps in drill notes.

2. Restore to isolated database
- Create a temporary restore DB, for example `family_teacher_restore_drill`.
- Restore backup into the temporary DB.
- Command template:
```bash
mysql -u <user> -p -e "DROP DATABASE IF EXISTS family_teacher_restore_drill; CREATE DATABASE family_teacher_restore_drill;"
mysql -u <user> -p family_teacher_restore_drill < /path/to/backup.sql
```

3. Validate schema and data integrity
- Confirm critical tables exist: `users`, `teacher_accounts`, `courses`, `bundles`, `bundle_versions`, `enrollments`, `chat_sessions`, `student_course_progress`.
- Run row-count sanity checks and compare against expected production ranges at backup time.
- Command template:
```bash
mysql -u <user> -p -D family_teacher_restore_drill -e "SELECT COUNT(*) AS users FROM users;"
mysql -u <user> -p -D family_teacher_restore_drill -e "SELECT COUNT(*) AS courses FROM courses;"
mysql -u <user> -p -D family_teacher_restore_drill -e "SELECT COUNT(*) AS bundles FROM bundles;"
```

4. Run API smoke checks against restored DB
- Point API env to restore DB.
- Start API with restore DB and run auth + marketplace smoke scripts:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/test_auth.ps1 -BaseUrl "https://<restore-host>"
powershell -ExecutionPolicy Bypass -File scripts/smoke_teacher_student_flow.ps1 -BaseUrl "https://<restore-host>"
```
- Verify enrollment request, approval, and bundle download paths pass.

5. Cleanup and record evidence
- Stop restore API instance.
- Drop temporary restore DB.
- Save drill report with:
  - backup artifact id/time
  - restore duration
  - validation query outputs
  - smoke test result
  - issues found and owner

## Exit Criteria
- Restore completed without SQL errors.
- Critical-table checks passed.
- Smoke tests passed.
- Drill report stored with timestamp and owner.

## Incident Checklist
1. Declare incident severity and assign incident commander.
2. Freeze destructive operations (deletes/migrations) until containment.
3. Capture current system state (service status, error logs, failing endpoints).
4. Identify last known-good backup candidate and restore target.
5. Perform restore to isolated environment first and validate with smoke scripts.
6. Communicate ETA and data-loss window to stakeholders.
7. Execute production cutover only after restore validation is green.
8. Revoke tokens/credentials if compromise suspected.
9. After recovery, run post-incident verification:
- login/auth flows
- enrollment and bundle download
- session/progress sync
10. Publish postmortem with root cause, timeline, and prevention actions.
