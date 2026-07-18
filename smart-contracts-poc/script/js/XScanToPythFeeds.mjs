#!/usr/bin/env node
/**
 * Multi-chain ERC-20 token scraper → Pyth Lazer feed mapper.
 *
 * For each configured chain (Base, Ethereum, Arbitrum, etc.):
 *   1. Scrapes top tokens from the chain's Etherscan-fork explorer
 *      using 3 sort criteria (volume, marketcap, holders) and intersects results
 *   2. Matches each token symbol against Pyth Lazer crypto feeds
 *   3. Saves per-chain JSON to <chain>.tokens.json
 *
 * Usage:
 *   npm install jsdom viem
 *   node multi_chain_pyth_lazer.mjs
 *
 * Env vars:
 *   MAX_PAGES=2         Pages per sort criterion (default: 1)
 *   REQUEST_DELAY=500   Delay between requests in ms (default: 300)
 *   CHAINS=base,arb     Comma-separated chain keys to process (default: all)
 *   DEBUG=1             Print raw Pyth API response sample
 */

import { JSDOM } from "jsdom";
import { getAddress } from "viem";
import fs from "fs";
import path from "path";

const SCRIPT_DIR = path.dirname(new URL(import.meta.url).pathname);

// ── Chain configs ───────────────────────────────────────────────────────────

const CHAINS = {
  base: {
    name: "Base",
    explorerUrl: "https://basescan.org/tokens",
    quoteToken: {
      symbol: "USDC",
      address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    },
  },
  ethereum: {
    name: "Ethereum",
    explorerUrl: "https://etherscan.io/tokens",
    quoteToken: {
      symbol: "USDC",
      address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    },
  },
  arbitrum: {
    name: "Arbitrum",
    explorerUrl: "https://arbiscan.io/tokens",
    quoteToken: {
      symbol: "USDC",
      address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    },
  },
  optimism: {
    name: "Optimism",
    explorerUrl: "https://optimistic.etherscan.io/tokens",
    quoteToken: {
      symbol: "USDC",
      address: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85",
    },
  },
  bsc: {
    name: "BSC",
    explorerUrl: "https://bscscan.com/tokens",
    quoteToken: {
      symbol: "USDT",
      address: "0x55d398326f99059fF775485246999027B3197955",
    },
  },
  linea: {
    name: "Linea",
    explorerUrl: "https://lineascan.build/tokens",
    quoteToken: {
      symbol: "USDC",
      address: "0x176211869cA2b568f2A7D4EE941E073a821EE1ff",
    },
  },
};

// ── Global config ───────────────────────────────────────────────────────────

const PYTH_LAZER_SYMBOLS_URL =
  "https://history.pyth-lazer.dourolabs.app/history/v1/symbols";

const MAX_PAGES = process.env.MAX_PAGES
  ? parseInt(process.env.MAX_PAGES, 10)
  : 1;
const REQUEST_DELAY = parseInt(process.env.REQUEST_DELAY ?? "300", 10);
const DEBUG = process.env.DEBUG === "1";

const ENABLED_CHAINS = process.env.CHAINS
  ? process.env.CHAINS.split(",").map((s) => s.trim().toLowerCase())
  : Object.keys(CHAINS);

const SORT_CRITERIA = ["24h_volume_usd", "marketcap", /* "holders" */];

const HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
    "AppleWebKit/537.36 (KHTML, like Gecko) " +
    "Chrome/125.0.0.0 Safari/537.36",
  Accept:
    "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "en-US,en;q=0.9",
};

// ── Helpers ─────────────────────────────────────────────────────────────────

function log(msg) {
  process.stderr.write(msg + "\n");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function toChecksumAddress(raw) {
  try {
    return getAddress(raw);
  } catch {
    return null;
  }
}

// ── Step 1: Scrape explorer/tokens ──────────────────────────────────────────

async function scrapeBySortCriterion(explorerUrl, chainName, sortBy) {
  const tokens = new Map();
  let page = 1;

  while (true) {
    if (MAX_PAGES && page > MAX_PAGES) break;

    const url = new URL(explorerUrl);
    url.searchParams.set("sort", sortBy);
    url.searchParams.set("order", "desc");
    if (page > 1) url.searchParams.set("p", String(page));

    log(`  [${chainName}][sort=${sortBy}] Fetching page ${page} ...`);

    let html;
    try {
      const resp = await fetch(url.toString(), { headers: HEADERS });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      html = await resp.text();
    } catch (e) {
      log(`  [${chainName}][sort=${sortBy}] Request failed page ${page}: ${e.message}`);
      break;
    }

    const dom = new JSDOM(html);
    const doc = dom.window.document;
    const links = doc.querySelectorAll('a[href^="/token/0x"]');

    if (links.length === 0) {
      log(`  [${chainName}][sort=${sortBy}] No token links found, stopping.`);
      break;
    }

    let foundNew = false;

    for (const link of links) {
      const href = link.getAttribute("href") ?? "";
      const addrMatch = href.match(/\/token\/(0x[0-9a-fA-F]{40})/);
      if (!addrMatch) continue;

      const text = link.textContent?.trim() ?? "";
      const symMatch = text.match(/\(([^)]+)\)\s*$/);
      if (!symMatch) continue;

      const symbol = symMatch[1].trim();
      const name = text.replace(/\s*\([^)]*\)\s*$/, "").trim();
      const checksum = toChecksumAddress(addrMatch[1]);
      if (!checksum) continue;
      if (tokens.has(checksum)) continue;

      tokens.set(checksum, { symbol, name, address: checksum });
      foundNew = true;
    }

    if (!foundNew) break;

    const nextDisabled = doc.querySelector(
      'li.page-item.disabled > a[aria-label="Next"]'
    );
    const nextLink = doc.querySelector('a[aria-label="Next"]');
    if (nextDisabled || !nextLink) break;

    page++;
    await sleep(REQUEST_DELAY);
  }

  log(`  [${chainName}][sort=${sortBy}] Scraped ${tokens.size} unique tokens.`);
  return tokens;
}

async function scrapeTokens(explorerUrl, chainName) {
  const maps = [];

  for (const sortBy of SORT_CRITERIA) {
    const m = await scrapeBySortCriterion(explorerUrl, chainName, sortBy);
    maps.push(m);
    await sleep(REQUEST_DELAY);
  }

  const [first, ...rest] = maps;
  const intersection = [];

  for (const [addr, token] of first) {
    if (rest.every((m) => m.has(addr))) {
      intersection.push(token);
    }
  }

  log(`  [${chainName}] Intersection across ${SORT_CRITERIA.length} criteria: ${intersection.length} tokens.`);
  return intersection;
}

// ── Step 2: Pyth Lazer (cached) ─────────────────────────────────────────────

let pythCache = null;
let debugPrinted = false;

async function loadPythFeeds() {
  if (pythCache) return pythCache;

  log("[pyth] Loading all crypto symbols ...");
  const url = new URL(PYTH_LAZER_SYMBOLS_URL);
  url.searchParams.set("asset_type", "crypto");

  const resp = await fetch(url.toString(), {
    headers: {
      "User-Agent": HEADERS["User-Agent"],
      Accept: "application/json",
    },
  });
  if (!resp.ok) throw new Error(`Pyth API HTTP ${resp.status}`);
  const data = await resp.json();
  pythCache = Array.isArray(data) ? data : [data];
  log(`[pyth] Loaded ${pythCache.length} crypto feeds.`);
  return pythCache;
}

function extractPythLazerId(item) {
  for (const key of [
    "pyth_lazer_id",
    "id",
    "price_feed_id",
    "priceFeedId",
    "feed_id",
  ]) {
    const val = item[key];
    if (val !== undefined && val !== null) {
      const n = Number(val);
      if (!isNaN(n)) return n;
    }
  }
  return null;
}

function extractSymbolFromName(name) {
  if (name.includes(".") && name.includes("/")) {
    return name.split(".").pop().split("/")[0].toUpperCase();
  }
  if (name.includes("/")) {
    return name.split("/")[0].trim().toUpperCase();
  }
  return name.trim().toUpperCase();
}

function findPythFeed(symbol, items) {
  if (DEBUG && !debugPrinted && items.length > 0) {
    log(`  [pyth] DEBUG - Sample:\n${JSON.stringify(items[0], null, 2)}`);
    debugPrinted = true;
  }

  const upper = symbol.toUpperCase();
  for (const item of items) {
    const itemSymbol = String(item.symbol ?? "").toUpperCase();
    const baseFromSymbol = extractSymbolFromName(itemSymbol);
    if (baseFromSymbol === upper) return item;
  }
  return null;
}

// ── Step 3: Build output for a chain ────────────────────────────────────────

async function buildChainOutput(tokens, quoteToken, pythFeeds) {
  const results = [];
  const missed = [];
  const quoteAddress = toChecksumAddress(quoteToken.address);

  for (let i = 0; i < tokens.length; i++) {
    const { symbol, address } = tokens[i];
    log(`  [${i + 1}/${tokens.length}] ${symbol} ...`);

    const feed = findPythFeed(symbol, pythFeeds);
    if (!feed) {
      missed.push(symbol);
      log(`    ↳ No feed`);
      continue;
    }

    const pythLazerId = extractPythLazerId(feed);
    if (pythLazerId === null) {
      log(`    ↳ Feed found but no ID. Keys: ${Object.keys(feed).join(", ")}`);
      continue;
    }

    log(`    ↳ id=${pythLazerId}`);
    results.push({
      pythLazerId,
      baseTokenSymbol: symbol,
      quoteTokenSymbol: quoteToken.symbol,
      baseTokenAddress: address,
      quoteTokenAddress: quoteAddress,
    });
  }

  return [results, missed];
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  log("=".repeat(60));
  log("Multi-chain Etherscan → Pyth Lazer Token Mapper");
  log(`Chains: ${ENABLED_CHAINS.join(", ")}`);
  log("=".repeat(60));

  // Validate chain keys
  for (const key of ENABLED_CHAINS) {
    if (!CHAINS[key]) {
      log(`Unknown chain key: "${key}". Available: ${Object.keys(CHAINS).join(", ")}`);
      process.exit(1);
    }
  }

  // Load Pyth feeds once
  const pythFeeds = await loadPythFeeds();

  const summary = [];

  for (const key of ENABLED_CHAINS) {
    const chain = CHAINS[key];
    log(`\n${"─".repeat(60)}`);
    log(`Processing: ${chain.name} (${chain.explorerUrl})`);
    log("─".repeat(60));

    // Scrape
    const tokens = await scrapeTokens(chain.explorerUrl, chain.name);
    if (tokens.length === 0) {
      log(`  No tokens scraped for ${chain.name}, skipping.`);
      summary.push({ chain: chain.name, matched: 0, total: 0, missed: [] });
      continue;
    }

    // Match
    log(`  Matching ${tokens.length} tokens against Pyth Lazer ...`);
    const [results, missed] = await buildChainOutput(
      tokens,
      chain.quoteToken,
      pythFeeds
    );

    // Save to script/config/networks.json → .<chain>.feeds
    const networksPath = path.join(SCRIPT_DIR, "config", "networks.json");
    const networks = JSON.parse(fs.readFileSync(networksPath, "utf-8"));
    if (!networks[key]) networks[key] = {};
    networks[key].feeds = {
      oracle: "0x0000000000000000000000000000000000000000",
      tokens: results,
    };
    fs.writeFileSync(networksPath, JSON.stringify(networks, null, 2) + "\n");
    log(`  ✓ Saved ${results.length} entries → networks.json .${key}.feeds`);

    summary.push({
      chain: chain.name,
      matched: results.length,
      total: tokens.length,
      missed,
    });

    await sleep(REQUEST_DELAY);
  }

  // Summary
  log(`\n${"=".repeat(60)}`);
  log("SUMMARY");
  log("=".repeat(60));
  for (const s of summary) {
    log(`  ${s.chain.padEnd(12)} ${s.matched} / ${s.total} matched`);
    if (s.missed.length > 0) {
      log(`${"".padEnd(16)} missed: ${s.missed.join(", ")}`);
    }
  }
  log("=".repeat(60));
}

main().catch((e) => {
  log(`Fatal error: ${e.message}`);
  process.exit(1);
});
