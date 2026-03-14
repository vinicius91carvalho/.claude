# Introduction

## What Is Claude Code?

Claude Code is a command-line tool (CLI) by Anthropic that lets you interact with the Claude AI model directly from your terminal for software development tasks. Unlike a chatbot, Claude Code can read files, edit code, run shell commands, navigate your file system, and delegate tasks to sub-agents — all autonomously or semi-autonomously.

When you open Claude Code in any project directory, it automatically loads a file called `CLAUDE.md`. This file acts as permanent instructions — everything in it is read by Claude at the start of every session, functioning as long-term memory for that specific project.

## The Problem This System Solves

Imagine opening Claude Code every day and having to explain everything from scratch: "use pnpm not npm", "run tests before committing", "don't delete passing tests". This is exhausting and inefficient.

The `~/.claude/` repository solves this by creating a **portable engineering system** that lives in your home directory. When you clone it to `~/.claude/`, it applies **automatically to every project** you open with Claude Code. Whether it's a Next.js app, a Python backend, or a Go API — the workflow, safety rules, and specialized agents are always available.

Think of it as the difference between a junior developer who follows one-off instructions and a senior engineer with a refined personal system built over years. This repository is that personal system — codified in files that Claude Code understands.

## The Core Philosophy: Compound Engineering

The opening line of the main `CLAUDE.md` says:

> "Each unit of work must make subsequent units easier — not harder."

This is **Compound Engineering** — engineering that compounds, like compound interest. Each task the AI agent completes not only delivers the requested result, but also **improves the system itself** so the next task is easier, faster, and has fewer errors.

The cycle has four steps:

```
                    ┌──────────────┐
                    │     PLAN     │ ◄── Understand & document
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │     WORK     │ ◄── Implement the code
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │    REVIEW    │ ◄── Verify correctness
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   COMPOUND   │ ◄── Capture learnings,
                    └──────┬───────┘     improve the system
                           │
                           ▼
                    ┌──────────────┐
               ┌───►│  NEXT TASK   │ ◄── Now easier because
               │    └──────────────┘     the system improved
               │           │
               └───────────┘
```

The key insight is step four — **Compound**. Without it, you have "traditional engineering with AI assistance." With it, you have a system that **evolves with every use**.

## Effort Distribution

The recommended split: **Plan + Review = 80%** of effort, **Work + Compound = 20%**.

This sounds counterintuitive — why spend more time planning and reviewing than coding? Because with AI agents, the bottleneck is not typing speed. The bottleneck is knowing **what** to build and **verifying** it was built correctly. If you plan well and review well, implementation becomes almost mechanical — perfect for delegating to an AI agent.

## Influences & References

This system is primarily shaped by hands-on experience building production software with AI agents, combined with ideas from:

- **[Compound Engineering](https://every.to/source-code/compound-engineering-the-definitive-guide)** — The methodology developed by [Every, Inc.](https://every.to/guides/compound-engineering) where each unit of work improves the system for the next. The Plan → Work → Review → Compound loop and the 80/20 split come from here. See also the [official Claude Code plugin](https://github.com/EveryInc/compound-engineering-plugin).
- **[Context Engineering](https://x.com/karpathy/status/1937902205765607626)** — The discipline of structuring everything an LLM needs to make reliable decisions, as articulated by [Andrej Karpathy](https://x.com/karpathy/status/1937902205765607626) and [Tobi Lütke](https://x.com/tobi/status/1935533422589399127). The agent architecture, worktree isolation, context budget rules, and context rot protocols are context engineering in practice.
- **The AI-Human Engineering Stack** (Mill & Sanchez, 2026) — A layered model (Prompt, Context, Intent, Judgment, Coherence) that informed the value hierarchy, judgment protocols, and evaluation framework.
- **The Complete Guide to Specifying Work for AI** (Mill & Sanchez, 2026) — Practical methods for translating human intent into AI-readable specifications that shaped the Contract-First pattern, Correctness Discovery, and PRD templates.
- **Personal experience** — Patterns, anti-patterns, hooks, and safety rules discovered through months of real-world AI-assisted development across multiple production projects.

The repository turns these concepts into a working system with real files, hooks, and agents.

---

Next: [Getting Started](02-getting-started.md)
