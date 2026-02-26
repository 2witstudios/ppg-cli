"use client";

import { useState } from "react";
import Link from "next/link";
import {
  Monitor,
  GitBranch,
  Cpu,
  Layers,
  Bot,
  Clock,
  Terminal,
  ArrowRight,
  Copy,
  Check,
  X,
  Zap,
  ChevronRight,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <button
      onClick={() => {
        navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }}
      className="text-muted-foreground hover:text-foreground transition-colors"
      aria-label="Copy to clipboard"
    >
      {copied ? <Check className="size-4" /> : <Copy className="size-4" />}
    </button>
  );
}

function NpmInstallBlock() {
  return (
    <div className="flex items-center gap-3 rounded-lg border bg-muted/50 px-4 py-3 font-mono text-sm">
      <span className="text-muted-foreground select-none">$</span>
      <code className="bg-transparent p-0 flex-1">npm install -g ppg-cli</code>
      <CopyButton text="npm install -g ppg-cli" />
    </div>
  );
}

const WITHOUT_PPG = [
  "One agent, one task at a time",
  "Context switching between branches manually",
  "No visibility into what agents are doing",
  "Merge conflicts from uncoordinated work",
];

const WITH_PPG = [
  "Multiple agents working in parallel",
  "Isolated worktrees — zero branch conflicts",
  "Real-time dashboard monitoring every agent",
  "Clean squash merges back to your base branch",
];

const FEATURES = [
  {
    icon: Monitor,
    title: "Native Dashboard",
    description:
      "A macOS app that shows every agent's status, logs, and progress in real time. No terminal juggling.",
  },
  {
    icon: GitBranch,
    title: "Worktree Isolation",
    description:
      "Every agent gets its own git worktree and branch. No stepping on each other's code.",
  },
  {
    icon: Cpu,
    title: "Agent Agnostic",
    description:
      "Works with Claude Code, Codex, Aider, or any CLI tool. Bring your own agent.",
  },
  {
    icon: Layers,
    title: "Swarms",
    description:
      "Predefined multi-agent templates for common workflows like code review, refactoring, and test generation.",
  },
  {
    icon: Bot,
    title: "Conductor Mode",
    description:
      "Let an AI agent orchestrate other AI agents. Plan, spawn, monitor, and merge — fully automated.",
  },
  {
    icon: Clock,
    title: "Scheduling",
    description:
      "Cron-based recurring tasks. Run nightly test suites, weekly dependency updates, or daily code audits.",
  },
];

const STEPS = [
  {
    number: "1",
    title: "Init",
    description: "Initialize PPG in any git repository",
    command: "ppg init",
  },
  {
    number: "2",
    title: "Spawn",
    description: "Spawn agents with isolated worktrees",
    command: 'ppg spawn --name auth --prompt "Add user auth"',
  },
  {
    number: "3",
    title: "Merge",
    description: "Squash merge when the agent finishes",
    command: "ppg merge auth",
  },
];

export default function Home() {
  return (
    <div className="flex flex-col">
      {/* ─── Hero ─── */}
      <section className="py-20 sm:py-32">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <div className="flex flex-col items-center text-center">
            <Badge variant="secondary" className="mb-6">
              <Terminal className="size-3" />
              Open Source CLI Tool
            </Badge>

            <h1 className="text-4xl font-bold tracking-tight sm:text-5xl lg:text-6xl">
              Orchestrate AI Agents
              <br />
              in Parallel
            </h1>

            <p className="mt-6 max-w-2xl text-lg text-muted-foreground sm:text-xl">
              PPG is a local orchestration runtime that spawns, monitors, and
              merges AI coding agents across isolated git worktrees — driven
              from a native macOS dashboard.
            </p>

            <div className="mt-10 flex flex-col items-center gap-4 sm:flex-row">
              <Button size="lg" asChild>
                <Link href="/download">
                  Download
                  <ArrowRight />
                </Link>
              </Button>
              <Button variant="outline" size="lg" asChild>
                <a
                  href="https://github.com/jonfleming/ppg-cli"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  View on GitHub
                </a>
              </Button>
            </div>

            <div className="mt-8 w-full max-w-md">
              <NpmInstallBlock />
            </div>

            <div className="mt-16 w-full max-w-4xl">
              <div className="flex aspect-video items-center justify-center rounded-xl border bg-muted">
                <span className="text-muted-foreground">
                  Dashboard Preview
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <Separator className="mx-auto max-w-7xl" />

      {/* ─── Problem / Solution ─── */}
      <section className="py-16 sm:py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <div className="text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              From Sequential to Parallel
            </h2>
            <p className="mt-4 text-muted-foreground text-lg">
              Stop waiting. Start shipping.
            </p>
          </div>

          <div className="mt-12 grid grid-cols-1 gap-8 md:grid-cols-2">
            <Card className="border-dashed">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <X className="size-5 text-muted-foreground" />
                  Without PPG
                </CardTitle>
                <CardDescription>
                  The traditional one-at-a-time workflow
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="space-y-3">
                  {WITHOUT_PPG.map((point) => (
                    <li
                      key={point}
                      className="flex items-start gap-3 text-sm text-muted-foreground"
                    >
                      <span className="mt-1.5 block size-1.5 shrink-0 rounded-full bg-muted-foreground/40" />
                      {point}
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>

            <Card className="border-primary/30">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Zap className="size-5 text-primary" />
                  With PPG
                </CardTitle>
                <CardDescription>
                  Parallel agents, clean merges, full visibility
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="space-y-3">
                  {WITH_PPG.map((point) => (
                    <li
                      key={point}
                      className="flex items-start gap-3 text-sm"
                    >
                      <Check className="mt-0.5 size-4 shrink-0 text-primary" />
                      {point}
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          </div>
        </div>
      </section>

      <Separator className="mx-auto max-w-7xl" />

      {/* ─── Features Grid ─── */}
      <section className="py-16 sm:py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <div className="text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Everything You Need
            </h2>
            <p className="mt-4 text-muted-foreground text-lg">
              A complete toolkit for parallel AI agent orchestration.
            </p>
          </div>

          <div className="mt-12 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {FEATURES.map((feature) => (
              <Card key={feature.title}>
                <CardHeader>
                  <feature.icon className="size-5 text-primary" />
                  <CardTitle className="text-base">{feature.title}</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground">
                    {feature.description}
                  </p>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </section>

      <Separator className="mx-auto max-w-7xl" />

      {/* ─── How It Works ─── */}
      <section className="py-16 sm:py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <div className="text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Three Simple Steps
            </h2>
            <p className="mt-4 text-muted-foreground text-lg">
              From zero to parallel agents in under a minute.
            </p>
          </div>

          <div className="mt-12 grid grid-cols-1 gap-8 md:grid-cols-3">
            {STEPS.map((step, i) => (
              <div key={step.number} className="relative flex flex-col">
                {/* Connector line — hidden on mobile, visible on md+ */}
                {i < STEPS.length - 1 && (
                  <div className="absolute right-0 top-6 hidden h-px w-8 translate-x-full bg-border md:block" />
                )}

                <Badge
                  variant="outline"
                  className="mb-4 size-8 justify-center rounded-full text-sm"
                >
                  {step.number}
                </Badge>

                <h3 className="text-lg font-semibold">{step.title}</h3>
                <p className="mt-1 text-sm text-muted-foreground">
                  {step.description}
                </p>

                <div className="mt-4 rounded-lg border bg-muted/50 px-4 py-3 font-mono text-sm">
                  <span className="text-muted-foreground select-none">$ </span>
                  {step.command}
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <Separator className="mx-auto max-w-7xl" />

      {/* ─── Bottom CTA ─── */}
      <section className="py-16 sm:py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <div className="flex flex-col items-center text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Get Started in Seconds
            </h2>
            <p className="mt-4 text-muted-foreground text-lg">
              Install the CLI globally and start orchestrating.
            </p>

            <div className="mt-8 w-full max-w-md">
              <NpmInstallBlock />
            </div>

            <div className="mt-8 flex flex-col items-center gap-4 sm:flex-row">
              <Button variant="outline" size="lg" asChild>
                <Link href="/docs">
                  Read the Docs
                  <ChevronRight />
                </Link>
              </Button>
              <Button variant="outline" size="lg" asChild>
                <Link href="/download">
                  Download Dashboard
                  <ArrowRight />
                </Link>
              </Button>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
