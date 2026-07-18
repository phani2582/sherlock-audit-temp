#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const CODEBOOK_DIR = path.join(ROOT, "codebook");
const TARGET = path.join(ROOT, "contracts", "oracles", "utils", "Codebook256.sol");
const PLACEHOLDER_REGEX = /bytes\s+internal\s+constant\s+TABLE\s*=\s*hex"[0-9a-fA-F]*";/;

function readValues() {
  const entries = fs.readdirSync(CODEBOOK_DIR)
    .filter((file) => file.toLowerCase().endsWith(".json"))
    .sort();

  if (entries.length === 0) {
    throw new Error(`No JSON codebook files found in ${CODEBOOK_DIR}`);
  }

  const values = [];
  for (const file of entries) {
    const raw = fs.readFileSync(path.join(CODEBOOK_DIR, file), "utf8");
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      throw new Error(`Failed to parse ${file}: ${err.message}`);
    }

    if (!Array.isArray(parsed)) {
      throw new Error(`${file} does not contain an array`);
    }

    for (const value of parsed) {
      if (!Number.isInteger(value) || value < 0 || value > 0xffff) {
        throw new Error(`Invalid value ${value} in ${file}; expected uint16 range`);
      }
      values.push(value);
    }
  }

  return values;
}

function buildHex(values) {

  const arr = [
    ...(new Array(64).fill(0).map((_, i) => { return i.toString(16).padStart(4, "0") })),
    ...(new Array(64).fill(0).map((_, i) => { return (64 + i * 20).toString(16).padStart(4, "0") })),
    ...(new Array(64).fill(0).map((_, i) => { return ((64 + 64*20) + i * 50).toString(16).padStart(4, "0") })),
    ...(new Array(64).fill(0).map((_, i) => { return ((64 + 64*20 + 64*50) + i * 80).toString(16).padStart(4, "0") })),
  ]

  arr[255] = (10_000).toString(16).padStart(4, "0");

  console.log(JSON.stringify(arr.map((v) => parseInt(v, 16))))

  return arr.join("");

  // return values.map((value) => value.toString(16).padStart(4, "0")).join("");
}

function updateTarget(hexString) {
  const replacement = `bytes internal constant TABLE = hex"${hexString}";`;
  const source = fs.readFileSync(TARGET, "utf8");

  if (!PLACEHOLDER_REGEX.test(source)) {
    throw new Error(`Placeholder not found in ${TARGET}`);
  }

  const next = source.replace(PLACEHOLDER_REGEX, replacement);
  fs.writeFileSync(TARGET, next, "utf8");
}

function main() {
  const values = readValues();
  const hex = buildHex(values);
  updateTarget(hex);
  console.log(`Generated codebook with ${values.length} entries -> ${hex.length / 2} bytes.`);
}

main();
