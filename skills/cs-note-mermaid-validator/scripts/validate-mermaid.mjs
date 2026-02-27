#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const knownStarters = new Set([
  "flowchart",
  "graph",
  "sequenceDiagram",
  "classDiagram",
  "stateDiagram",
  "stateDiagram-v2",
  "erDiagram",
  "journey",
  "gantt",
  "pie",
  "mindmap",
  "timeline",
  "quadrantChart",
  "requirementDiagram",
  "gitGraph",
  "C4Context",
  "C4Container",
  "C4Component",
  "C4Dynamic",
  "C4Deployment",
  "sankey-beta",
  "xychart-beta",
  "block-beta",
  "packet-beta",
]);

const severityRank = { ERROR: 0, WARN: 1, INFO: 2 };

function parseArgs(argv) {
  const opts = {
    root: ".",
    autoFix: false,
    jsonOut: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--root" || arg === "-r") {
      i += 1;
      if (i >= argv.length) throw new Error("Missing value for --root");
      opts.root = argv[i];
      continue;
    }
    if (arg === "--auto-fix") {
      opts.autoFix = true;
      continue;
    }
    if (arg === "--json-out") {
      i += 1;
      if (i >= argv.length) throw new Error("Missing value for --json-out");
      opts.jsonOut = argv[i];
      continue;
    }
    if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    }
    throw new Error(`Unknown argument: ${arg}`);
  }
  return opts;
}

function printHelp() {
  console.log("Usage: node validate-mermaid.mjs [--root <path>] [--auto-fix] [--json-out <path>]");
}

function collectMarkdownFiles(rootDir) {
  const files = [];
  function walk(currentDir) {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true });
    for (const entry of entries) {
      const entryPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === ".git" || entry.name === "skills") continue;
        walk(entryPath);
        continue;
      }
      if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) {
        files.push(entryPath);
      }
    }
  }
  walk(rootDir);
  return files;
}

function bracketImbalance(text, openChar, closeChar) {
  let balance = 0;
  for (const char of text) {
    if (char === openChar) balance += 1;
    if (char === closeChar) balance -= 1;
  }
  return balance;
}

function validateBlock(blockLines, filePath, blockStart, options, issues) {
  let changed = false;
  const fixed = [];

  const addIssue = (severity, rule, line, message) => {
    issues.push({ severity, rule, path: filePath, blockStart, line, message });
  };

  for (let i = 0; i < blockLines.length; i += 1) {
    const original = blockLines[i];
    let next = original;
    if (next.includes("\t")) {
      addIssue("WARN", "mermaid.tab", blockStart + i + 1, "Tab character found in Mermaid block.");
      if (options.autoFix) {
        next = next.replace(/\t/g, "  ");
      }
    }

    const trimmed = next.replace(/[ \t]+$/g, "");
    if (trimmed.length !== next.length) {
      if (options.autoFix) {
        next = trimmed;
      } else {
        addIssue("INFO", "mermaid.trailing-space", blockStart + i + 1, "Trailing whitespace found.");
      }
    }

    if (next !== original) changed = true;
    fixed.push(next);
  }

  const firstNonEmpty = fixed.findIndex((line) => line.trim().length > 0);
  if (firstNonEmpty < 0) {
    addIssue("ERROR", "mermaid.empty", blockStart, "Empty Mermaid block.");
    return { lines: fixed, changed };
  }

  const starter = fixed[firstNonEmpty].trim().split(/\s+/)[0];
  if (!knownStarters.has(starter)) {
    addIssue("ERROR", "mermaid.starter", blockStart + firstNonEmpty + 1, `Unknown Mermaid starter token '${starter}'.`);
  }

  const fullText = fixed.join("\n");
  if (bracketImbalance(fullText, "(", ")") !== 0) {
    addIssue("WARN", "mermaid.bracket-round", blockStart, "Possible imbalance in round brackets.");
  }
  if (bracketImbalance(fullText, "[", "]") !== 0) {
    addIssue("WARN", "mermaid.bracket-square", blockStart, "Possible imbalance in square brackets.");
  }
  if (bracketImbalance(fullText, "{", "}") !== 0) {
    addIssue("WARN", "mermaid.bracket-curly", blockStart, "Possible imbalance in curly braces.");
  }

  const quoteCount = (fullText.match(/(?<!\\)"/g) ?? []).length;
  if (quoteCount % 2 !== 0) {
    addIssue("WARN", "mermaid.quote", blockStart, "Odd count of unescaped double quotes.");
  }

  const subgraphCount = (fullText.match(/^\s*subgraph\b/gm) ?? []).length;
  const endCount = (fullText.match(/^\s*end\s*$/gm) ?? []).length;
  if (subgraphCount !== endCount) {
    addIssue("WARN", "mermaid.subgraph-balance", blockStart, `subgraph count (${subgraphCount}) does not match end count (${endCount}).`);
  }

  return { lines: fixed, changed };
}

function run() {
  const options = parseArgs(process.argv.slice(2));
  const rootPath = path.resolve(options.root);
  const files = collectMarkdownFiles(rootPath);
  const issues = [];

  for (const filePath of files) {
    const original = fs.readFileSync(filePath, "utf8");
    const lineEnding = original.includes("\r\n") ? "\r\n" : "\n";
    const lines = original.split(/\r?\n/);
    const outputLines = [];

    let inMermaid = false;
    let blockStart = 0;
    let blockLines = [];
    let changedFile = false;

    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i];
      const lineNumber = i + 1;

      if (!inMermaid) {
        if (/^\s*```mermaid\s*$/.test(line)) {
          inMermaid = true;
          blockStart = lineNumber;
          blockLines = [];
          outputLines.push(line);
        } else {
          outputLines.push(line);
        }
        continue;
      }

      if (/^\s*```\s*$/.test(line)) {
        const checked = validateBlock(blockLines, filePath, blockStart, options, issues);
        outputLines.push(...checked.lines);
        outputLines.push(line);
        if (checked.changed) changedFile = true;
        inMermaid = false;
        continue;
      }

      blockLines.push(line);
    }

    if (inMermaid) {
      issues.push({
        severity: "ERROR",
        rule: "mermaid.fence-unclosed",
        path: filePath,
        blockStart,
        line: blockStart,
        message: "Mermaid fence is not closed.",
      });
      outputLines.push(...blockLines);
    }

    if (options.autoFix && changedFile) {
      fs.writeFileSync(filePath, outputLines.join(lineEnding), "utf8");
    }
  }

  issues.sort((a, b) => {
    const rankDiff = severityRank[a.severity] - severityRank[b.severity];
    if (rankDiff !== 0) return rankDiff;
    if (a.path !== b.path) return a.path.localeCompare(b.path);
    if (a.blockStart !== b.blockStart) return a.blockStart - b.blockStart;
    return a.line - b.line;
  });

  for (const issue of issues) {
    console.log(`[${issue.severity}] ${issue.rule} ${issue.path}:${issue.blockStart}:${issue.line} - ${issue.message}`);
  }

  const errorCount = issues.filter((item) => item.severity === "ERROR").length;
  const warnCount = issues.filter((item) => item.severity === "WARN").length;
  const infoCount = issues.filter((item) => item.severity === "INFO").length;
  console.log(`Summary: ERROR=${errorCount}, WARN=${warnCount}, INFO=${infoCount}`);

  if (options.jsonOut) {
    const jsonPath = path.resolve(rootPath, options.jsonOut);
    fs.writeFileSync(jsonPath, `${JSON.stringify(issues, null, 2)}\n`, "utf8");
    console.log(`JSON report: ${jsonPath}`);
  }

  if (errorCount > 0) process.exit(2);
  if (issues.length > 0) process.exit(1);
  console.log("No Mermaid issues found.");
  process.exit(0);
}

try {
  run();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(2);
}
