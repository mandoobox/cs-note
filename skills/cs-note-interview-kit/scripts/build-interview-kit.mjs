#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

function parseArgs(argv) {
  const opts = {
    root: ".",
    topics: [],
    questionsPerSection: 3,
    maxSectionsPerFile: 12,
    output: "interview-kit.json",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--root" || arg === "-r") {
      i += 1;
      if (i >= argv.length) throw new Error("Missing value for --root");
      opts.root = argv[i];
      continue;
    }
    if (arg === "--topics") {
      i += 1;
      if (i >= argv.length) throw new Error("Missing value for --topics");
      const parts = argv[i].split(",").map((item) => item.trim()).filter(Boolean);
      opts.topics.push(...parts);
      continue;
    }
    if (arg === "--questions-per-section") {
      i += 1;
      if (i >= argv.length) throw new Error("Missing value for --questions-per-section");
      opts.questionsPerSection = Number.parseInt(argv[i], 10);
      continue;
    }
    if (arg === "--max-sections-per-file") {
      i += 1;
      if (i >= argv.length) throw new Error("Missing value for --max-sections-per-file");
      opts.maxSectionsPerFile = Number.parseInt(argv[i], 10);
      continue;
    }
    if (arg === "--output" || arg === "-o") {
      i += 1;
      if (i >= argv.length) throw new Error("Missing value for --output");
      opts.output = argv[i];
      continue;
    }
    if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  if (!Number.isInteger(opts.questionsPerSection) || opts.questionsPerSection < 1 || opts.questionsPerSection > 10) {
    throw new Error("--questions-per-section must be an integer between 1 and 10");
  }
  if (!Number.isInteger(opts.maxSectionsPerFile) || opts.maxSectionsPerFile < 1 || opts.maxSectionsPerFile > 50) {
    throw new Error("--max-sections-per-file must be an integer between 1 and 50");
  }

  return opts;
}

function printHelp() {
  console.log([
    "Usage: node build-interview-kit.mjs [options]",
    "  --root <path>",
    "  --topics <comma-separated>",
    "  --questions-per-section <1..10>",
    "  --max-sections-per-file <1..50>",
    "  --output <path>",
  ].join("\n"));
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
      if (!entry.isFile()) continue;
      if (!entry.name.toLowerCase().endsWith(".md")) continue;
      if (entry.name.toLowerCase() === "readme.md") continue;
      files.push(entryPath);
    }
  }
  walk(rootDir);
  return files;
}

function getSectionBlocks(content) {
  const matches = [...content.matchAll(/^##\s+(.+)$/gm)];
  const sections = [];
  for (let i = 0; i < matches.length; i += 1) {
    const current = matches[i];
    const start = (current.index ?? 0) + current[0].length;
    const end = i < matches.length - 1 ? (matches[i + 1].index ?? content.length) : content.length;
    const body = content.slice(start, end).trim();
    sections.push({ title: current[1].trim(), body });
  }
  return sections;
}

function getSectionSummary(body) {
  const lines = body.split(/\r?\n/);
  const clean = lines
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .filter((line) => !line.startsWith("```"))
    .filter((line) => !line.startsWith("|"))
    .filter((line) => !/^[-*]\s*$/.test(line))
    .slice(0, 3);
  const summary = clean.join(" ").trim();
  if (summary.length === 0) {
    return "Read the section directly and extract key definitions, tradeoffs, and failure modes.";
  }
  if (summary.length > 220) {
    return `${summary.slice(0, 220)}...`;
  }
  return summary;
}

function questionTemplates() {
  return [
    {
      type: "concept",
      difficulty: "medium",
      prompt: "Explain the core idea of '{section}' in {topic}, then state one practical implementation constraint.",
      followUp: "If the chosen approach fails under high scale, what exact metric fails first and why?",
    },
    {
      type: "tradeoff",
      difficulty: "medium-hard",
      prompt: "Compare '{section}' with its nearest alternative in {topic}. Describe decision criteria with one concrete example.",
      followUp: "What hidden cost is usually missed during the first design review?",
    },
    {
      type: "scenario",
      difficulty: "hard",
      prompt: "Given a production incident related to '{section}' in {topic}, outline a triage-first response plan.",
      followUp: "Which observation would make you change the initial hypothesis immediately?",
    },
    {
      type: "recall",
      difficulty: "easy-medium",
      prompt: "List the minimum key points an interviewer expects for '{section}' in under 60 seconds.",
      followUp: "Which one point is most frequently confused, and how do you disambiguate it quickly?",
    },
  ];
}

function renderTemplate(text, topic, section) {
  return text.replaceAll("{topic}", topic).replaceAll("{section}", section);
}

function run() {
  const options = parseArgs(process.argv.slice(2));
  const rootPath = path.resolve(options.root);
  let files = collectMarkdownFiles(rootPath);
  if (options.topics.length > 0) {
    const topicSet = new Set(options.topics.map((item) => item.toLowerCase()));
    files = files.filter((filePath) => topicSet.has(path.parse(filePath).name.toLowerCase()));
  }

  if (files.length === 0) {
    throw new Error("No matching markdown files found.");
  }

  files.sort((a, b) => a.localeCompare(b));
  const templates = questionTemplates();
  const entries = [];
  let totalQuestions = 0;

  for (const filePath of files) {
    const content = fs.readFileSync(filePath, "utf8");
    const sections = getSectionBlocks(content).slice(0, options.maxSectionsPerFile);
    const topic = path.parse(filePath).name;
    const relative = path.relative(rootPath, filePath);

    for (const section of sections) {
      const questions = [];
      for (let i = 0; i < options.questionsPerSection; i += 1) {
        const template = templates[i % templates.length];
        questions.push({
          question_type: template.type,
          difficulty: template.difficulty,
          prompt: renderTemplate(template.prompt, topic, section.title),
          follow_up: renderTemplate(template.followUp, topic, section.title),
          rubric: [
            "State the correct core concept with precise terminology.",
            "Explain tradeoffs or limits instead of listing features only.",
            "Use one concrete example or metric to justify claims.",
            "Communicate with short structure: claim -> reason -> example.",
          ],
        });
        totalQuestions += 1;
      }

      entries.push({
        topic,
        section: section.title,
        section_digest: getSectionSummary(section.body),
        source: relative,
        questions,
      });
    }
  }

  const result = {
    generated_at: new Date().toISOString(),
    root: rootPath,
    files: files.map((filePath) => path.relative(rootPath, filePath)),
    questions_per_entry: options.questionsPerSection,
    total_entries: entries.length,
    total_questions: totalQuestions,
    entries,
  };

  const outputPath = path.resolve(rootPath, options.output);
  fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, "utf8");
  console.log(`Generated interview kit: ${outputPath}`);
  console.log(`Entries: ${entries.length}, Questions: ${totalQuestions}`);
}

try {
  run();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
