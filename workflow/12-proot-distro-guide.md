# proot-distro ARM64 Guide

This section handles a specific but important use case: running the workflow on ARM64 devices using proot-distro (common with Termux on Android tablets).

## Why Special Handling Is Needed

proot-distro is a user-space process emulator. It doesn't have a real kernel — it intercepts system calls and translates them. This causes several classes of failures:

```
┌──────────────────────────────────────────────────────────┐
│            PROOT-DISTRO LIMITATIONS                      │
│                                                          │
│  ✗ Native binaries may crash (SIGSEGV, SIGBUS)          │
│  ✗ inotify doesn't work (no file watching)              │
│  ✗ /proc is limited                                     │
│  ✗ Everything runs 2-5x slower                          │
│                                                          │
│  ✓ Chromium works (/usr/bin/chromium)                    │
│  ✓ Playwright tests + screenshots work                   │
│  ✓ Polling-based file watching works                     │
│  ✓ JavaScript-only alternatives work                     │
│  ✓ python3 http.server works                             │
│  ✓ Node.js with increased memory works                   │
└──────────────────────────────────────────────────────────┘
```

## Auto-Detection

If `uname -r` contains `PRoot-Distro` AND `uname -m` = `aarch64`, all proot rules activate automatically. Three layers handle proot:

1. **settings.json env:** Sets `NODE_OPTIONS`, `CHOKIDAR_USEPOLLING`, `WATCHPACK_POLLING` globally
2. **proot-preflight.sh:** Runs once per session; warns about disk, symlinks, SST locks
3. **worktree-preflight.sh:** Called by orchestrator; sets env vars and fixes deps for sprint execution

## Mandatory Rules

| Rule | Why |
|---|---|
| Chromium works — use `pnpm exec playwright test` | Chromium is at `/usr/bin/chromium`. Playwright runs normally. |
| NEVER trust `pnpm install` blindly | Check `.npmrc` for `node-linker=hoisted`. Verify symlinks after install. |
| NEVER set tight timeouts | Everything runs 2-5x slower. Multiply by 3x minimum. |
| NEVER use Lighthouse as quality gate | Scores unreliable in proot. Mark as `BLOCKED: proot-distro ARM64`. |
| ALWAYS use polling for file watching | `CHOKIDAR_USEPOLLING=true` set globally in settings.json |
| ALWAYS use retry-with-backoff for APIs | Source `~/.claude/hooks/retry-with-backoff.sh` |

## Known Native Module Failures

These packages have native binaries that WILL fail in proot-distro:

| Package | Issue | Workaround |
|---|---|---|
| `@parcel/watcher` | Native binary crash | `PARCEL_WATCHER_BACKEND=fs-events` or JS fallback |
| `@rollup/rollup-linux-arm64-gnu` | Binary incompatible | `--ignore-scripts` and rebuild selectively |
| `sharp` | Native image processing | JS-based image processing alternatives |
| `turbo` (native) | Binary crash | Non-native mode |
| Any `node-gyp` build | Compilation fails | Prefer JS alternatives |

## Common Error Patterns

| Error | Root Cause | Fix |
|---|---|---|
| `ENOENT .bin/` | Broken symlink in node_modules | `pnpm install` with correct `.npmrc` |
| `spawn EACCES` | Binary not executable | Use JS alternative |
| `heap out of memory` | Default Node.js limit too low | `NODE_OPTIONS=--max-old-space-size=2048` (set globally) |
| `Chromium not found` | Playwright can't find browser | Run `pnpm exec playwright install chromium` or use system `/usr/bin/chromium` |
| `SIGBUS/SIGSEGV` on native binary | proot syscall translation failure | Use JS fallback |
| `inotify_add_watch` | inotify not available | Polling already enabled globally |

## Go Binary /.l2s/ Fix

Go binaries resolve libraries via `/proc/self/exe`, which proot translates to `/.l2s/`. Copy required resource files there:

```bash
if [ -d "/.l2s" ]; then cp /path/to/lib/*.d.ts /.l2s/; fi
```

Already handled for tsgo in `end-of-turn-typecheck.sh`.

## Playwright in proot

Chromium works in proot-distro ARM64 (`/usr/bin/chromium`). Playwright tests, screenshots, and browser automation all function normally. Use `pnpm exec playwright test` as in any other environment.

## Performance Expectations

Everything runs 2-5x slower in proot-distro. Plan accordingly:

| Operation | Normal | proot-distro |
|---|---|---|
| `pnpm install` | 30s | 1-2min |
| `pnpm build` | 1min | 2-5min |
| Type checking | 10s | 30s-1min |
| Test suite | 30s | 1-2min |

Multiply all timeouts by 3x minimum.

---

Next: [End-to-End Example](13-end-to-end-example.md)
