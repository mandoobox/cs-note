#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const severityRank = { ERROR: 0, WARN: 1, INFO: 2 };

function parseArgs(argv) {
  const opts = {
    root: ".",
    fix: false,
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
    if (arg === "--fix") {
      opts.fix = true;
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
  console.log("Usage: node lint-cs-notes.mjs [--root <path>] [--fix] [--json-out <path>]");
}

function collectMarkdownFiles(rootDir) {
  const files = [];

  function walk(currentDir) {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true });
    for (const entry of entries) {
      const entryPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === ".git" || entry.name === "skills") {
          continue;
        }
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

function lineNumberFromIndex(content, index) {
  if (index <= 0) return 1;
  let count = 1;
  for (let i = 0; i < index; i += 1) {
    if (content[i] === "\n") count += 1;
  }
  return count;
}

function resolveLocalLink(filePath, linkTarget) {
  const target = linkTarget.split("#")[0].trim();
  if (!target) return null;
  if (/^(https?:|mailto:|obsidian:|#)/i.test(target)) return null;
  return path.resolve(path.dirname(filePath), target);
}

function run() {
  const options = parseArgs(process.argv.slice(2));
  const rootPath = path.resolve(options.root);
  const files = collectMarkdownFiles(rootPath);
  const issues = [];

  function addIssue(severity, rule, filePath, line, message) {
    issues.push({ severity, rule, path: filePath, line, message });
  }

  for (const filePath of files) {
    const original = fs.readFileSync(filePath, "utf8");
    const lineEnding = original.includes("\r\n") ? "\r\n" : "\n";
    const lines = original.split(/\r?\n/);
    let changed = false;

    const hasFrontMatter = lines.length > 0 && lines[0].trim() === "---";
    let frontMatterEnd = -1;

    if (hasFrontMatter) {
      for (let i = 1; i < lines.length; i += 1) {
        if (lines[i].trim() === "---") {
          frontMatterEnd = i;
          break;
        }
      }

      if (frontMatterEnd < 0) {
        addIssue("ERROR", "frontmatter.unclosed", filePath, 1, "Frontmatter starts but does not close with '---'.");
      } else {
        const frontMatterLines = lines.slice(1, frontMatterEnd);
        for (const field of ["title", "date", "category", "tags"]) {
          const fieldRe = new RegExp(`^\\s*${field}\\s*:`);
          const hasField = frontMatterLines.some((line) => fieldRe.test(line));
          if (!hasField) {
            addIssue("WARN", "frontmatter.required", filePath, 1, `Missing '${field}' in frontmatter.`);
          }
        }

        for (let i = 1; i < frontMatterEnd; i += 1) {
          const tagMatch = lines[i].match(/^\s*tags\s*:\s*\[(.+)\]\s*$/);
          if (!tagMatch) continue;
          if (/\bdatsstructure\b/.test(tagMatch[1])) {
            addIssue("WARN", "tags.typo", filePath, i + 1, "Found 'datsstructure'. Replace with 'datastructure'.");
            if (options.fix) {
              const updated = lines[i].replace(/\bdatsstructure\b/g, "datastructure");
              if (updated !== lines[i]) {
                lines[i] = updated;
                changed = true;
              }
            }
          }
        }
      }
    } else if (path.basename(filePath).toLowerCase() !== "readme.md") {
      addIssue("WARN", "frontmatter.missing", filePath, 1, "Missing frontmatter block.");
    }

    const linkRe = /\[[^\]]+\]\(([^)]+)\)/g;
    let linkMatch;
    while ((linkMatch = linkRe.exec(original)) !== null) {
      const target = linkMatch[1].trim();
      if (/^(https?:|mailto:|obsidian:|#)/i.test(target)) continue;
      const resolved = resolveLocalLink(filePath, target);
      if (!resolved) continue;
      if (!fs.existsSync(resolved)) {
        addIssue("WARN", "link.missing", filePath, lineNumberFromIndex(original, linkMatch.index), `Missing local target: ${target}`);
      }
    }

    const numberedMatches = [...original.matchAll(/^##\s+(\d+)\./gm)];
    for (let i = 0; i < numberedMatches.length; i += 1) {
      const expected = i + 1;
      const actual = Number.parseInt(numberedMatches[i][1], 10);
      if (actual !== expected) {
        const line = lineNumberFromIndex(original, numberedMatches[i].index ?? 0);
        addIssue("WARN", "heading.h2-numbering", filePath, line, `Expected section number ${expected} but found ${actual}.`);
        break;
      }
    }

    const badIdx = original.indexOf("\uFFFD");
    if (badIdx >= 0) {
      addIssue("WARN", "text.mojibake", filePath, lineNumberFromIndex(original, badIdx), "Found replacement character U+FFFD.");
    }

    if (/[\x00-\x08\x0B\x0C\x0E-\x1F]/.test(original)) {
      addIssue("ERROR", "text.control-char", filePath, 1, "Found non-whitespace control character.");
    }

    if (options.fix && changed) {
      fs.writeFileSync(filePath, lines.join(lineEnding), "utf8");
    }
  }

  issues.sort((a, b) => {
    const rankDiff = severityRank[a.severity] - severityRank[b.severity];
    if (rankDiff !== 0) return rankDiff;
    if (a.path !== b.path) return a.path.localeCompare(b.path);
    return a.line - b.line;
  });

  for (const issue of issues) {
    console.log(`[${issue.severity}] ${issue.rule} ${issue.path}:${issue.line} - ${issue.message}`);
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
  console.log("No issues found.");
  process.exit(0);
}

try {
  run();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(2);
}
