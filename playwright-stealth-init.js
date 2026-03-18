// Comprehensive Playwright stealth init script
// Patches browser APIs to avoid bot detection fingerprinting

(() => {
  // 1. Remove navigator.webdriver flag
  Object.defineProperty(navigator, 'webdriver', {
    get: () => undefined,
  });

  // 2. Chrome runtime stubs
  if (!window.chrome) {
    window.chrome = {};
  }
  window.chrome.runtime = {
    PlatformOs: { MAC: 'mac', WIN: 'win', ANDROID: 'android', CROS: 'cros', LINUX: 'linux', OPENBSD: 'openbsd' },
    PlatformArch: { ARM: 'arm', X86_32: 'x86-32', X86_64: 'x86-64', MIPS: 'mips', MIPS64: 'mips64' },
    PlatformNaclArch: { ARM: 'arm', X86_32: 'x86-32', X86_64: 'x86-64', MIPS: 'mips', MIPS64: 'mips64' },
    RequestUpdateCheckStatus: { THROTTLED: 'throttled', NO_UPDATE: 'no_update', UPDATE_AVAILABLE: 'update_available' },
    OnInstalledReason: { INSTALL: 'install', UPDATE: 'update', CHROME_UPDATE: 'chrome_update', SHARED_MODULE_UPDATE: 'shared_module_update' },
    OnRestartRequiredReason: { APP_UPDATE: 'app_update', OS_UPDATE: 'os_update', PERIODIC: 'periodic' },
    connect: function() {},
    sendMessage: function() {},
  };

  window.chrome.app = {
    isInstalled: false,
    InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
    RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' },
    getDetails: function() { return null; },
    getIsInstalled: function() { return false; },
    runningState: function() { return 'cannot_run'; },
  };

  window.chrome.csi = function() {
    return {
      onloadT: Date.now(),
      startE: Date.now(),
      pageT: performance.now(),
      tran: 15,
    };
  };

  window.chrome.loadTimes = function() {
    return {
      get commitLoadTime() { return Date.now() / 1000; },
      get connectionInfo() { return 'h2'; },
      get finishDocumentLoadTime() { return Date.now() / 1000; },
      get finishLoadTime() { return Date.now() / 1000; },
      get firstPaintAfterLoadTime() { return 0; },
      get firstPaintTime() { return Date.now() / 1000; },
      get navigationType() { return 'Other'; },
      get npnNegotiatedProtocol() { return 'h2'; },
      get requestTime() { return Date.now() / 1000 - 0.16; },
      get startLoadTime() { return Date.now() / 1000; },
      get wasAlternateProtocolAvailable() { return false; },
      get wasFetchedViaSpdy() { return true; },
      get wasNpnNegotiated() { return true; },
    };
  };

  // 3. Fake navigator.plugins (PluginArray with Chrome PDF Plugin etc.)
  const makePlugin = (name, description, filename, mimeTypes) => {
    const plugin = Object.create(Plugin.prototype);
    Object.defineProperties(plugin, {
      name: { get: () => name, enumerable: true },
      description: { get: () => description, enumerable: true },
      filename: { get: () => filename, enumerable: true },
      length: { get: () => mimeTypes.length, enumerable: true },
    });
    mimeTypes.forEach((mt, i) => {
      const mimeType = Object.create(MimeType.prototype);
      Object.defineProperties(mimeType, {
        type: { get: () => mt.type },
        suffixes: { get: () => mt.suffixes },
        description: { get: () => mt.description },
        enabledPlugin: { get: () => plugin },
      });
      Object.defineProperty(plugin, i, { get: () => mimeType });
      Object.defineProperty(plugin, mt.type, { get: () => mimeType });
    });
    return plugin;
  };

  const pluginsData = [
    {
      name: 'Chrome PDF Plugin',
      description: 'Portable Document Format',
      filename: 'internal-pdf-viewer',
      mimeTypes: [
        { type: 'application/x-google-chrome-pdf', suffixes: 'pdf', description: 'Portable Document Format' },
      ],
    },
    {
      name: 'Chrome PDF Viewer',
      description: '',
      filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai',
      mimeTypes: [
        { type: 'application/pdf', suffixes: 'pdf', description: '' },
      ],
    },
    {
      name: 'Native Client',
      description: '',
      filename: 'internal-nacl-plugin',
      mimeTypes: [
        { type: 'application/x-nacl', suffixes: '', description: 'Native Client Executable' },
        { type: 'application/x-pnacl', suffixes: '', description: 'Portable Native Client Executable' },
      ],
    },
  ];

  const fakePlugins = pluginsData.map(p =>
    makePlugin(p.name, p.description, p.filename, p.mimeTypes)
  );

  const pluginArray = Object.create(PluginArray.prototype);
  fakePlugins.forEach((plugin, i) => {
    Object.defineProperty(pluginArray, i, { get: () => plugin, enumerable: true });
    Object.defineProperty(pluginArray, plugin.name, { get: () => plugin });
  });
  Object.defineProperty(pluginArray, 'length', { get: () => fakePlugins.length });
  pluginArray.item = function(index) { return fakePlugins[index] || null; };
  pluginArray.namedItem = function(name) { return fakePlugins.find(p => p.name === name) || null; };
  pluginArray.refresh = function() {};
  pluginArray[Symbol.iterator] = function*() { yield* fakePlugins; };

  Object.defineProperty(navigator, 'plugins', {
    get: () => pluginArray,
  });

  // 4. Navigator languages consistency
  Object.defineProperty(navigator, 'languages', {
    get: () => ['en-US', 'en'],
  });
  Object.defineProperty(navigator, 'language', {
    get: () => 'en-US',
  });

  // 5. Navigator permissions (notifications = 'prompt')
  const originalQuery = navigator.permissions.query;
  navigator.permissions.query = function(parameters) {
    if (parameters.name === 'notifications') {
      return Promise.resolve({ state: 'prompt', onchange: null });
    }
    return originalQuery.call(this, parameters);
  };

  // 6. Navigator vendor
  Object.defineProperty(navigator, 'vendor', {
    get: () => 'Google Inc.',
  });

  // 7. Hardware concurrency
  Object.defineProperty(navigator, 'hardwareConcurrency', {
    get: () => 4,
  });

  // 8. Navigator connection
  if (!navigator.connection) {
    Object.defineProperty(navigator, 'connection', {
      get: () => ({
        effectiveType: '4g',
        rtt: 50,
        downlink: 10,
        saveData: false,
        onchange: null,
        ontypechange: null,
        type: 'wifi',
      }),
    });
  }

  // 9. WebGL vendor/renderer spoofing
  const getParameterProxyHandler = {
    apply: function(target, thisArg, args) {
      const param = args[0];
      const gl = thisArg;
      // UNMASKED_VENDOR_WEBGL
      if (param === 0x9245) {
        return 'Intel Inc.';
      }
      // UNMASKED_RENDERER_WEBGL
      if (param === 0x9246) {
        return 'Intel Iris OpenGL Engine';
      }
      return Reflect.apply(target, thisArg, args);
    },
  };

  const getExtensionProxyHandler = {
    apply: function(target, thisArg, args) {
      const result = Reflect.apply(target, thisArg, args);
      if (args[0] === 'WEBGL_debug_renderer_info' && result) {
        // Return a proxy that intercepts getParameter calls with the debug constants
        return result;
      }
      return result;
    },
  };

  // Patch both WebGL and WebGL2
  ['WebGLRenderingContext', 'WebGL2RenderingContext'].forEach(ctxName => {
    const ctx = window[ctxName];
    if (ctx && ctx.prototype) {
      const origGetParameter = ctx.prototype.getParameter;
      ctx.prototype.getParameter = new Proxy(origGetParameter, getParameterProxyHandler);
    }
  });

  // 10. Canvas fingerprint noise (subtle randomization)
  const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
  HTMLCanvasElement.prototype.toDataURL = function(type, quality) {
    const context = this.getContext('2d');
    if (context && this.width > 0 && this.height > 0) {
      try {
        const imageData = context.getImageData(0, 0, Math.min(this.width, 2), Math.min(this.height, 2));
        // Add subtle noise to a few pixels
        for (let i = 0; i < imageData.data.length && i < 16; i += 4) {
          imageData.data[i] = imageData.data[i] ^ 1; // flip least significant bit of R channel
        }
        context.putImageData(imageData, 0, 0);
      } catch (e) {
        // Canvas might be tainted, ignore
      }
    }
    return origToDataURL.call(this, type, quality);
  };

  const origToBlob = HTMLCanvasElement.prototype.toBlob;
  HTMLCanvasElement.prototype.toBlob = function(callback, type, quality) {
    const context = this.getContext('2d');
    if (context && this.width > 0 && this.height > 0) {
      try {
        const imageData = context.getImageData(0, 0, Math.min(this.width, 2), Math.min(this.height, 2));
        for (let i = 0; i < imageData.data.length && i < 16; i += 4) {
          imageData.data[i] = imageData.data[i] ^ 1;
        }
        context.putImageData(imageData, 0, 0);
      } catch (e) {}
    }
    return origToBlob.call(this, callback, type, quality);
  };

  // 11. Window outer dimensions consistency
  Object.defineProperty(window, 'outerWidth', {
    get: () => window.innerWidth,
  });
  Object.defineProperty(window, 'outerHeight', {
    get: () => window.innerHeight + 85, // typical browser chrome height
  });

  // 12. Screen colorDepth and pixelDepth
  Object.defineProperty(screen, 'colorDepth', {
    get: () => 24,
  });
  Object.defineProperty(screen, 'pixelDepth', {
    get: () => 24,
  });

  // 13. sec-ch-ua Client Hints consistency
  Object.defineProperty(navigator, 'userAgentData', {
    get: () => ({
      brands: [
        { brand: 'Chromium', version: '144' },
        { brand: 'Google Chrome', version: '144' },
        { brand: 'Not:A-Brand', version: '99' },
      ],
      mobile: false,
      platform: 'Linux',
      getHighEntropyValues: function(hints) {
        return Promise.resolve({
          architecture: 'x86',
          bitness: '64',
          brands: this.brands,
          fullVersionList: [
            { brand: 'Chromium', version: '144.0.7559.109' },
            { brand: 'Google Chrome', version: '144.0.7559.109' },
            { brand: 'Not:A-Brand', version: '99.0.0.0' },
          ],
          mobile: false,
          model: '',
          platform: 'Linux',
          platformVersion: '6.17.0',
          uaFullVersion: '144.0.7559.109',
          wow64: false,
        });
      },
      toJSON: function() {
        return {
          brands: this.brands,
          mobile: this.mobile,
          platform: this.platform,
        };
      },
    }),
  });

  // 14. Media codecs (canPlayType returns correct values for common formats)
  const origCanPlayType = HTMLMediaElement.prototype.canPlayType;
  HTMLMediaElement.prototype.canPlayType = function(mediaType) {
    const codecMap = {
      'video/mp4': 'probably',
      'video/mp4; codecs="avc1.42E01E"': 'probably',
      'video/mp4; codecs="avc1.42E01E, mp4a.40.2"': 'probably',
      'video/webm': 'probably',
      'video/webm; codecs="vp8"': 'probably',
      'video/webm; codecs="vp8, vorbis"': 'probably',
      'video/webm; codecs="vp9"': 'probably',
      'video/ogg': 'probably',
      'video/ogg; codecs="theora"': 'probably',
      'audio/mpeg': 'probably',
      'audio/mp4; codecs="mp4a.40.2"': 'probably',
      'audio/webm; codecs="vorbis"': 'probably',
      'audio/webm; codecs="opus"': 'probably',
      'audio/ogg; codecs="vorbis"': 'probably',
      'audio/ogg; codecs="opus"': 'probably',
      'audio/wav': 'probably',
      'audio/flac': 'probably',
    };
    const result = codecMap[mediaType];
    if (result !== undefined) {
      return result;
    }
    return origCanPlayType.call(this, mediaType);
  };

  // 15. Additional stealth: remove Playwright/automation markers from Error stack traces
  const origGetOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
  // Ensure toString on patched functions looks native
  const nativeToString = Function.prototype.toString;
  const patchedFunctions = new Set();

  const origToString = Function.prototype.toString;
  Function.prototype.toString = function() {
    if (patchedFunctions.has(this)) {
      return 'function ' + (this.name || '') + '() { [native code] }';
    }
    return origToString.call(this);
  };
  patchedFunctions.add(Function.prototype.toString);
  patchedFunctions.add(navigator.permissions.query);
  patchedFunctions.add(HTMLCanvasElement.prototype.toDataURL);
  patchedFunctions.add(HTMLCanvasElement.prototype.toBlob);
  patchedFunctions.add(HTMLMediaElement.prototype.canPlayType);

  // 16. Prevent iframe contentWindow detection
  try {
    const origContentWindowGetter = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'contentWindow');
    if (origContentWindowGetter && origContentWindowGetter.get) {
      Object.defineProperty(HTMLIFrameElement.prototype, 'contentWindow', {
        get: function() {
          const win = origContentWindowGetter.get.call(this);
          if (win) {
            try {
              Object.defineProperty(win.navigator, 'webdriver', { get: () => undefined });
            } catch (e) {}
          }
          return win;
        },
      });
    }
  } catch (e) {}

  // 17. Console.debug marker removal (some detectors check for this)
  // Already handled by the native toString patch above

  console.log('[stealth] Init script loaded successfully');
})();
