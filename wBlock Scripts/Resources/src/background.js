// background.js
const NATIVE_APP_ID = "com.0xcube.wBlock.wBlock-Scripts";
const LOG_PREFIX = "[wBlock Scripts]";
const CHUNK_TIMEOUT = 30000; // 30 seconds

const log = {
  info: (msg, ...args) => console.log(`${LOG_PREFIX} ${msg}`, ...args),
  error: (msg, ...args) => console.error(`${LOG_PREFIX} ${msg}`, ...args),
  warn: (msg, ...args) => console.warn(`${LOG_PREFIX} ${msg}`, ...args),
};

let scriptletRegistry = undefined;
let loadRegistryPromise = undefined;
const scriptletCache = new Map();

const loadRegistry = async () => {
  try {
    const url = browser.runtime.getURL(
      "web_accessible_resources/registry.json",
    );
    const response = await fetch(url);
    const registry = await response.json();
    log.info("(loadRegistry) Scriptlet registry loaded");
    return registry;
  } catch (error) {
    log.error("(loadRegistry) Scriptlet registry load failed:", error);
  }
};

const getScriptletCode = async (name) => {
  if (scriptletRegistry == undefined) {
    if (loadRegistryPromise == undefined) {
      loadRegistryPromise = loadRegistry();
    }
    scriptletRegistry = await loadRegistryPromise;
  }
  log.info(`(getScriptletCode) Getting code for ${name}...`);
  // Direct lookup with case-insensitive fallback
  const exactMatch = scriptletRegistry[name];
  const normalizedMatch = Object.entries(scriptletRegistry).find(
    ([key]) => key.toLowerCase() === name.toLowerCase(),
  )?.[1];

  const filename = exactMatch || normalizedMatch;
  if (!filename) {
    log.error(`(getScriptletCode) No registry entry for: ${name}`);
    return null;
  }

  // Return cached if available
  if (scriptletCache.has(filename)) {
    return scriptletCache.get(filename);
  }
  log.info(`(getScriptletCode) Filename: ${filename}`);
  try {
    const url = browser.runtime.getURL(
      `web_accessible_resources/scriptlets/${filename}`,
    );
    const response = await fetch(url);
    const code = await response.text();
    log.info(`(getScriptletCode) Received code`);
    log.info(`(getScriptletCode) Setting scriptlet cache...`);
    scriptletCache.set(filename, code);
    log.info(`(getScriptletCode) Set scriptlet cache`);
    return code;
  } catch (error) {
    log.error(
      `(getScriptletCode) Failed to load scriptlet file ${filename}:`,
      error,
    );
    return null;
  }
};

const clearScriptletCache = () => {
  scriptletCache.clear();
  log.info("(clearScriptletCache) Scriptlet cache cleared");
};

const chunkAccumulators = new Map();

browser.runtime.onStartup.addListener(clearScriptletCache);

browser.tabs.onRemoved.addListener((tabId) => {
  // Cleanup all accumulators for this tab
  for (const [key] of chunkAccumulators) {
    if (key.startsWith(`${tabId}-`)) {
      cleanupAccumulator(key);
    }
  }
});

browser.runtime.onMessage.addListener(async (message, sender) => {
  if (message.action === "getAdvancedBlockingData") {
    return await handleBlockingRequest(message, sender);
  }
  if (message.action === "getScriptlets") {
    return await handleScriptletRequest(message);
  }
  return false;
});

const handleScriptletRequest = async (request) => {
  if (request.action === "getScriptlets") {
    return Promise.all(
      request.scriptlets.map(async ({ name, args, sourceConfig }) => {
        if (!name || typeof name !== "string") {
          log.error("(handleScriptletRequest) Invalid scriptlet name:", name);
          return null;
        }

        const code = await getScriptletCode(name);
        if (!code) return null;

        return {
          code,
          source: {
            name: name.trim(),
            args: Array.isArray(args) ? args : [],
            engine: sourceConfig?.engine || "extension",
            version: sourceConfig?.version || "1.0.0",
            verbose: Boolean(sourceConfig?.verbose),
          },
          args,
        };
      }),
    );
  }
};

const handleBlockingRequest = async (message, sender) => {
  const { url, fromBeginning } = message;
  const requestId = Math.random().toString(36).slice(2); // Unique ID
  const accumulatorKey = `${sender.tab.id}-${url}-${requestId}`;

  try {
    if (typeof browser.runtime.sendNativeMessage !== "function") {
      log.warn(
        "(handleBlockingRequest) Native messaging is not supported on this platform.",
      );
      return { error: "Native messaging not supported" };
    }

    log.info(
      "(handleBlockingRequest) Native messaging (sendNativeMessage) is supported on this platform.",
    );

    // Initialize accumulator if starting from the beginning
    if (fromBeginning) {
      chunkAccumulators.set(accumulatorKey, {
        data: "",
        timeout: setTimeout(
          () => cleanupAccumulator(accumulatorKey),
          CHUNK_TIMEOUT,
        ),
      });
    }

    let moreChunks = true;
    let isFirstRequest = fromBeginning;

    // Loop to fetch all chunks
    while (moreChunks) {
      const response = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, {
        action: "getAdvancedBlockingData",
        url: url,
        fromBeginning: isFirstRequest, // Only true for the first request
      });

      log.info("(handleBlockingRequest) Response: ", response);

      if (response.error) throw new Error(response.error);

      // Process the response and update accumulator
      const result = processResponse(response, accumulatorKey);

      // Check if there are more chunks to fetch
      moreChunks = response.chunked && response.more;
      isFirstRequest = false; // Subsequent requests are continuations

      // If not chunked or no more chunks, return the final result
      if (!moreChunks) {
        return result;
      }
    }
  } catch (error) {
    cleanupAccumulator(accumulatorKey);
    log.error("(handleBlockingRequest) Request failed:", error);
    return { error: error.message };
  }
};

const processResponse = (response, accumulatorKey) => {
  let accumulator = chunkAccumulators.get(accumulatorKey);

  if (!response.chunked) {
    try {
      return validateAndParse(response);
    } catch (e) {
      return { error: e.message };
    }
  }

  if (!accumulator) {
    // Initialize if missing (edge case)
    chunkAccumulators.set(accumulatorKey, {
      data: "",
      timeout: setTimeout(
        () => cleanupAccumulator(accumulatorKey),
        CHUNK_TIMEOUT,
      ),
    });
    accumulator = chunkAccumulators.get(accumulatorKey);
  } else {
    // Reset timeout for existing accumulator
    clearTimeout(accumulator.timeout);
    accumulator.timeout = setTimeout(
      () => cleanupAccumulator(accumulatorKey),
      CHUNK_TIMEOUT,
    );
  }

  // Append data for ALL accumulators (new or existing)
  accumulator.data += String(response.data);

  // Check if this is the final chunk
  if (!response.more) {
    const finalData = accumulator.data;
    cleanupAccumulator(accumulatorKey);
    try {
      return validateAndParse({ data: finalData, verbose: response.verbose });
    } catch (e) {
      return { error: e.message };
    }
  }

  return { __chunked: true };
};

const validateAndParse = (response) => {
  if (!response.data) throw new Error("Empty response from native host");
  try {
    return {
      data: JSON.parse(response.data),
      verbose: response.verbose,
    };
  } catch (e) {
    throw new Error(`JSON parse error: ${e.message}`);
  }
};

const cleanupAccumulator = (key) => {
  const accumulator = chunkAccumulators.get(key);
  if (accumulator) {
    clearTimeout(accumulator.timeout);
    chunkAccumulators.delete(key);
  }
};
