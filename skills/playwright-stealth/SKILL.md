---
name: playwright-stealth
description: >
  Stealth web browsing and content extraction for accessing the user's own content
  on sites with bot detection. Uses Patchright (Playwright fork) + Xvfb virtual
  display + headed Chromium. Use this skill when the user wants to access their own
  content on sites that block automated browsers, read their own blog posts, verify
  their own published pages, or interact with sites that misidentify automation as
  bot traffic. Also use when the user says "stealth browse", "get page content",
  "open this URL", "read this page", "check this site", or mentions bot detection.
paths:
  - "**/*.spec.ts"
  - "**/e2e/**"
  - "**/playwright/**"
---

# Playwright Stealth: Anti-Detection Web Browsing

> **Intended use:** Accessing your own content on sites where automated browsers are
> incorrectly blocked by bot detection systems. This is personal tooling for content
> verification, not for unauthorized scraping of third-party data.

Uses Patchright (a Playwright fork that patches CDP-level automation leaks) with
a virtual display for headed mode to present as a standard browser.

## Why This Approach Works

Bot detection operates at multiple layers. Standard Playwright fails because:

| Layer | Detection Signal | Fix |
|-------|-----------------|-----|
| CDP Protocol | `Runtime.enable` leak, `Console.enable` | **Patchright** patches these at source level |
| Browser Identity | `HeadlessChrome` in `Browser.getVersion` | **Xvfb + headed mode** — browser reports standard Chrome |
| Automation Flags | `--enable-automation`, `navigator.webdriver=true` | Patchright removes flag; init script patches webdriver |
| JS Fingerprints | Missing plugins, wrong WebGL vendor, no `chrome.runtime` | **Init script** patches all of these |
| Headers | `Sec-Fetch-*` applied to all requests breaks CORS | **Route-based headers** — only on document requests |
| Behavior | Instant actions, no scrolling | **Human-like delays** between actions |

---

## Architecture

```
Xvfb (virtual X display, 1366x768x24)
  +-- Patchright launches Chromium in HEADED mode
        +-- Init scripts patch JS fingerprints
              +-- Navigate to target, challenge resolves in ~6s
```

**Prerequisites** (install once):
- `xvfb` — `apt-get install -y xvfb`
- `patchright` — `npm install patchright`
- System Chromium — `/usr/bin/chromium` (already installed)

---

## Step 1: Launch Stealth Browser

This is the critical step. Use `browser_run_code` to launch the full stealth stack.

### Option A: Via standalone script (for heavy extraction)

When you need full control, run a standalone script via Bash:

```bash
xvfb-run --auto-servernum --server-args="-screen 0 1366x768x24" \
  node /path/to/stealth-script.mjs
```

The script uses Patchright (same API as Playwright):

```javascript
import { chromium } from 'patchright';

const browser = await chromium.launch({
  executablePath: '/usr/bin/chromium',
  headless: false,  // HEADED — Xvfb provides the display
  args: [
    '--no-sandbox',
    '--disable-gpu',
    '--disable-dev-shm-usage',
    '--no-first-run',
    '--disable-infobars',
    '--window-size=1366,768',
    '--disable-blink-features=AutomationControlled',
  ],
});

const context = await browser.newContext({
  userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36',
  viewport: { width: 1366, height: 768 },
  locale: 'en-US',
  timezoneId: 'America/New_York',
});
```

### Option B: Via Playwright MCP (for interactive browsing)

When using the MCP tools directly, apply stealth patches at the MCP level.
The MCP plugin can be reconfigured for stealth by updating its config:

```bash
claude mcp add playwright -- npx @playwright/mcp@latest \
  --executable-path /usr/bin/chromium \
  --no-sandbox \
  --init-script ~/.claude/playwright-stealth-init.js \
  --user-agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36" \
  --viewport-size 1366x768
```

**Important:** The MCP approach lacks Patchright's CDP patches and Xvfb headed mode,
so it will NOT bypass JS challenge pages. Use Option A for sites with aggressive
bot detection. Use the MCP for sites with lighter or no detection.

---

## Step 2: Register Stealth Init Scripts

Add these patches BEFORE navigating. They run in the page context before any page JS.

```javascript
await context.addInitScript(() => {
  // 1. Remove webdriver flag
  Object.defineProperty(navigator, 'webdriver', {
    get: () => undefined, configurable: true
  });

  // 2. Mock chrome runtime (exists in real Chrome, missing in automation)
  window.chrome = {
    runtime: {
      onMessage: { addListener() {}, removeListener() {} },
      sendMessage() {},
      connect() { return { onMessage: { addListener() {} }, postMessage() {} }; }
    },
    loadTimes() { return {}; },
    csi() { return {}; },
    app: {
      isInstalled: false,
      InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
      RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' }
    }
  };

  // 3. Fake plugins (real Chrome has 3, headless has 0)
  Object.defineProperty(navigator, 'plugins', {
    get: () => {
      const p = [
        { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format', length: 1 },
        { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '', length: 1 },
        { name: 'Native Client', filename: 'internal-nacl-plugin', description: '', length: 1 }
      ];
      p.refresh = () => {};
      return p;
    }
  });

  // 4. Languages & vendor consistency
  Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
  Object.defineProperty(navigator, 'vendor', { get: () => 'Google Inc.' });
  Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => 8 });

  // 5. Fix permissions API (headless returns 'denied' for notifications)
  const origQuery = window.Permissions?.prototype?.query;
  if (origQuery) {
    window.Permissions.prototype.query = function(params) {
      if (params.name === 'notifications') return Promise.resolve({ state: 'prompt', onchange: null });
      return origQuery.call(this, params);
    };
  }

  // 6. Connection info
  Object.defineProperty(navigator, 'connection', {
    get: () => ({ effectiveType: '4g', rtt: 50, downlink: 10, saveData: false })
  });

  // 7. Screen properties
  Object.defineProperty(screen, 'colorDepth', { get: () => 24 });
  Object.defineProperty(screen, 'pixelDepth', { get: () => 24 });

  // 8. WebGL vendor/renderer spoof (hide SwiftShader)
  const getParam = WebGLRenderingContext.prototype.getParameter;
  WebGLRenderingContext.prototype.getParameter = function(param) {
    if (param === 37445) return 'Intel Inc.';
    if (param === 37446) return 'Intel Iris OpenGL Engine';
    return getParam.call(this, param);
  };
  const getParam2 = WebGL2RenderingContext?.prototype?.getParameter;
  if (getParam2) {
    WebGL2RenderingContext.prototype.getParameter = function(param) {
      if (param === 37445) return 'Intel Inc.';
      if (param === 37446) return 'Intel Iris OpenGL Engine';
      return getParam2.call(this, param);
    };
  }
});
```

---

## Step 3: Navigate and Handle Bot Challenges

```javascript
const page = await context.newPage();
const response = await page.goto(targetUrl, {
  waitUntil: 'domcontentloaded',
  timeout: 30000
});

// Check for JS challenge page
const title = await page.title();
if (title.includes('Just a moment') || title.includes('Attention Required')) {
  // Wait for challenge to auto-resolve (typically 4-8 seconds with stealth)
  for (let i = 0; i < 20; i++) {
    await new Promise(r => setTimeout(r, 2000));
    const currentTitle = await page.title();
    if (!currentTitle.includes('Just a moment')) break;
  }
  // Wait for actual content to load after challenge resolves
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await new Promise(r => setTimeout(r, 3000));
}
```

### If Challenge Doesn't Resolve

If still blocked after 40 seconds, the site may have additional protection.
Escalation options:

1. **Ask user to solve manually** — user opens the URL in their real browser,
   solves the challenge, exports the clearance cookie for reuse
2. **Use platform API** — many sites offer APIs for accessing your own content
3. **Try cached version** — search engine caches may have the content

---

## Step 4: Handle Common Obstacles

### Cookie Consent Banners

Take a snapshot, find "Accept" / "Accept All" / "I Agree" button, click it.

### Login Wall Detection

If the page shows a login form:
1. Tell the user what you see and ask if they want to log in
2. Ask for credentials (NEVER store or log them)
3. Type slowly for login fields:
   ```javascript
   await page.fill('#email', email);
   await new Promise(r => setTimeout(r, 1000 + Math.random() * 1000));
   await page.fill('#password', password);
   await new Promise(r => setTimeout(r, 500 + Math.random() * 500));
   await page.click('button[type="submit"]');
   ```
4. After login, re-navigate to the original target URL if redirected

### CAPTCHA

Tell the user: "A CAPTCHA appeared. I can't solve these automatically. Please solve
it manually, then tell me to continue." Wait for user signal.

---

## Step 5: Content Extraction

### Page Metadata

```javascript
const metadata = await page.evaluate(() => ({
  title: document.title,
  url: window.location.href,
  canonical: document.querySelector('link[rel="canonical"]')?.href,
  description: document.querySelector('meta[name="description"]')?.content,
  ogTitle: document.querySelector('meta[property="og:title"]')?.content,
  ogDescription: document.querySelector('meta[property="og:description"]')?.content,
  ogImage: document.querySelector('meta[property="og:image"]')?.content,
  author: document.querySelector('meta[name="author"]')?.content,
  publishDate: document.querySelector('meta[property="article:published_time"]')?.content
    || document.querySelector('time')?.getAttribute('datetime'),
  lang: document.documentElement.lang
}));
```

### Main Content

```javascript
const content = await page.evaluate(() => {
  const selectors = [
    'article', 'main', '[role="main"]',
    '.post-content', '.entry-content', '.article-content',
    '.content', '#content', '#main-content'
  ];
  let el = null;
  for (const s of selectors) {
    el = document.querySelector(s);
    if (el && el.textContent.trim().length > 200) break;
  }
  if (!el) el = document.body;
  return el.innerText;
});
```

### When using the MCP tools (Option B)

Use the same extraction pattern via MCP tools:

```
browser_snapshot                           -> page structure
browser_evaluate: () => document.title     -> metadata
browser_evaluate: () => document.body.innerText -> content
browser_console_messages: level="warning"  -> debug info
browser_network_requests: includeStatic=false -> detect blocks
```

---

## Artifact Output Paths (MANDATORY)

All Playwright-generated files MUST be saved to `.artifacts/playwright/` — never to the
project root. The `cleanup-artifacts` Stop hook will move any stray root-level media
files automatically, but the preferred approach is to write them to the right place from
the start.

| File type | Destination |
|-----------|-------------|
| Screenshots (`.png`, `.jpg`) | `.artifacts/playwright/screenshots/YYYY-MM-DD_HHmm/` |
| Videos (`.mp4`, `.webm`) | `.artifacts/playwright/videos/YYYY-MM-DD_HHmm/` |
| HAR files (`.har`) | `.artifacts/playwright/har/YYYY-MM-DD_HHmm/` |

### Creating the directory before saving

Always create the directory first:

```bash
ARTIFACT_DIR=".artifacts/playwright/screenshots/$(date +%Y-%m-%d_%H%M)"
mkdir -p "$ARTIFACT_DIR"
```

Then reference it in your Playwright script:

```javascript
const artifactDir = `.artifacts/playwright/screenshots/${new Date().toISOString().slice(0,16).replace('T','_').replace(':','')}`;
await fs.mkdir(artifactDir, { recursive: true });
await page.screenshot({ path: `${artifactDir}/page.png` });
```

### Via Playwright MCP tools

When using `browser_take_screenshot`, save to the artifact path explicitly:

```
browser_take_screenshot -> save as .artifacts/playwright/screenshots/YYYY-MM-DD_HHmm/name.png
```

Do NOT leave screenshots or videos in the project root directory.

---

## Step 6: Output Format

Present extracted data as structured markdown:

```markdown
# Page Extraction Report

## Metadata
- **URL:** [actual URL after redirects]
- **Title:** [page title]
- **Author:** [if found]
- **Published:** [if found]

## Content
[Main extracted content — headings, paragraphs, lists preserved]

## Diagnostics
- **Bot Detection:** [type detected / none]
- **Resolution:** [Auto-resolved in Xs / No challenge / Manual intervention needed]
- **Console Errors:** [Any relevant errors]
```

---

## Reference Scripts

### Stealth init script (standalone file)
Location: `~/.claude/playwright-stealth-init.js`

### Quick Reference: Approach Selection

| Site Protection | Approach | Works? |
|----------------|----------|--------|
| No bot detection | MCP tools directly | Yes |
| Light detection (basic JS checks) | MCP + init script | Yes |
| JS challenge pages | **Patchright + Xvfb** (Option A) | Yes (tested) |
| Public profiles on social platforms | Patchright + Xvfb or MCP | Yes (tested) |
| CAPTCHA required | Any — needs manual user intervention | Partial |

### Key Dependencies

| Package | Purpose | Install |
|---------|---------|---------|
| `patchright` | Playwright fork (patches CDP leaks) | `npm install patchright` |
| `xvfb` | Virtual X display for headed mode without real monitor | `apt-get install -y xvfb` |
| System Chromium | Real browser binary at `/usr/bin/chromium` | Pre-installed |

### Environment Notes (proot-distro ARM64)

- Always use `--no-sandbox` and `--disable-gpu` flags
- Use `xvfb-run --auto-servernum` to provide virtual display
- Generous timeouts — everything runs 2-5x slower
- Use `browser_snapshot` (not screenshots) when using MCP tools
- JS challenges typically resolve in 4-8 seconds with this stack
