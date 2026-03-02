# Security Policy

This repository is public-safe by design, but local runtime setup uses private secrets.

## Never commit
- `server/.env`
- any real API key (`OPENAI_API_KEY`, `OPENROUTER_API_KEY`, etc.)
- local databases (`server/data/*.db`)
- personal uploads (`server/uploads/*`)
- backup archives (`server/backups/*`)
- release binaries (`*.apk`, `*.aab`, `*.ipa`, `*.app`, `*.dmg`)

## Secret handling
- Keep secrets only in local `server/.env`.
- Use `server/.env.example` as template.
- If a key is exposed (terminal logs, screenshot, accidental commit), rotate it immediately.

## Pre-commit protection (recommended)

Install local pre-commit hook:

```bash
mkdir -p .git/hooks
cp scripts/pre-commit-secret-scan.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

This hook blocks commits when key-like patterns are found.

## If secret leaked in Git history
1. Revoke/rotate key at provider dashboard.
2. Remove secret from files.
3. Rewrite git history (if needed) using `git filter-repo` or BFG.
4. Force push rewritten history.

## Responsible disclosure
If you find a security issue in this project, do not post real exploit details publicly with active credentials.
Report privately to the maintainer first.
