import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  Terminal,
  GitBranch,
  Bot,
  FileText,
  Trash2,
  Layers,
  LayoutDashboard,
  Clock,
  ChevronRight,
} from "lucide-react"
import type { Metadata } from "next"
import type { ReactNode } from "react"

export const metadata: Metadata = {
  title: "CLI Reference — ppg",
  description: "Complete reference for all ppg commands",
}

/* ─── Helpers ─────────────────────────────────────────────────────── */

function CommandBlock({
  id,
  name,
  description,
  usage,
  options,
  examples,
}: {
  id: string
  name: string
  description: string
  usage: string
  options?: { flag: string; description: string }[]
  examples?: { code: string; label?: string }[]
}) {
  return (
    <div id={id} className="scroll-mt-24 space-y-3">
      <h3 className="text-xl font-semibold tracking-tight">
        <code className="bg-muted rounded px-1.5 py-0.5 font-mono text-lg">
          {name}
        </code>
      </h3>
      <p className="text-muted-foreground">{description}</p>
      <pre>
        <code>{usage}</code>
      </pre>

      {options && options.length > 0 && (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Option</TableHead>
              <TableHead>Description</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {options.map((opt) => (
              <TableRow key={opt.flag}>
                <TableCell className="font-mono text-xs">{opt.flag}</TableCell>
                <TableCell className="text-muted-foreground">
                  {opt.description}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {examples && examples.length > 0 && (
        <div className="space-y-2">
          {examples.map((ex, i) => (
            <div key={i}>
              {ex.label && (
                <p className="text-muted-foreground mb-1 text-sm">
                  {ex.label}
                </p>
              )}
              <pre>
                <code>{ex.code}</code>
              </pre>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function SectionHeader({
  id,
  icon,
  label,
  children,
}: {
  id: string
  icon: ReactNode
  label: string
  children: string
}) {
  return (
    <div id={id} className="scroll-mt-24 space-y-1">
      <Badge variant="secondary" className="mb-2 gap-1.5">
        {icon}
        {label}
      </Badge>
      <h2 className="text-2xl font-semibold tracking-tight">{children}</h2>
    </div>
  )
}

/* ─── Data ────────────────────────────────────────────────────────── */

const tocGroups = [
  {
    label: "Core Commands",
    href: "#core",
    items: ["init", "spawn", "status", "merge", "reset"],
  },
  {
    label: "Agent Management",
    href: "#agents",
    items: ["kill", "attach", "logs", "send", "restart", "wait"],
  },
  {
    label: "Results & Diffs",
    href: "#results",
    items: ["aggregate", "diff", "pr"],
  },
  { label: "Cleanup", href: "#cleanup", items: ["clean"] },
  {
    label: "Swarms & Prompts",
    href: "#swarms",
    items: ["swarm", "prompt", "list"],
  },
  {
    label: "Worktree Management",
    href: "#worktree",
    items: ["worktree create"],
  },
  {
    label: "Dashboard & UI",
    href: "#dashboard",
    items: ["ui", "install-dashboard"],
  },
  {
    label: "Scheduling (Cron)",
    href: "#cron",
    items: [
      "cron start",
      "cron stop",
      "cron list",
      "cron status",
      "cron add",
      "cron remove",
    ],
  },
  { label: "Global Options", href: "#global-options", items: [] },
]

/* ─── Page ────────────────────────────────────────────────────────── */

export default function CLIReferencePage() {
  return (
    <div className="space-y-12">
      {/* Title */}
      <div className="space-y-2">
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
          CLI Reference
        </h1>
        <p className="text-muted-foreground text-lg">
          Complete reference for all ppg commands
        </p>
      </div>

      {/* Table of Contents */}
      <nav className="bg-muted/50 rounded-lg border p-5">
        <p className="mb-3 text-sm font-medium uppercase tracking-wider text-muted-foreground">
          On this page
        </p>
        <ul className="grid gap-1 sm:grid-cols-2 lg:grid-cols-3">
          {tocGroups.map((group) => (
            <li key={group.href}>
              <a
                href={group.href}
                className="group flex items-center gap-1.5 rounded-md px-2 py-1.5 text-sm transition-colors hover:bg-accent hover:text-accent-foreground"
              >
                <ChevronRight className="text-muted-foreground size-3.5 transition-transform group-hover:translate-x-0.5" />
                <span className="font-medium">{group.label}</span>
                {group.items.length > 0 && (
                  <span className="text-muted-foreground ml-auto text-xs">
                    {group.items.length}
                  </span>
                )}
              </a>
            </li>
          ))}
        </ul>
      </nav>

      <Separator />

      {/* ── Core Commands ─────────────────────────────────────────── */}
      <section className="space-y-8">
        <SectionHeader
          id="core"
          icon={<Terminal className="size-3.5" />}
          label="Core"
        >
          Core Commands
        </SectionHeader>

        <CommandBlock
          id="init"
          name="ppg init"
          description="Initialize PPG in the current git repository."
          usage="ppg init [--json]"
        />

        <CommandBlock
          id="spawn"
          name="ppg spawn"
          description="Spawn a new worktree and agent(s), or add agents to an existing worktree."
          usage="ppg spawn [options]"
          options={[
            { flag: "-n, --name <name>", description: "Worktree name" },
            { flag: "-a, --agent <type>", description: "Agent type to spawn" },
            {
              flag: "-p, --prompt <text>",
              description: "Task prompt for the agent",
            },
            {
              flag: "-f, --prompt-file <path>",
              description: "Read prompt from a file",
            },
            {
              flag: "-t, --template <name>",
              description: "Use a named template",
            },
            {
              flag: "--var <key=value>",
              description: "Template variable (repeatable)",
            },
            {
              flag: "-b, --base <branch>",
              description: "Base branch for the worktree",
            },
            {
              flag: "--branch <name>",
              description: "Explicit branch name for the worktree",
            },
            {
              flag: "-w, --worktree <id>",
              description: "Add agent to an existing worktree",
            },
            {
              flag: "-c, --count <n>",
              description: "Number of agents to spawn",
            },
            {
              flag: "--split",
              description: "Split panes within a single tmux window",
            },
            {
              flag: "--open",
              description: "Open Terminal.app window after spawning",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
          examples={[
            {
              label: "Spawn with an inline prompt:",
              code: "ppg spawn --name auth --prompt 'Add OAuth login'",
            },
            {
              label: "Add an agent to an existing worktree:",
              code: "ppg spawn -w wt-abc123 --agent codex --prompt 'review'",
            },
          ]}
        />

        <CommandBlock
          id="status"
          name="ppg status"
          description="Show status of worktrees and agents."
          usage="ppg status [worktree] [--json] [-w/--watch]"
          options={[
            {
              flag: "-w, --watch",
              description: "Continuously watch for status changes",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="merge"
          name="ppg merge"
          description="Merge a worktree branch back into the base branch."
          usage="ppg merge <worktree-id> [options]"
          options={[
            {
              flag: "-s, --strategy <squash|no-ff>",
              description: "Merge strategy (default: squash)",
            },
            {
              flag: "--no-cleanup",
              description: "Keep worktree and branch after merge",
            },
            {
              flag: "--dry-run",
              description: "Preview merge without applying",
            },
            {
              flag: "--force",
              description: "Force merge even with conflicts",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="reset"
          name="ppg reset"
          description="Kill all agents, remove all worktrees, and wipe manifest."
          usage="ppg reset [--force] [--prune] [--include-open-prs] [--json]"
          options={[
            { flag: "--force", description: "Skip confirmation prompt" },
            {
              flag: "--prune",
              description: "Also prune orphaned git worktrees",
            },
            {
              flag: "--include-open-prs",
              description: "Also remove worktrees with open PRs",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />
      </section>

      <Separator />

      {/* ── Agent Management ──────────────────────────────────────── */}
      <section className="space-y-8">
        <SectionHeader
          id="agents"
          icon={<Bot className="size-3.5" />}
          label="Agents"
        >
          Agent Management
        </SectionHeader>

        <CommandBlock
          id="kill"
          name="ppg kill"
          description="Kill agents or worktrees."
          usage="ppg kill [options]"
          options={[
            { flag: "-a, --agent <id>", description: "Kill a specific agent" },
            {
              flag: "-w, --worktree <id>",
              description: "Kill all agents in a worktree",
            },
            { flag: "--all", description: "Kill all agents" },
            {
              flag: "-r, --remove",
              description: "Remove worktree after killing",
            },
            {
              flag: "-d, --delete",
              description: "Delete worktree branch after killing",
            },
            {
              flag: "--include-open-prs",
              description: "Also kill worktrees with open PRs",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="attach"
          name="ppg attach"
          description="Attach to a worktree or agent tmux pane."
          usage="ppg attach <target>"
        />

        <CommandBlock
          id="logs"
          name="ppg logs"
          description="View agent pane output."
          usage="ppg logs <agent-id> [-l/--lines <n>] [-f/--follow] [--full] [--json]"
          options={[
            {
              flag: "-l, --lines <n>",
              description: "Number of lines to show",
            },
            { flag: "-f, --follow", description: "Follow log output" },
            { flag: "--full", description: "Show full pane history" },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="send"
          name="ppg send"
          description="Send text to an agent's tmux pane."
          usage="ppg send <agent-id> <text> [--keys] [--no-enter] [--json]"
          options={[
            {
              flag: "--keys",
              description: "Send as tmux key sequence instead of text",
            },
            {
              flag: "--no-enter",
              description: "Don't append Enter after text",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="restart"
          name="ppg restart"
          description="Restart an agent in the same worktree."
          usage="ppg restart <agent-id> [-p/--prompt <text>] [-a/--agent <type>] [--open] [--json]"
          options={[
            {
              flag: "-p, --prompt <text>",
              description: "New prompt for the restarted agent",
            },
            {
              flag: "-a, --agent <type>",
              description: "Change agent type on restart",
            },
            {
              flag: "--open",
              description: "Open Terminal.app window after restart",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="wait"
          name="ppg wait"
          description="Wait for agents to reach a terminal state."
          usage="ppg wait [worktree-id] [--all] [--timeout <seconds>] [--interval <seconds>] [--json]"
          options={[
            { flag: "--all", description: "Wait for all agents" },
            {
              flag: "--timeout <seconds>",
              description: "Maximum time to wait",
            },
            {
              flag: "--interval <seconds>",
              description: "Polling interval",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />
      </section>

      <Separator />

      {/* ── Results & Diffs ───────────────────────────────────────── */}
      <section className="space-y-8">
        <SectionHeader
          id="results"
          icon={<FileText className="size-3.5" />}
          label="Results"
        >
          Results & Diffs
        </SectionHeader>

        <CommandBlock
          id="aggregate"
          name="ppg aggregate"
          description="Aggregate results from agents."
          usage="ppg aggregate [worktree-id] [--all] [-o/--output <file>] [--json]"
          options={[
            {
              flag: "--all",
              description: "Aggregate results from all worktrees",
            },
            {
              flag: "-o, --output <file>",
              description: "Write aggregated results to a file",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="diff"
          name="ppg diff"
          description="Show changes made in a worktree branch."
          usage="ppg diff <worktree-id> [--stat] [--name-only] [--json]"
          options={[
            {
              flag: "--stat",
              description: "Show diffstat summary",
            },
            { flag: "--name-only", description: "Only list changed file names" },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="pr"
          name="ppg pr"
          description="Create a GitHub PR from a worktree branch."
          usage="ppg pr <worktree-id> [--title <text>] [--body <text>] [--draft] [--json]"
          options={[
            { flag: "--title <text>", description: "PR title" },
            { flag: "--body <text>", description: "PR body" },
            { flag: "--draft", description: "Create as draft PR" },
            { flag: "--json", description: "Output JSON" },
          ]}
        />
      </section>

      <Separator />

      {/* ── Cleanup ───────────────────────────────────────────────── */}
      <section className="space-y-8">
        <SectionHeader
          id="cleanup"
          icon={<Trash2 className="size-3.5" />}
          label="Cleanup"
        >
          Cleanup
        </SectionHeader>

        <CommandBlock
          id="clean"
          name="ppg clean"
          description="Remove worktrees in terminal states (completed, merged, failed, killed)."
          usage="ppg clean [--all] [--dry-run] [--prune] [--include-open-prs] [--json]"
          options={[
            {
              flag: "--all",
              description: "Clean all terminal-state worktrees",
            },
            {
              flag: "--dry-run",
              description: "Preview what would be removed",
            },
            {
              flag: "--prune",
              description: "Also prune orphaned git worktrees",
            },
            {
              flag: "--include-open-prs",
              description: "Also clean worktrees with open PRs",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />
      </section>

      <Separator />

      {/* ── Swarms & Prompts ──────────────────────────────────────── */}
      <section className="space-y-8">
        <SectionHeader
          id="swarms"
          icon={<Layers className="size-3.5" />}
          label="Swarms"
        >
          Swarms & Prompts
        </SectionHeader>

        <CommandBlock
          id="swarm"
          name="ppg swarm"
          description="Run a swarm template (multi-agent workflow)."
          usage="ppg swarm <template> [-w/--worktree <ref>] [--var <key=value>] [-n/--name <name>] [-b/--base <branch>] [--open] [--json]"
          options={[
            {
              flag: "-w, --worktree <ref>",
              description: "Target an existing worktree",
            },
            {
              flag: "--var <key=value>",
              description: "Template variable (repeatable)",
            },
            { flag: "-n, --name <name>", description: "Worktree name" },
            {
              flag: "-b, --base <branch>",
              description: "Base branch",
            },
            { flag: "--open", description: "Open Terminal.app window" },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="prompt"
          name="ppg prompt"
          description="Spawn using a named prompt from .ppg/prompts/."
          usage="ppg prompt <name> [-n/--name <name>] [-a/--agent <type>] [--var <key=value>] [-b/--base <branch>] [-c/--count <n>] [--split] [--open] [--json]"
          options={[
            { flag: "-n, --name <name>", description: "Worktree name" },
            { flag: "-a, --agent <type>", description: "Agent type" },
            {
              flag: "--var <key=value>",
              description: "Template variable (repeatable)",
            },
            { flag: "-b, --base <branch>", description: "Base branch" },
            {
              flag: "-c, --count <n>",
              description: "Number of agents to spawn",
            },
            {
              flag: "--split",
              description: "Split panes within a single tmux window",
            },
            { flag: "--open", description: "Open Terminal.app window" },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="list"
          name="ppg list"
          description="List available templates, swarms, or prompts."
          usage="ppg list <templates|swarms|prompts> [--json]"
        />
      </section>

      <Separator />

      {/* ── Worktree Management ───────────────────────────────────── */}
      <section className="space-y-8">
        <SectionHeader
          id="worktree"
          icon={<GitBranch className="size-3.5" />}
          label="Worktrees"
        >
          Worktree Management
        </SectionHeader>

        <CommandBlock
          id="worktree-create"
          name="ppg worktree create"
          description="Create a standalone worktree without spawning agents."
          usage="ppg worktree create [-n/--name <name>] [-b/--base <branch>] [--branch <name>] [--json]"
          options={[
            { flag: "-n, --name <name>", description: "Worktree name" },
            { flag: "-b, --base <branch>", description: "Base branch" },
            {
              flag: "--branch <name>",
              description: "Explicit branch name",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />
      </section>

      <Separator />

      {/* ── Dashboard & UI ────────────────────────────────────────── */}
      <section className="space-y-8">
        <SectionHeader
          id="dashboard"
          icon={<LayoutDashboard className="size-3.5" />}
          label="Dashboard"
        >
          Dashboard & UI
        </SectionHeader>

        <CommandBlock
          id="ui"
          name="ppg ui"
          description="Open the native macOS dashboard. Also available as ppg dashboard."
          usage="ppg ui"
        />

        <CommandBlock
          id="install-dashboard"
          name="ppg install-dashboard"
          description="Download and install the macOS dashboard app."
          usage="ppg install-dashboard [--dir <path>] [--json]"
          options={[
            {
              flag: "--dir <path>",
              description: "Installation directory",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />
      </section>

      <Separator />

      {/* ── Scheduling (Cron) ─────────────────────────────────────── */}
      <section className="space-y-8">
        <SectionHeader
          id="cron"
          icon={<Clock className="size-3.5" />}
          label="Cron"
        >
          Scheduling (Cron)
        </SectionHeader>

        <CommandBlock
          id="cron-start"
          name="ppg cron start"
          description="Start the cron scheduler daemon."
          usage="ppg cron start [--json]"
        />

        <CommandBlock
          id="cron-stop"
          name="ppg cron stop"
          description="Stop the cron scheduler daemon."
          usage="ppg cron stop [--json]"
        />

        <CommandBlock
          id="cron-list"
          name="ppg cron list"
          description="List configured schedules and next run times."
          usage="ppg cron list [--json]"
        />

        <CommandBlock
          id="cron-status"
          name="ppg cron status"
          description="Show cron daemon status and recent log."
          usage="ppg cron status [-l/--lines <n>] [--json]"
          options={[
            {
              flag: "-l, --lines <n>",
              description: "Number of log lines to show",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />

        <CommandBlock
          id="cron-add"
          name="ppg cron add"
          description="Add a new schedule entry."
          usage="ppg cron add --name <name> --cron <expression> [--swarm <name>] [--prompt <name>] [--var <key=value>] [--project <path>] [--json]"
          options={[
            {
              flag: "--name <name>",
              description: "Schedule entry name (required)",
            },
            {
              flag: "--cron <expression>",
              description: "Cron expression (required)",
            },
            { flag: "--swarm <name>", description: "Swarm to run" },
            { flag: "--prompt <name>", description: "Prompt to run" },
            {
              flag: "--var <key=value>",
              description: "Template variable (repeatable)",
            },
            {
              flag: "--project <path>",
              description: "Project directory path",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
          examples={[
            {
              code: "ppg cron add --name nightly-review --cron '0 2 * * *' --swarm code-review",
            },
          ]}
        />

        <CommandBlock
          id="cron-remove"
          name="ppg cron remove"
          description="Remove a schedule entry."
          usage="ppg cron remove --name <name> [--project <path>] [--json]"
          options={[
            {
              flag: "--name <name>",
              description: "Schedule entry name to remove (required)",
            },
            {
              flag: "--project <path>",
              description: "Project directory path",
            },
            { flag: "--json", description: "Output JSON" },
          ]}
        />
      </section>

      <Separator />

      {/* ── Global Options ────────────────────────────────────────── */}
      <section id="global-options" className="scroll-mt-24 space-y-4">
        <Badge variant="secondary" className="mb-2 gap-1.5">
          <Terminal className="size-3.5" />
          Global
        </Badge>
        <h2 className="text-2xl font-semibold tracking-tight">
          Global Options
        </h2>
        <p className="text-muted-foreground">
          These flags are available across all commands.
        </p>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Option</TableHead>
              <TableHead>Description</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow>
              <TableCell className="font-mono text-xs">--json</TableCell>
              <TableCell className="text-muted-foreground">
                Output machine-readable JSON (used by conductor mode)
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell className="font-mono text-xs">--version</TableCell>
              <TableCell className="text-muted-foreground">
                Show ppg version
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell className="font-mono text-xs">--help</TableCell>
              <TableCell className="text-muted-foreground">
                Show help for any command
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </section>
    </div>
  )
}
