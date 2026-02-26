import type { Metadata } from "next";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import {
  Monitor,
  Download,
  Terminal,
  FolderOpen,
  Layers,
  Eye,
  GitMerge,
  Command,
  FileText,
  Network,
  Clock,
  Settings,
  Lightbulb,
  Cpu,
  Apple,
} from "lucide-react";

export const metadata: Metadata = {
  title: "Dashboard Guide — PPG",
  description:
    "Learn how to install and use the native macOS dashboard for PPG — monitor agents, view diffs, manage merges, and more.",
};

function Screenshot({ label }: { label: string }) {
  return (
    <div className="flex aspect-video items-center justify-center rounded-xl border bg-muted">
      <span className="text-sm text-muted-foreground">{label}</span>
    </div>
  );
}

function SectionIcon({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center justify-center rounded-lg bg-muted p-2 text-muted-foreground">
      {children}
    </span>
  );
}

const tocItems = [
  { href: "#installation", label: "Installation" },
  { href: "#main-interface", label: "Main Interface" },
  { href: "#overview-tab", label: "Overview Tab" },
  { href: "#workspace-view", label: "Workspace View" },
  { href: "#command-palette", label: "Command Palette" },
  { href: "#prompts-editor", label: "Prompts Editor" },
  { href: "#swarms-editor", label: "Swarms Editor" },
  { href: "#schedules", label: "Schedules" },
  { href: "#settings", label: "Settings" },
  { href: "#tips", label: "Tips" },
  { href: "#architecture", label: "Architecture Note" },
];

export default function DashboardGuidePage() {
  return (
    <div className="prose-like space-y-12">
      {/* Header */}
      <div className="space-y-3">
        <h1>Dashboard Guide</h1>
        <p className="text-lg text-muted-foreground">
          The native macOS interface for PPG
        </p>
      </div>

      {/* Table of Contents */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">On this page</CardTitle>
        </CardHeader>
        <CardContent>
          <nav>
            <ul className="grid gap-1 sm:grid-cols-2">
              {tocItems.map((item) => (
                <li key={item.href}>
                  <a
                    href={item.href}
                    className="inline-block py-1 text-sm text-muted-foreground transition-colors hover:text-foreground"
                  >
                    {item.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        </CardContent>
      </Card>

      <Separator />

      {/* Installation */}
      <section className="space-y-6" id="installation">
        <div className="flex items-center gap-3">
          <SectionIcon>
            <Download className="size-5" />
          </SectionIcon>
          <h2>Installation</h2>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Terminal className="size-4" />
                Via CLI
              </CardTitle>
              <CardDescription>
                Downloads the latest release to <code>/Applications</code>
              </CardDescription>
            </CardHeader>
            <CardContent>
              <pre>
                <code>ppg install-dashboard</code>
              </pre>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Download className="size-4" />
                Via GitHub
              </CardTitle>
              <CardDescription>
                Download directly from the Releases page
              </CardDescription>
            </CardHeader>
            <CardContent>
              <a
                href="https://github.com/jonfleming/ppg-cli/releases"
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-primary underline underline-offset-4 hover:text-primary/80"
              >
                github.com/jonfleming/ppg-cli/releases
              </a>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <FolderOpen className="size-4" />
                Manual Location
              </CardTitle>
              <CardDescription>
                Install to a custom directory
              </CardDescription>
            </CardHeader>
            <CardContent>
              <pre>
                <code>ppg install-dashboard --dir ~/Desktop</code>
              </pre>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Apple className="size-4" />
                Requirements
              </CardTitle>
              <CardDescription>
                System requirements for the dashboard
              </CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-sm text-muted-foreground">
                macOS 14 (Sonoma) or later
              </p>
            </CardContent>
          </Card>
        </div>
      </section>

      <Separator />

      {/* Main Interface */}
      <section className="space-y-10" id="main-interface">
        <div className="flex items-center gap-3">
          <SectionIcon>
            <Monitor className="size-5" />
          </SectionIcon>
          <h2>Main Interface</h2>
        </div>

        <Screenshot label="Dashboard main interface" />

        {/* Overview Tab */}
        <div className="space-y-4" id="overview-tab">
          <h3>Overview Tab</h3>
          <p className="text-muted-foreground">
            Shows all active worktrees and their agents at a glance.
          </p>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Eye className="size-4" />
                Real-time Status Badges
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex flex-wrap gap-2">
                <Badge className="bg-green-600 text-white hover:bg-green-600">
                  running
                </Badge>
                <Badge className="bg-blue-600 text-white hover:bg-blue-600">
                  completed
                </Badge>
                <Badge variant="destructive">failed</Badge>
                <Badge variant="secondary">killed</Badge>
                <Badge className="bg-amber-600 text-white hover:bg-amber-600">
                  lost
                </Badge>
              </div>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li>
                  <strong className="text-foreground">Quick actions</strong> —
                  kill agent, attach to pane, view diff
                </li>
              </ul>
            </CardContent>
          </Card>

          <Screenshot label="Overview tab with worktree list" />
        </div>

        {/* Workspace View */}
        <div className="space-y-4" id="workspace-view">
          <h3>Workspace View</h3>
          <p className="text-muted-foreground">
            Detailed view of a single worktree and its agents.
          </p>

          <div className="grid gap-4 sm:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Agent Details</CardTitle>
                <CardDescription>
                  Status, type, and start time for each agent
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="space-y-1.5 text-sm text-muted-foreground">
                  <li>Agent list with real-time status</li>
                  <li>Agent type and configuration</li>
                  <li>Start time and duration</li>
                </ul>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-base">Live Logs</CardTitle>
                <CardDescription>
                  Stream output directly from tmux panes
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="space-y-1.5 text-sm text-muted-foreground">
                  <li>Real-time log streaming</li>
                  <li>Scrollback history</li>
                  <li>Per-agent log isolation</li>
                </ul>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-base">Diff Viewer</CardTitle>
                <CardDescription>
                  See changes made by agents
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="space-y-1.5 text-sm text-muted-foreground">
                  <li>Side-by-side diff view</li>
                  <li>File-level change summary</li>
                  <li>Syntax highlighting</li>
                </ul>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <GitMerge className="size-4" />
                  Merge Controls
                </CardTitle>
                <CardDescription>
                  Merge completed work back to the base branch
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="space-y-1.5 text-sm text-muted-foreground">
                  <li>
                    Squash merge (<code>--squash</code>)
                  </li>
                  <li>
                    No-ff merge (<code>--no-ff</code>)
                  </li>
                  <li>Conflict detection and resolution hints</li>
                </ul>
              </CardContent>
            </Card>
          </div>

          <Screenshot label="Workspace view with agent details and diff" />
        </div>

        {/* Command Palette */}
        <div className="space-y-4" id="command-palette">
          <h3>Command Palette</h3>
          <p className="text-muted-foreground">
            Quick-access command palette for common actions.
          </p>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Command className="size-4" />
                Actions
              </CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="space-y-1.5 text-sm text-muted-foreground">
                <li>Spawn new agents with custom prompts</li>
                <li>Kill running agents</li>
                <li>Run swarm workflows</li>
                <li>Keyboard shortcut accessible</li>
              </ul>
            </CardContent>
          </Card>

          <Screenshot label="Command palette overlay" />
        </div>

        {/* Prompts Editor */}
        <div className="space-y-4" id="prompts-editor">
          <h3>Prompts Editor</h3>
          <p className="text-muted-foreground">
            Visual editor for prompt templates in{" "}
            <code>.ppg/prompts/</code>.
          </p>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <FileText className="size-4" />
                Features
              </CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="space-y-1.5 text-sm text-muted-foreground">
                <li>Markdown editing with live preview</li>
                <li>
                  Template variable highlighting (
                  <code>{"{{VAR}}"}</code> syntax)
                </li>
                <li>Save and apply templates directly</li>
              </ul>
            </CardContent>
          </Card>

          <Screenshot label="Prompts editor with markdown preview" />
        </div>

        {/* Swarms Editor */}
        <div className="space-y-4" id="swarms-editor">
          <h3>Swarms Editor</h3>
          <p className="text-muted-foreground">
            Visual editor for swarm definitions in{" "}
            <code>.ppg/swarms/</code>.
          </p>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Network className="size-4" />
                Features
              </CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="space-y-1.5 text-sm text-muted-foreground">
                <li>Multi-agent workflow configuration</li>
                <li>YAML editing with validation</li>
                <li>Visual agent dependency mapping</li>
              </ul>
            </CardContent>
          </Card>

          <Screenshot label="Swarms editor with YAML validation" />
        </div>

        {/* Schedules */}
        <div className="space-y-4" id="schedules">
          <h3>Schedules</h3>
          <p className="text-muted-foreground">
            View and manage cron-based automation schedules.
          </p>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Clock className="size-4" />
                Features
              </CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="space-y-1.5 text-sm text-muted-foreground">
                <li>Next run time display</li>
                <li>Enable / disable individual schedules</li>
                <li>Create new schedules with the UI</li>
                <li>Cron expression validation</li>
              </ul>
            </CardContent>
          </Card>

          <Screenshot label="Schedule manager with cron entries" />
        </div>
      </section>

      <Separator />

      {/* Settings */}
      <section className="space-y-4" id="settings">
        <div className="flex items-center gap-3">
          <SectionIcon>
            <Settings className="size-5" />
          </SectionIcon>
          <h2>Settings</h2>
        </div>

        <Card>
          <CardContent className="pt-6">
            <ul className="space-y-1.5 text-sm text-muted-foreground">
              <li>Configure default agent type</li>
              <li>Set project paths</li>
              <li>Theme preferences (follows system by default)</li>
            </ul>
          </CardContent>
        </Card>
      </section>

      <Separator />

      {/* Tips */}
      <section className="space-y-4" id="tips">
        <div className="flex items-center gap-3">
          <SectionIcon>
            <Lightbulb className="size-5" />
          </SectionIcon>
          <h2>Tips</h2>
        </div>

        <Card>
          <CardContent className="pt-6">
            <ul className="space-y-3 text-sm text-muted-foreground">
              <li>
                <strong className="text-foreground">
                  No server needed
                </strong>{" "}
                — the dashboard reads{" "}
                <code>.ppg/manifest.json</code> directly from disk.
              </li>
              <li>
                <strong className="text-foreground">
                  Instant sync
                </strong>{" "}
                — changes made via the CLI are instantly reflected in the
                dashboard.
              </li>
              <li>
                <strong className="text-foreground">
                  Multiple instances
                </strong>{" "}
                — multiple dashboards can monitor the same project
                simultaneously.
              </li>
              <li>
                <strong className="text-foreground">
                  Fully decoupled
                </strong>{" "}
                — the dashboard and CLI are independent. Use either or both.
              </li>
            </ul>
          </CardContent>
        </Card>
      </section>

      <Separator />

      {/* Architecture Note */}
      <section className="space-y-4" id="architecture">
        <div className="flex items-center gap-3">
          <SectionIcon>
            <Cpu className="size-5" />
          </SectionIcon>
          <h2>Architecture Note</h2>
        </div>

        <Card>
          <CardContent className="pt-6">
            <ul className="space-y-3 text-sm text-muted-foreground">
              <li>
                <strong className="text-foreground">
                  Built with Swift and SwiftUI
                </strong>{" "}
                — native macOS performance and look-and-feel.
              </li>
              <li>
                <strong className="text-foreground">
                  FSEvents file watching
                </strong>{" "}
                — watches <code>manifest.json</code> for changes with
                near-zero overhead.
              </li>
              <li>
                <strong className="text-foreground">
                  No IPC, no WebSocket
                </strong>{" "}
                — pure filesystem-based communication between CLI and dashboard.
              </li>
              <li>
                <strong className="text-foreground">Lightweight</strong> —
                less than 5 MB app size.
              </li>
            </ul>
          </CardContent>
        </Card>
      </section>
    </div>
  );
}
