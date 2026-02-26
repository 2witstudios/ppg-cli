import {
  GitBranch,
  Bot,
  Database,
  Terminal,
  FileText,
  Users,
  Cpu,
  Monitor,
  ArrowRight,
  List,
} from "lucide-react"

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"

const tocItems = [
  { id: "worktrees", label: "Worktrees", icon: GitBranch },
  { id: "agents", label: "Agents", icon: Bot },
  { id: "manifest", label: "Manifest", icon: Database },
  { id: "tmux", label: "tmux", icon: Terminal },
  { id: "templates-prompts", label: "Templates & Prompts", icon: FileText },
  { id: "swarms", label: "Swarms", icon: Users },
  { id: "conductor-mode", label: "Conductor Mode", icon: Cpu },
  { id: "dashboard", label: "Dashboard", icon: Monitor },
  { id: "architecture-diagram", label: "Architecture Diagram", icon: List },
]

export default function ConceptsPage() {
  return (
    <div className="prose-like space-y-12">
      {/* Header */}
      <div className="space-y-3">
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
          Concepts &amp; Architecture
        </h1>
        <p className="text-muted-foreground max-w-2xl text-lg">
          Understanding how PPG orchestrates parallel AI agents
        </p>
      </div>

      {/* Table of Contents */}
      <Card>
        <CardHeader>
          <CardTitle>On this page</CardTitle>
        </CardHeader>
        <CardContent>
          <nav className="grid gap-1 sm:grid-cols-2 lg:grid-cols-3">
            {tocItems.map(({ id, label, icon: Icon }) => (
              <a
                key={id}
                href={`#${id}`}
                className="text-muted-foreground hover:text-foreground hover:bg-muted flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors"
              >
                <Icon className="size-4 shrink-0" />
                {label}
              </a>
            ))}
          </nav>
        </CardContent>
      </Card>

      <Separator />

      {/* 1. Worktrees */}
      <section id="worktrees" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <GitBranch className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Worktrees</h2>
            <p className="text-muted-foreground text-sm">
              Git-native filesystem isolation for every agent
            </p>
          </div>
        </div>

        <p className="text-muted-foreground leading-relaxed">
          PPG uses <strong className="text-foreground">git worktrees</strong> to give each agent its own
          isolated filesystem checkout. Every agent works on its own branch following the{" "}
          <code>ppg/&lt;name&gt;</code> naming convention, in a directory at{" "}
          <code>.worktrees/wt-&#123;id&#125;/</code> relative to the project root.
        </p>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Benefits</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="text-muted-foreground space-y-2 text-sm">
              <li className="flex items-start gap-2">
                <ArrowRight className="text-primary mt-0.5 size-4 shrink-0" />
                <span>
                  <strong className="text-foreground">True filesystem isolation</strong> — agents
                  can&apos;t step on each other&apos;s files
                </span>
              </li>
              <li className="flex items-start gap-2">
                <ArrowRight className="text-primary mt-0.5 size-4 shrink-0" />
                <span>
                  <strong className="text-foreground">Shared git history</strong> — all worktrees
                  share the same <code>.git</code> object store
                </span>
              </li>
              <li className="flex items-start gap-2">
                <ArrowRight className="text-primary mt-0.5 size-4 shrink-0" />
                <span>
                  <strong className="text-foreground">Clean merges</strong> — squash merge back to
                  the base branch when work is done
                </span>
              </li>
            </ul>
          </CardContent>
        </Card>

        <div className="space-y-2">
          <p className="text-sm font-medium">Lifecycle</p>
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <Badge variant="outline">create</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge variant="outline">agent works</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge variant="outline">merge</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge variant="outline">cleanup</Badge>
          </div>
        </div>

        <pre>
{`# Branch naming convention
ppg/<name>

# Directory structure
.worktrees/
  wt-abc123/    # ← isolated checkout on branch ppg/auth-refactor
  wt-xyz789/    # ← isolated checkout on branch ppg/add-tests`}
        </pre>
      </section>

      <Separator />

      {/* 2. Agents */}
      <section id="agents" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <Bot className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Agents</h2>
            <p className="text-muted-foreground text-sm">
              CLI processes that do the actual coding work
            </p>
          </div>
        </div>

        <p className="text-muted-foreground leading-relaxed">
          An agent is a <strong className="text-foreground">CLI process running in a tmux pane</strong>.
          PPG is agent-agnostic: it works with Claude Code (the default), OpenAI Codex, or any CLI
          tool that accepts a prompt.
        </p>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Agent Configuration</CardTitle>
            <CardDescription>
              Agents are defined in <code>.ppg/config.yaml</code>
            </CardDescription>
          </CardHeader>
          <CardContent>
            <pre>
{`# .ppg/config.yaml
agents:
  claude:
    command: "claude"
    promptFlag: "--prompt"
    interactive: true

  codex:
    command: "codex"
    promptFlag: "--prompt"
    interactive: false`}
            </pre>
          </CardContent>
        </Card>

        <div className="space-y-2">
          <p className="text-sm font-medium">Lifecycle</p>
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <Badge variant="secondary">spawning</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge variant="secondary">running</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <span className="text-muted-foreground">one of:</span>
            <Badge variant="default">completed</Badge>
            <Badge variant="destructive">failed</Badge>
            <Badge variant="outline">killed</Badge>
            <Badge variant="outline">lost</Badge>
          </div>
        </div>

        <p className="text-muted-foreground text-sm leading-relaxed">
          Agents receive their task via a <strong className="text-foreground">prompt file</strong> written
          to the worktree. The prompt file is generated from a template with variables like{" "}
          <code>&#123;&#123;WORKTREE_PATH&#125;&#125;</code>,{" "}
          <code>&#123;&#123;BRANCH&#125;&#125;</code>, and{" "}
          <code>&#123;&#123;RESULT_FILE&#125;&#125;</code>.
        </p>
      </section>

      <Separator />

      {/* 3. Manifest */}
      <section id="manifest" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <Database className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Manifest</h2>
            <p className="text-muted-foreground text-sm">
              Single source of truth for all runtime state
            </p>
          </div>
        </div>

        <p className="text-muted-foreground leading-relaxed">
          <code>.ppg/manifest.json</code> is the{" "}
          <strong className="text-foreground">single source of truth</strong> for all runtime state.
          It tracks worktrees, agents, statuses, tmux targets, and timestamps.
        </p>

        <div className="grid gap-4 sm:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Contents</CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="text-muted-foreground space-y-1.5 text-sm">
                <li>Worktree records (ID, name, branch, path, status)</li>
                <li>Agent records (ID, command, tmux target, status)</li>
                <li>Timestamps (created, updated, completed)</li>
                <li>tmux session and pane identifiers</li>
              </ul>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Safety Guarantees</CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="text-muted-foreground space-y-1.5 text-sm">
                <li>
                  <strong className="text-foreground">File-level locking</strong> via{" "}
                  <code>proper-lockfile</code> (10s stale, 5 retries)
                </li>
                <li>
                  <strong className="text-foreground">Atomic writes</strong> via{" "}
                  <code>write-file-atomic</code>
                </li>
                <li>No partial reads or torn writes</li>
              </ul>
            </CardContent>
          </Card>
        </div>

        <p className="text-muted-foreground text-sm leading-relaxed">
          Both the CLI and the native macOS Dashboard read the same manifest file — no IPC, no
          sockets, no server. The filesystem <em>is</em> the communication layer.
        </p>
      </section>

      <Separator />

      {/* 4. tmux */}
      <section id="tmux" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <Terminal className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">tmux</h2>
            <p className="text-muted-foreground text-sm">
              Process management without a daemon
            </p>
          </div>
        </div>

        <p className="text-muted-foreground leading-relaxed">
          PPG uses <strong className="text-foreground">tmux</strong> as its process manager. One
          session per project, one window per worktree, one pane per agent. There is no custom
          daemon or server — tmux <em>is</em> the process manager.
        </p>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">What tmux provides</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="text-muted-foreground space-y-1.5 text-sm">
              <li>
                <strong className="text-foreground">Process lifecycle</strong> — start, stop, and
                monitor agent processes
              </li>
              <li>
                <strong className="text-foreground">Log capture</strong> — full scrollback buffer
                for every agent
              </li>
              <li>
                <strong className="text-foreground">Attach/detach</strong> — connect to a running
                agent interactively
              </li>
              <li>
                <strong className="text-foreground">send-keys</strong> — inject commands into
                running agents
              </li>
            </ul>
          </CardContent>
        </Card>

        <div className="space-y-2">
          <p className="text-sm font-medium">Signal-stack status detection</p>
          <p className="text-muted-foreground text-sm">
            PPG checks agent status using a priority stack, from most to least authoritative:
          </p>
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <Badge variant="default">result file</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge variant="secondary">pane exists</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge variant="secondary">pane dead</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge variant="secondary">current command</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge variant="outline">running</Badge>
          </div>
        </div>
      </section>

      <Separator />

      {/* 5. Templates & Prompts */}
      <section id="templates-prompts" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <FileText className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Templates &amp; Prompts</h2>
            <p className="text-muted-foreground text-sm">
              Reusable task definitions with variable substitution
            </p>
          </div>
        </div>

        <p className="text-muted-foreground leading-relaxed">
          Templates are Markdown files in <code>.ppg/templates/</code> with{" "}
          <code>&#123;&#123;VAR&#125;&#125;</code> placeholders. PPG substitutes built-in variables
          at spawn time.
        </p>

        <div className="grid gap-4 sm:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Built-in Variables</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex flex-wrap gap-2">
                <Badge variant="outline"><code>WORKTREE_PATH</code></Badge>
                <Badge variant="outline"><code>BRANCH</code></Badge>
                <Badge variant="outline"><code>AGENT_ID</code></Badge>
                <Badge variant="outline"><code>RESULT_FILE</code></Badge>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">File Locations</CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="text-muted-foreground space-y-1.5 text-sm">
                <li>
                  <code>.ppg/templates/</code> — reusable Markdown templates
                </li>
                <li>
                  <code>.ppg/prompts/</code> — named prompt files (spawn shorthand)
                </li>
                <li>
                  <code>.ppg/swarms/</code> — multi-agent workflow definitions
                </li>
              </ul>
            </CardContent>
          </Card>
        </div>

        <pre>
{`# Example template: .ppg/templates/implement.md
You are working in {{WORKTREE_PATH}} on branch {{BRANCH}}.

Your task: {{TASK}}

When finished, write your result to {{RESULT_FILE}}.`}
        </pre>
      </section>

      <Separator />

      {/* 6. Swarms */}
      <section id="swarms" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <Users className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Swarms</h2>
            <p className="text-muted-foreground text-sm">
              Predefined multi-agent workflows
            </p>
          </div>
        </div>

        <p className="text-muted-foreground leading-relaxed">
          Swarms are predefined multi-agent workflows defined in YAML files under{" "}
          <code>.ppg/swarms/</code>. They let you spawn multiple agents that work on the same or
          different worktrees as a coordinated group.
        </p>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Use Cases</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="text-muted-foreground space-y-1.5 text-sm">
              <li>
                <strong className="text-foreground">Code review swarms</strong> — multiple
                reviewers analyzing code from different angles
              </li>
              <li>
                <strong className="text-foreground">Feature implementation</strong> — one agent
                writes code, another writes tests
              </li>
              <li>
                <strong className="text-foreground">Multi-file refactors</strong> — coordinate
                changes across independent modules
              </li>
            </ul>
          </CardContent>
        </Card>

        <pre>
{`# Example: .ppg/swarms/review.yaml
name: code-review
agents:
  - name: security-reviewer
    template: review
    vars:
      FOCUS: "security vulnerabilities"
  - name: perf-reviewer
    template: review
    vars:
      FOCUS: "performance issues"`}
        </pre>
      </section>

      <Separator />

      {/* 7. Conductor Mode */}
      <section id="conductor-mode" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <Cpu className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Conductor Mode</h2>
            <p className="text-muted-foreground text-sm">
              AI orchestrating AI — fully autonomous workflows
            </p>
          </div>
        </div>

        <p className="text-muted-foreground leading-relaxed">
          A conductor is a <strong className="text-foreground">meta-agent</strong> — an AI that
          drives PPG programmatically. It uses <code>--json</code> output for machine-readable
          responses and follows a structured loop.
        </p>

        <div className="space-y-2">
          <p className="text-sm font-medium">Conductor Loop</p>
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <Badge>Plan</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge>Spawn</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge>Poll</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge>Aggregate</Badge>
            <ArrowRight className="text-muted-foreground size-3" />
            <Badge>Merge</Badge>
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Example Commands</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <pre>
{`# Spawn agents with JSON output
ppg spawn --name auth-refactor --prompt "Refactor auth module" --json

# Poll for completion
ppg status --json

# Collect results
ppg aggregate --all --json

# Merge completed work
ppg merge wt-abc123`}
            </pre>
          </CardContent>
        </Card>

        <p className="text-muted-foreground text-sm leading-relaxed">
          The conductor enables fully autonomous multi-agent workflows — an AI breaks down a
          complex task, delegates to specialist agents, monitors their progress, and merges the
          results.
        </p>
      </section>

      <Separator />

      {/* 8. Dashboard */}
      <section id="dashboard" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <Monitor className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Dashboard</h2>
            <p className="text-muted-foreground text-sm">
              Native macOS app for visual agent management
            </p>
          </div>
        </div>

        <p className="text-muted-foreground leading-relaxed">
          The Dashboard is a <strong className="text-foreground">native macOS app</strong> built in
          Swift that watches <code>manifest.json</code> for changes. It provides visual controls
          for spawning, killing, monitoring, and merging agents.
        </p>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Key Design</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="text-muted-foreground space-y-1.5 text-sm">
              <li>
                <strong className="text-foreground">Fully decoupled</strong> — reads the same
                manifest file as the CLI
              </li>
              <li>
                <strong className="text-foreground">No server, no IPC</strong> — filesystem
                watching is the only communication channel
              </li>
              <li>
                <strong className="text-foreground">Visual controls</strong> — spawn, kill, status,
                logs, diffs, merge
              </li>
              <li>
                <strong className="text-foreground">Real-time updates</strong> — reacts
                instantly to manifest changes
              </li>
            </ul>
          </CardContent>
        </Card>
      </section>

      <Separator />

      {/* Architecture Diagram */}
      <section id="architecture-diagram" className="scroll-mt-20 space-y-4">
        <div className="flex items-center gap-3">
          <div className="bg-primary/10 text-primary flex size-10 items-center justify-center rounded-lg">
            <List className="size-5" />
          </div>
          <div>
            <h2 className="text-2xl font-semibold tracking-tight">Architecture Diagram</h2>
            <p className="text-muted-foreground text-sm">
              How all the pieces fit together
            </p>
          </div>
        </div>

        <Card>
          <CardContent className="pt-6">
            <pre className="text-xs leading-relaxed sm:text-sm">
{`┌─────────────────────────────────────────────────────────┐
│                      Project Root                       │
│                                                         │
│  ┌─────────────────────────┐  ┌──────────────────────┐  │
│  │         .ppg/           │  │     .worktrees/      │  │
│  │                         │  │                      │  │
│  │  manifest.json ◄────────┼──┼─── wt-abc123/       │  │
│  │  config.yaml            │  │    (ppg/auth-refac)  │  │
│  │  templates/             │  │                      │  │
│  │  prompts/               │  │    wt-xyz789/        │  │
│  │  swarms/                │  │    (ppg/add-tests)   │  │
│  │  results/               │  │                      │  │
│  │    ag-abcd1234.md       │  └──────────────────────┘  │
│  │    ag-efgh5678.md       │                            │
│  └────────┬────────────────┘                            │
│           │                                             │
└───────────┼─────────────────────────────────────────────┘
            │
            │ reads / writes
            │
    ┌───────┴───────────────────────────────────────┐
    │                                               │
    ▼                                               ▼
┌──────────┐   ┌──────────────────────────────────────┐
│   CLI    │   │         Dashboard (Swift)             │
│  (ppg)   │   │                                       │
│          │   │  watches manifest.json                │
│          │   │  visual spawn / kill / merge           │
└────┬─────┘   └───────────────────────────────────────┘
     │
     │ manages
     │
     ▼
┌──────────────────────────────────────────────────────┐
│                   tmux session                       │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │  Window 1   │  │  Window 2   │  │  Window 3   │  │
│  │  wt-abc123  │  │  wt-xyz789  │  │  wt-...     │  │
│  │             │  │             │  │             │  │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │  │
│  │ │ Pane 1  │ │  │ │ Pane 1  │ │  │ │ Pane 1  │ │  │
│  │ │ Agent   │ │  │ │ Agent   │ │  │ │ Agent   │ │  │
│  │ │ claude  │ │  │ │ codex   │ │  │ │ claude  │ │  │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  │
└──────────────────────────────────────────────────────┘`}
            </pre>
          </CardContent>
        </Card>
      </section>
    </div>
  )
}
