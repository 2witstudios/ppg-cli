import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import {
  Check,
  Download,
  ExternalLink,
  Info,
  Monitor,
  Terminal,
} from "lucide-react";

export const metadata = {
  title: "Download & Install — PPG",
  description:
    "Get the PPG dashboard app and CLI tool. Visual agent management for macOS.",
};

export default function DownloadPage() {
  return (
    <div className="py-16 sm:py-24">
      <div className="mx-auto max-w-4xl px-4 sm:px-6">
        {/* Page Header */}
        <div className="mb-12 text-center">
          <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
            Download &amp; Install
          </h1>
          <p className="mt-3 text-lg text-muted-foreground">
            Get the PPG dashboard app and CLI tool
          </p>
        </div>

        {/* Primary Card: macOS Dashboard App */}
        <Card className="mb-8 border-primary/20">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                <Monitor className="h-5 w-5 text-primary" />
              </div>
              <div className="flex-1">
                <CardTitle className="text-xl">
                  PPG Dashboard for macOS
                </CardTitle>
                <CardDescription className="mt-1">
                  Native macOS app for visual agent management. Real-time status
                  monitoring, spawn controls, log streaming, diff viewer, and
                  merge actions — all in one window.
                </CardDescription>
              </div>
              <Badge variant="secondary">macOS 14+</Badge>
            </div>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Screenshot placeholder */}
            <div className="flex aspect-video items-center justify-center rounded-xl border bg-muted">
              <span className="text-sm text-muted-foreground">
                Dashboard Screenshot
              </span>
            </div>

            {/* Install methods */}
            <div className="space-y-4">
              <div>
                <h3 className="mb-2 text-sm font-medium">
                  Install via CLI{" "}
                  <Badge variant="outline" className="ml-1.5">
                    Preferred
                  </Badge>
                </h3>
                <pre className="rounded-lg border bg-muted px-4 py-3">
                  <code className="text-sm">ppg install-dashboard</code>
                </pre>
              </div>

              <div>
                <h3 className="mb-2 text-sm font-medium">Manual Download</h3>
                <Button variant="outline" size="sm" asChild>
                  <a
                    href="https://github.com/jonfleming/ppg-cli/releases"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    <Download className="mr-2 h-4 w-4" />
                    Download from GitHub Releases
                    <ExternalLink className="ml-2 h-3 w-3" />
                  </a>
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Secondary Card: CLI Installation */}
        <Card className="mb-12">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-muted">
                <Terminal className="h-5 w-5" />
              </div>
              <div>
                <CardTitle className="text-xl">PPG CLI</CardTitle>
                <CardDescription className="mt-1">
                  Command-line tool for orchestrating parallel AI agents
                </CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <ol className="space-y-3">
              <li className="flex items-start gap-3">
                <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-medium text-primary-foreground">
                  1
                </span>
                <pre className="flex-1 rounded-lg border bg-muted px-4 py-3">
                  <code className="text-sm">npm install -g ppg-cli</code>
                </pre>
              </li>
              <li className="flex items-start gap-3">
                <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-medium text-primary-foreground">
                  2
                </span>
                <pre className="flex-1 rounded-lg border bg-muted px-4 py-3">
                  <code className="text-sm">
                    cd your-project &amp;&amp; ppg init
                  </code>
                </pre>
              </li>
              <li className="flex items-start gap-3">
                <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-medium text-primary-foreground">
                  3
                </span>
                <pre className="flex-1 rounded-lg border bg-muted px-4 py-3">
                  <code className="text-sm">
                    ppg spawn --name my-task --prompt &quot;Your task here&quot;
                  </code>
                </pre>
              </li>
            </ol>

            <Separator className="my-6" />

            <div>
              <h3 className="mb-3 text-sm font-medium text-muted-foreground">
                Requirements
              </h3>
              <div className="flex flex-wrap gap-2">
                <Badge variant="outline">Node.js 20+</Badge>
                <Badge variant="outline">git</Badge>
                <Badge variant="outline">
                  tmux
                  <span className="ml-1 text-muted-foreground">
                    — brew install tmux
                  </span>
                </Badge>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Prerequisites Checklist */}
        <div className="mb-12">
          <h2 className="mb-6 text-2xl font-semibold tracking-tight">
            Prerequisites
          </h2>
          <div className="grid gap-3 sm:grid-cols-2">
            {[
              {
                label: "macOS",
                detail: "Apple Silicon or Intel",
              },
              {
                label: "Node.js 20",
                detail: "or later",
              },
              {
                label: "git",
                detail: "pre-installed on macOS",
              },
              {
                label: "tmux",
                detail: "brew install tmux",
              },
            ].map((item) => (
              <div
                key={item.label}
                className="flex items-center gap-3 rounded-lg border px-4 py-3"
              >
                <Check className="h-4 w-4 shrink-0 text-primary" />
                <span className="text-sm font-medium">{item.label}</span>
                <span className="text-sm text-muted-foreground">
                  {item.detail}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Quick Start */}
        <div className="mb-12">
          <h2 className="mb-6 text-2xl font-semibold tracking-tight">
            Quick Start
          </h2>
          <div className="space-y-2">
            {[
              "npm install -g ppg-cli",
              "cd my-project",
              "ppg init",
              "ppg spawn --name first-task --prompt 'Add a README'",
              "ppg ui",
            ].map((cmd, i) => (
              <div key={i} className="flex items-center gap-3">
                <span className="w-6 text-right text-xs text-muted-foreground">
                  {i + 1}
                </span>
                <pre className="flex-1 rounded-lg border bg-muted px-4 py-2.5">
                  <code className="text-sm">{cmd}</code>
                </pre>
              </div>
            ))}
            <p className="ml-9 mt-2 text-sm text-muted-foreground">
              Step 5 opens the PPG Dashboard for visual management.
            </p>
          </div>
        </div>

        {/* Integration Note */}
        <Card className="border-dashed">
          <CardContent className="flex items-start gap-3 pt-6">
            <Info className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              Works with Claude Code, OpenAI Codex, and any CLI-based AI agent.
              PPG is agent-agnostic by design.
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
