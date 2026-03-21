# PRoot-Distro ARM64 Environment Profile

**Detection:** Kernel contains `PRoot-Distro` (`uname -r`) AND `uname -m` = `aarch64`

This environment runs Ubuntu inside Termux's proot-distro on Android (ARM64). It emulates a Linux root filesystem but has fundamental limitations that cause cascading failures if not handled upfront.

---

## Known Constraints & Workarounds

### 1. Native Binary Modules (CRITICAL)

**Problem:** Native Node.js addons compiled for standard Linux/ARM64 often fail because proot intercepts syscalls. Affected packages include:
- `@parcel/watcher` — filesystem watching (used by many bundlers)
- `@rollup/rollup-linux-arm64-gnu` — Rollup native optimizer
- `@swc/core` — SWC compiler
- `esbuild` — already has ARM64 binary but may have issues
- `turbo` — Turborepo native binary
- `sharp` — Image processing
- Any package with `node-gyp` compilation

**Workaround:**
```bash
# Force JavaScript fallback for @parcel/watcher
echo 'PARCEL_WATCHER_BACKEND=fs-events' >> .env
# Or in package.json:
# "overrides": { "@parcel/watcher": "npm:@aspect-build/chokidar-watcher" }

# For pnpm, add to .npmrc:
# shamefully-hoist=true
# node-linker=hoisted

# Skip optional native deps that will fail:
pnpm install --ignore-scripts
# Then selectively run postinstall for packages that work:
pnpm rebuild esbuild
```

**Prevention:** Before `pnpm install`, check if `.npmrc` has `ignore-scripts=false` and warn. Always prefer JS-based alternatives to native modules when available.

### 2. Symlink Issues in node_modules/.bin (CRITICAL)

**Problem:** proot translates absolute paths in symlinks. When pnpm creates `.bin` symlinks, they may point to translated paths (e.g., `/.l2s/...` instead of real paths). This breaks:
- `pnpm run <script>` — scripts can't find binaries
- `pnpm dlx <package>` — same issue
- Direct `./node_modules/.bin/<tool>` execution

**Workaround:**
```bash
# Option 1: Use hoisted node_modules layout
echo "node-linker=hoisted" >> .npmrc

# Option 2: Fix broken symlinks after install
find node_modules/.bin -type l ! -exec test -e {} \; -delete
pnpm install

# Option 3: Run tools via their actual paths
node node_modules/<package>/bin/<tool>.js
# Instead of:
./node_modules/.bin/<tool>
```

**Prevention:** Always verify symlinks after `pnpm install`:
```bash
# Quick check for broken symlinks
find node_modules/.bin -type l ! -exec test -e {} \; -print 2>/dev/null | head -5
```

### 3. Playwright / Browser Automation (WORKS)

Chromium IS available in proot-distro ARM64 at `/usr/bin/chromium`. Playwright tests, `browser_take_screenshot`, and `browser_snapshot` all work normally. Use `pnpm exec playwright test` as in any other environment. No special workarounds needed.

### 4. tsgo Binary Path Resolution (HANDLED)

**Problem:** Go binaries resolve libs relative to `/proc/self/exe`, which proot translates to `/.l2s/`. TypeScript lib.d.ts files can't be found.

**Workaround (already implemented in end-of-turn-typecheck.sh):**
```bash
# Copy lib.d.ts files to /.l2s/ where tsgo expects them
if [ -d "/.l2s" ]; then
  cp /path/to/tsgo/lib/lib*.d.ts /.l2s/
fi
```

**Prevention:** The `end-of-turn-typecheck.sh` hook already handles this. For other Go binaries that exhibit similar behavior, apply the same pattern: copy required resource files to `/.l2s/`.

### 5. /proc Limitations

**Problem:** proot emulates `/proc` imperfectly. Some entries are missing or return unexpected values:
- `/proc/self/exe` → translated to `/.l2s/` paths
- `/proc/cpuinfo` → may show host CPU, not emulated
- `/proc/meminfo` → reflects host, not container limits

**Workaround:** Don't rely on `/proc` for resource detection. Hardcode reasonable defaults for:
- CPU cores: assume 4
- Memory: assume 4GB available
- Don't use process-level resource monitoring

### 6. File Watching / Hot Reload (DEGRADED)

**Problem:** `inotify` works partially in proot but is unreliable. File watchers may:
- Miss changes
- Trigger excessive events
- Consume excessive CPU with polling fallback

**Workaround:**
```bash
# Force polling mode with reasonable interval
CHOKIDAR_USEPOLLING=true
CHOKIDAR_INTERVAL=1000
WATCHPACK_POLLING=true

# Or use --poll flag for dev servers:
pnpm dev -- --poll 1000

# Reduce watched files:
# Add node_modules, .next, dist to ignore patterns
```

**Prevention:** Set these environment variables in the project's `.env` file before starting dev servers.

### 7. API Rate Limits

**Problem:** External API calls (GitHub, npm registry, Anthropic API) may hit rate limits, especially during batch operations.

**Workaround:**
```bash
# Retry with exponential backoff (bash function)
retry_with_backoff() {
  local max_retries=${1:-3}
  local delay=${2:-2}
  shift 2
  local attempt=0
  while [ $attempt -lt $max_retries ]; do
    if "$@"; then return 0; fi
    attempt=$((attempt + 1))
    if [ $attempt -lt $max_retries ]; then
      echo "Attempt $attempt failed. Retrying in ${delay}s..." >&2
      sleep $delay
      delay=$((delay * 2))
    fi
  done
  return 1
}

# Usage: retry_with_backoff 3 2 gh api /repos/...
```

**Prevention:** Batch API calls where possible. Use `--paginate` with `gh` to reduce calls. Cache API responses locally.

### 8. SST / IaC State Locks

**Problem:** SST (and other IaC tools) create state lock files. If a deploy is interrupted (common in proot due to instability), the lock persists and blocks subsequent deploys.

**Workaround:**
```bash
# Check for stale SST locks
ls -la .sst/lock* 2>/dev/null

# If lock is stale (process no longer running):
rm .sst/lock 2>/dev/null

# For AWS state locks (DynamoDB):
# Check if lock is actually held by a running process before removing
aws dynamodb delete-item --table-name <lock-table> --key '{"LockID":{"S":"<lock-id>"}}'
```

**Prevention:** Always check for stale locks before `sst deploy`. Set timeouts on deploy commands.

### 9. Memory Pressure

**Problem:** proot-distro shares memory with Android. Heavy builds (webpack, Next.js, TypeScript compilation) can OOM.

**Workaround:**
```bash
# Limit Node.js memory
export NODE_OPTIONS="--max-old-space-size=2048"

# For pnpm install, reduce concurrency
pnpm install --network-concurrency 4

# For builds, use incremental mode
pnpm build -- --incremental
```

### 10. Performance Expectations

**Problem:** Everything runs 2-5x slower than native Linux due to proot syscall interception. Unrealistic timeouts or performance thresholds will cause false failures.

**Workaround:**
- Multiply all timeout values by 3x minimum
- Don't use Lighthouse/PageSpeed performance scores as gates in this environment
- Type checking with `tsc` takes 2-3x longer — accept it
- `pnpm install` may take 5-10 minutes for large projects

---

## Preflight Checklist (Run Before Build/Deploy Sessions)

```bash
#!/usr/bin/env bash
# Quick environment health check for proot-distro

echo "=== PRoot-Distro Preflight Check ==="

# 1. Verify node/pnpm
echo -n "Node: "; node --version 2>/dev/null || echo "MISSING"
echo -n "pnpm: "; pnpm --version 2>/dev/null || echo "MISSING"

# 2. Check disk space (proot can fill up fast)
echo -n "Disk: "; df -h / | tail -1 | awk '{print $4 " free"}'

# 3. Check for stale locks
if ls .sst/lock* 2>/dev/null; then
  echo "WARNING: SST lock file found — check if stale"
fi

# 4. Check node_modules health
if [ -d node_modules ]; then
  BROKEN=$(find node_modules/.bin -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)
  if [ "$BROKEN" -gt 0 ]; then
    echo "WARNING: $BROKEN broken symlinks in node_modules/.bin"
  else
    echo "Symlinks: OK"
  fi
fi

# 5. Check /.l2s/ for tsgo compat
if [ -d "/.l2s" ]; then
  echo "PRoot /.l2s/ directory: present (tsgo compat may be needed)"
fi

echo "=== Preflight Complete ==="
```

---

## Quick Reference: What NOT to Attempt

| Action | Why | Alternative |
|--------|-----|-------------|
| `playwright install chromium` | Already installed at /usr/bin/chromium | Just run `pnpm exec playwright test` |
| `pnpm install` without checking .npmrc | Native modules will fail | Add ignore-scripts, verify symlinks |
| Lighthouse CI in this env | Unreliable perf scores | Run on real CI only |
| `node-gyp rebuild` | Most native builds fail | Use JS alternatives |
| Rely on `inotify` | Unreliable in proot | Use polling mode |
| Trust `/proc` values | Emulated, not real | Hardcode defaults |
| Set tight timeouts | Everything is 2-5x slower | Multiply by 3x |
| Force push after interrupted deploy | State may be corrupted | Check locks first |
