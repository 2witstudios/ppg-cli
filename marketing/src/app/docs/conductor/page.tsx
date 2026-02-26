import { Bot, Cpu, Hash, Lightbulb, RefreshCw, Sparkles, Terminal, Zap } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"

export default function ConductorModePage() {
  return (
    <div className="space-y-12">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
          Conductor Mode
        </h1>
        <p className="mt-2 text-lg text-muted-foreground">
          AI orchestrating AI &mdash; autonomous multi-agent workflows
        </p>
      </div>

      {/* Table of Contents */}
      <Card className="border-dashed">
        <CardHeader>
          <CardTitle className="text-sm uppercase tracking-wider text-muted-foreground">
            On this page
          </CardTitle>
        </CardHeader>
        <CardContent className="pt-0">
          <nav className="flex flex-col gap-1.5 text-sm">
            <a href="#what-is-conductor-mode" className="text-muted-foreground transition-colors hover:text-foreground">
              What is Conductor Mode?
            </a>
            <a href="#two-modes" className="text-muted-foreground transition-colors hover:text-foreground">
              Two Modes
            </a>
            <a href="#the-conductor-loop" className="text-muted-foreground transition-colors hover:text-foreground">
              The Conductor Loop
            </a>
            <a href="#the-ppg-skill" className="text-muted-foreground transition-colors hover:text-foreground">
              The /ppg Skill
            </a>
            <a href="#custom-conductor-scripts" className="text-muted-foreground transition-colors hover:text-foreground">
              Custom Conductor Scripts
            </a>
            <a href="#agent-type-selection" className="text-muted-foreground transition-colors hover:text-foreground">
              Agent Type Selection
            </a>
            <a href="#error-handling" className="text-muted-foreground transition-colors hover:text-foreground">
              Error Handling
            </a>
            <a href="#best-practices" className="text-muted-foreground transition-colors hover:text-foreground">
              Best Practices
            </a>
          </nav>
        </CardContent>
      </Card>

      <Separator />

      {/* What is Conductor Mode? */}
      <section className="space-y-4" id="what-is-conductor-mode">
        <h2 className="text-2xl font-semibold tracking-tight">
          What is Conductor Mode?
        </h2>
        <p className="text-muted-foreground">
          A conductor is a <strong className="text-foreground">meta-agent</strong> that
          drives PPG programmatically. Instead of a human typing{" "}
          <code>ppg</code> commands, an AI agent does it.
        </p>
        <p className="text-muted-foreground">
          The conductor plans tasks, spawns agents, monitors progress, and merges
          results. Think of it as{" "}
          <strong className="text-foreground">
            an AI project manager directing AI developers
          </strong>
          .
        </p>
        <Card className="border-dashed">
          <CardContent className="flex items-start gap-3 py-4">
            <Lightbulb className="mt-0.5 size-5 shrink-0 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              A human defines the high-level goal. The conductor decomposes it,
              assigns work to parallel agents, and assembles the results &mdash;
              all without further human intervention.
            </p>
          </CardContent>
        </Card>
      </section>

      <Separator />

      {/* Two Modes */}
      <section className="space-y-6" id="two-modes">
        <h2 className="text-2xl font-semibold tracking-tight">Two Modes</h2>

        <div className="grid gap-4 sm:grid-cols-2">
          {/* Swarm Mode */}
          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <Sparkles className="size-5 text-muted-foreground" />
                <CardTitle>Swarm Mode</CardTitle>
              </div>
              <Badge variant="secondary">Repeatable</Badge>
            </CardHeader>
            <CardContent className="space-y-3 text-sm text-muted-foreground">
              <p>
                Uses <code>ppg swarm &lt;template&gt;</code> to run predefined
                multi-agent workflows. Great for repeatable patterns: code
                review, testing, documentation.
              </p>
              <p>
                Swarm templates define the agents, prompts, and worktree
                configuration upfront.
              </p>
              <div className="rounded-md bg-muted/50 px-3 py-2 font-mono text-xs">
                # Example: a &quot;review&quot; swarm that spawns 3 agents
                <br />
                ppg swarm review
                <br />
                # → security-reviewer, performance-reviewer, style-reviewer
              </div>
            </CardContent>
          </Card>

          {/* Batch Mode */}
          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <Zap className="size-5 text-muted-foreground" />
                <CardTitle>Batch Mode</CardTitle>
              </div>
              <Badge variant="secondary">Flexible</Badge>
            </CardHeader>
            <CardContent className="space-y-3 text-sm text-muted-foreground">
              <p>
                Uses <code>ppg spawn</code> repeatedly to create ad-hoc parallel
                work. The conductor breaks a task into subtasks and spawns an
                agent for each.
              </p>
              <p>
                More flexible than swarms &mdash; the conductor decides the
                decomposition at runtime.
              </p>
              <div className="rounded-md bg-muted/50 px-3 py-2 font-mono text-xs">
                # Example: &quot;Implement auth&quot; decomposed to:
                <br />
                ppg spawn --name login-page --prompt &apos;...&apos;
                <br />
                ppg spawn --name api-routes --prompt &apos;...&apos;
                <br />
                ppg spawn --name tests --prompt &apos;...&apos;
                <br />
                ppg spawn --name docs --prompt &apos;...&apos;
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      <Separator />

      {/* The Conductor Loop */}
      <section className="space-y-4" id="the-conductor-loop">
        <h2 className="text-2xl font-semibold tracking-tight">
          The Conductor Loop
        </h2>
        <p className="text-muted-foreground">
          The core algorithm every conductor follows, regardless of
          implementation:
        </p>

        <div className="space-y-3">
          {[
            {
              step: "1",
              label: "Plan",
              description:
                "Break the task into independent, parallelizable units",
              command: null,
            },
            {
              step: "2",
              label: "Spawn",
              description: "Create an agent for each unit of work",
              command: "ppg spawn --name <name> --prompt '<task>' --json",
            },
            {
              step: "3",
              label: "Poll",
              description:
                "Check for completed or failed agents every 5 seconds",
              command: "ppg status --json",
            },
            {
              step: "4",
              label: "Aggregate",
              description: "Collect result files from all completed agents",
              command: "ppg aggregate --all --json",
            },
            {
              step: "5",
              label: "Present",
              description:
                "Show results, PR links, and summaries to the user",
              command: null,
            },
            {
              step: "6",
              label: "Cleanup",
              description:
                "Remove worktrees (skips those with open PRs)",
              command: "ppg reset --json",
            },
          ].map(({ step, label, description, command }) => (
            <div
              key={step}
              className="flex items-start gap-4 rounded-lg border px-4 py-3"
            >
              <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-muted font-mono text-xs font-bold">
                {step}
              </span>
              <div className="min-w-0 flex-1">
                <p className="font-medium">
                  {label}{" "}
                  <span className="font-normal text-muted-foreground">
                    &mdash; {description}
                  </span>
                </p>
                {command && (
                  <pre className="mt-1.5 text-xs">
                    <code>{command}</code>
                  </pre>
                )}
              </div>
            </div>
          ))}
        </div>

        <p className="pt-2 text-sm font-medium text-muted-foreground">
          Pseudocode:
        </p>
        <pre>
          <code>{`function conductorLoop(goal) {
  // 1. Plan
  const tasks = decompose(goal)

  // 2. Spawn
  for (const task of tasks) {
    exec(\`ppg spawn --name \${task.name} --prompt '\${task.prompt}' --json\`)
  }

  // 3. Poll until all done
  while (true) {
    const status = JSON.parse(exec('ppg status --json'))
    const agents = status.worktrees.flatMap(w => w.agents)

    if (agents.every(a => a.status === 'completed' || a.status === 'failed')) {
      break
    }
    sleep(5000)
  }

  // 4. Aggregate
  const results = JSON.parse(exec('ppg aggregate --all --json'))

  // 5. Present results to user
  summarize(results)

  // 6. Cleanup
  exec('ppg reset --json')
}`}</code>
        </pre>
      </section>

      <Separator />

      {/* The /ppg Skill */}
      <section className="space-y-4" id="the-ppg-skill">
        <h2 className="text-2xl font-semibold tracking-tight">
          The /ppg Skill
        </h2>
        <p className="text-muted-foreground">
          PPG ships with a{" "}
          <strong className="text-foreground">Claude Code skill</strong> that
          turns Claude into a conductor automatically:
        </p>
        <ul className="list-inside list-disc space-y-2 text-muted-foreground">
          <li>
            Activated by mentioning ppg-related tasks in conversation
          </li>
          <li>
            The skill provides Claude with the full conductor protocol
          </li>
          <li>
            Claude reads the <code>CLAUDE.md</code>, understands the
            project, and orchestrates agents
          </li>
          <li>
            All agents are spawned via <code>ppg spawn</code> (never as
            background bash tasks)
          </li>
          <li>
            The skill monitors the ppg dashboard for the user
          </li>
        </ul>
        <Card className="border-dashed">
          <CardContent className="flex items-start gap-3 py-4">
            <Bot className="mt-0.5 size-5 shrink-0 text-muted-foreground" />
            <div className="text-sm text-muted-foreground">
              <p>
                Just mention your goal in a Claude Code session with
                the PPG plugin installed. Claude recognizes the context and
                enters conductor mode on its own &mdash; no special commands
                needed.
              </p>
            </div>
          </CardContent>
        </Card>
      </section>

      <Separator />

      {/* Custom Conductor Scripts */}
      <section className="space-y-6" id="custom-conductor-scripts">
        <h2 className="text-2xl font-semibold tracking-tight">
          Custom Conductor Scripts
        </h2>
        <p className="text-muted-foreground">
          You can write your own conductor as a shell script or Node.js
          program for full control over orchestration logic.
        </p>

        {/* Shell script example */}
        <div className="space-y-2">
          <h3 className="text-xl font-semibold tracking-tight">
            Shell Script
          </h3>
          <pre>
            <code>{`#!/bin/bash
# conductor.sh — spawn agents for a feature

# 2. Spawn
ppg spawn --name api --prompt 'Build the REST API for user management' --json
ppg spawn --name frontend --prompt 'Build the React UI for user management' --json
ppg spawn --name tests --prompt 'Write integration tests for user management' --json

# 3. Wait for all agents (1 hour timeout)
ppg wait --all --timeout 3600 --json

# 4. Aggregate results
ppg aggregate --all --json

# 5. Merge in dependency order
ppg merge wt-abc123 --json   # api (shared code first)
ppg merge wt-def456 --json   # frontend
ppg merge wt-ghi789 --json   # tests`}</code>
          </pre>
        </div>

        {/* Node.js example */}
        <div className="space-y-2">
          <h3 className="text-xl font-semibold tracking-tight">
            Node.js
          </h3>
          <pre>
            <code>{`import { execaCommand } from 'execa'

async function ppg(cmd) {
  const { stdout } = await execaCommand(\`ppg \${cmd} --json\`)
  return JSON.parse(stdout)
}

// Spawn agents
const tasks = [
  { name: 'api', prompt: 'Build the REST API' },
  { name: 'frontend', prompt: 'Build the React UI' },
  { name: 'tests', prompt: 'Write integration tests' },
]

for (const task of tasks) {
  await ppg(\`spawn --name \${task.name} --prompt '\${task.prompt}'\`)
}

// Poll until done
let done = false
while (!done) {
  const status = await ppg('status')
  const agents = status.worktrees.flatMap(w => w.agents)
  done = agents.every(a => ['completed', 'failed'].includes(a.status))
  if (!done) await new Promise(r => setTimeout(r, 5000))
}

// Aggregate and review
const results = await ppg('aggregate --all')
console.log(results)`}</code>
          </pre>
        </div>
      </section>

      <Separator />

      {/* Agent Type Selection */}
      <section className="space-y-4" id="agent-type-selection">
        <h2 className="text-2xl font-semibold tracking-tight">
          Agent Type Selection
        </h2>
        <p className="text-muted-foreground">
          PPG supports multiple agent backends. Pass{" "}
          <code>--agent</code> when spawning to choose:
        </p>

        <div className="space-y-3">
          <div className="flex items-start gap-3 rounded-lg border px-4 py-3">
            <Badge variant="default">claude</Badge>
            <div className="min-w-0 text-sm text-muted-foreground">
              <strong className="text-foreground">Default.</strong> Claude Code
              &mdash; best for complex, multi-file tasks that require deep
              codebase understanding.
            </div>
          </div>
          <div className="flex items-start gap-3 rounded-lg border px-4 py-3">
            <Badge variant="secondary">codex</Badge>
            <div className="min-w-0 text-sm text-muted-foreground">
              OpenAI Codex &mdash; good for focused code generation and
              single-file tasks.
            </div>
          </div>
          <div className="flex items-start gap-3 rounded-lg border px-4 py-3">
            <Badge variant="outline">custom</Badge>
            <div className="min-w-0 text-sm text-muted-foreground">
              Define your own in <code>.ppg/config.yaml</code> with{" "}
              <code>command</code> and <code>promptFlag</code> fields.
            </div>
          </div>
        </div>

        <pre>
          <code>{`# Spawn with a specific agent type
ppg spawn --name api --agent codex --prompt 'Build the REST API'

# Custom agent in .ppg/config.yaml
agents:
  my-agent:
    command: "my-cli run"
    promptFlag: "--task"`}</code>
        </pre>
      </section>

      <Separator />

      {/* Error Handling */}
      <section className="space-y-4" id="error-handling">
        <h2 className="text-2xl font-semibold tracking-tight">
          Error Handling
        </h2>
        <p className="text-muted-foreground">
          Agents can fail. A robust conductor handles failures gracefully:
        </p>
        <ul className="list-inside list-disc space-y-2 text-muted-foreground">
          <li>
            Check agent status for <code>failed</code> state in the poll loop
          </li>
          <li>
            Use <code>ppg logs &lt;agent-id&gt;</code> to diagnose what went
            wrong
          </li>
          <li>
            Use <code>ppg restart &lt;agent-id&gt;</code> to retry with the same
            or a modified prompt
          </li>
          <li>
            Set <code>--timeout</code> on <code>ppg wait</code> to prevent
            infinite blocking
          </li>
          <li>
            Handle partial failures &mdash; merge what succeeded, report what
            didn&apos;t
          </li>
        </ul>
        <pre>
          <code>{`# Diagnose a failed agent
ppg logs ag-abc12345

# Retry with same prompt
ppg restart ag-abc12345 --json

# Retry with modified prompt
ppg restart ag-abc12345 --prompt 'Build REST API (use Express, not Hono)' --json

# Wait with a timeout (seconds)
ppg wait --all --timeout 1800 --json`}</code>
        </pre>
      </section>

      <Separator />

      {/* Best Practices */}
      <section className="space-y-4" id="best-practices">
        <h2 className="text-2xl font-semibold tracking-tight">
          Best Practices
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {[
            {
              icon: Hash,
              title: "One concern per worktree",
              description:
                "Keep each agent focused on a single task for clean, conflict-free merges.",
            },
            {
              icon: Terminal,
              title: "Always use --json",
              description:
                "Machine-readable output is essential for automated conductor workflows.",
            },
            {
              icon: RefreshCw,
              title: "Poll every 5 seconds",
              description:
                "Polling more frequently wastes resources. 5s strikes the right balance.",
            },
            {
              icon: Cpu,
              title: "Self-contained prompts",
              description:
                "Agents have no shared context. Each prompt must stand on its own.",
            },
          ].map(({ icon: Icon, title, description }) => (
            <Card key={title} className="border-dashed">
              <CardContent className="flex items-start gap-3 py-4">
                <Icon className="mt-0.5 size-5 shrink-0 text-muted-foreground" />
                <div className="min-w-0">
                  <p className="text-sm font-medium">{title}</p>
                  <p className="text-sm text-muted-foreground">
                    {description}
                  </p>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
        <Card className="border-dashed">
          <CardContent className="flex items-start gap-3 py-4">
            <Lightbulb className="mt-0.5 size-5 shrink-0 text-muted-foreground" />
            <div className="text-sm text-muted-foreground">
              <p>
                <strong className="text-foreground">Merge order matters.</strong>{" "}
                Merge shared code and dependencies first, then the features that
                depend on them. Use <code>ppg aggregate</code> to review all
                results before merging anything.
              </p>
            </div>
          </CardContent>
        </Card>
      </section>
    </div>
  )
}
