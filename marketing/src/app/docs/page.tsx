import Link from "next/link"
import { ArrowRight, BookOpen, Bot, Layers, Monitor, Terminal } from "lucide-react"

import { Separator } from "@/components/ui/separator"
import { Card, CardContent } from "@/components/ui/card"

export default function DocsGettingStarted() {
  return (
    <div className="space-y-12">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
          Getting Started
        </h1>
        <p className="mt-2 text-lg text-muted-foreground">
          Get up and running with PPG in under 5 minutes.
        </p>
      </div>

      <Separator />

      {/* Prerequisites */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">Prerequisites</h2>
        <ul className="list-inside list-disc space-y-2 text-muted-foreground">
          <li>macOS (Apple Silicon or Intel)</li>
          <li>Node.js 20+</li>
          <li>git</li>
          <li>
            tmux &mdash; install via{" "}
            <code>brew install tmux</code>
          </li>
        </ul>
      </section>

      <Separator />

      {/* Installation */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">Installation</h2>
        <p className="text-muted-foreground">
          Install PPG globally with npm:
        </p>
        <pre>
          <code>npm install -g ppg-cli</code>
        </pre>
        <p className="text-muted-foreground">
          Verify the installation:
        </p>
        <pre>
          <code>ppg --version</code>
        </pre>
      </section>

      <Separator />

      {/* Initialize */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">
          Initialize Your Project
        </h2>
        <p className="text-muted-foreground">
          Navigate to a git repository and initialize PPG:
        </p>
        <pre>
          <code>{`cd your-project\nppg init`}</code>
        </pre>
        <p className="text-muted-foreground">
          This creates a <code>.ppg/</code> directory containing:
        </p>
        <ul className="list-inside list-disc space-y-2 text-muted-foreground">
          <li>
            <code>config.yaml</code> &mdash; session name, agent definitions,
            directory paths
          </li>
          <li>
            <code>manifest.json</code> &mdash; runtime state tracking for
            worktrees and agents
          </li>
        </ul>
      </section>

      <Separator />

      {/* Spawn */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">
          Spawn Your First Agent
        </h2>
        <pre>
          <code>ppg spawn --name my-feature --prompt &apos;Add user authentication&apos;</code>
        </pre>
        <p className="text-muted-foreground">This command:</p>
        <ul className="list-inside list-disc space-y-2 text-muted-foreground">
          <li>Creates an isolated git worktree on a new branch</li>
          <li>Starts a Claude Code agent in a tmux pane</li>
          <li>Passes your prompt to the agent as its task</li>
        </ul>
        <Card className="border-dashed">
          <CardContent className="py-4 text-sm text-muted-foreground">
            Each agent works in its own branch, so you can spawn multiple agents
            in parallel without conflicts.
          </CardContent>
        </Card>
      </section>

      <Separator />

      {/* Dashboard */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">
          Open the Dashboard
        </h2>
        <pre>
          <code>ppg ui</code>
        </pre>
        <p className="text-muted-foreground">
          Opens the native macOS dashboard app for visual monitoring of your
          running agents, their status, and outputs. You can also use{" "}
          <code>ppg dashboard</code> as an alias.
        </p>
      </section>

      <Separator />

      {/* Status */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">Check Status</h2>
        <pre>
          <code>ppg status</code>
        </pre>
        <p className="text-muted-foreground">
          Displays a table of all active worktrees and their agents, including
          current status (<code>running</code>, <code>completed</code>,{" "}
          <code>failed</code>), branch names, and tmux targets.
        </p>
      </section>

      <Separator />

      {/* Merge */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">
          Merge Your Work
        </h2>
        <pre>
          <code>{`ppg merge <worktree-id>`}</code>
        </pre>
        <p className="text-muted-foreground">
          Squash-merges the agent&apos;s branch back to your base branch,
          then cleans up the worktree, tmux pane, and temporary branch. Your
          agent&apos;s work is now part of your main codebase.
        </p>
      </section>

      <Separator />

      {/* Next Steps */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">Next Steps</h2>
        <p className="text-muted-foreground">
          Now that you have the basics, dive deeper:
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          {[
            {
              href: "/docs/concepts",
              label: "Concepts",
              description: "Worktrees, agents, manifests, and the lifecycle",
              icon: Layers,
            },
            {
              href: "/docs/cli",
              label: "CLI Reference",
              description: "Every command, flag, and option",
              icon: Terminal,
            },
            {
              href: "/docs/dashboard",
              label: "Dashboard Guide",
              description: "Visual monitoring with the macOS app",
              icon: Monitor,
            },
            {
              href: "/docs/conductor",
              label: "Conductor Mode",
              description: "Orchestrate agents programmatically",
              icon: Bot,
            },
          ].map(({ href, label, description, icon: Icon }) => (
            <Link key={href} href={href}>
              <Card className="group transition-colors hover:border-foreground/20">
                <CardContent className="flex items-start gap-3 py-4">
                  <Icon className="mt-0.5 size-5 shrink-0 text-muted-foreground" />
                  <div className="min-w-0">
                    <p className="font-medium flex items-center gap-1">
                      {label}
                      <ArrowRight className="size-3 opacity-0 transition-opacity group-hover:opacity-100" />
                    </p>
                    <p className="text-sm text-muted-foreground">
                      {description}
                    </p>
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      </section>
    </div>
  )
}
