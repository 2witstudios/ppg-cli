import Link from "next/link"
import { Github } from "lucide-react"

const footerLinks = [
  { href: "/", label: "Home" },
  { href: "/download", label: "Download" },
  { href: "/docs", label: "Docs" },
  {
    href: "https://github.com/jonfleming/ppg-cli",
    label: "GitHub",
    external: true,
  },
] as const

export function SiteFooter() {
  return (
    <footer className="border-t py-8">
      <div className="mx-auto max-w-7xl px-4 sm:px-6">
        {/* Top section */}
        <div className="flex flex-col gap-8 md:flex-row md:justify-between">
          {/* Brand */}
          <div className="space-y-2">
            <Link
              href="/"
              className="font-mono text-lg font-bold tracking-tight"
            >
              PPG
            </Link>
            <p className="text-muted-foreground text-sm">
              Orchestrate parallel AI coding agents from your terminal.
            </p>
          </div>

          {/* Links + install */}
          <div className="flex flex-col gap-8 sm:flex-row sm:gap-16">
            {/* Quick links */}
            <div className="space-y-3">
              <h4 className="text-sm font-semibold">Quick Links</h4>
              <ul className="space-y-2">
                {footerLinks.map(({ href, label, ...rest }) => {
                  const isExternal = "external" in rest && rest.external
                  return (
                    <li key={href}>
                      {isExternal ? (
                        <a
                          href={href}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-muted-foreground hover:text-foreground inline-flex items-center gap-1.5 text-sm transition-colors"
                        >
                          <Github className="size-3.5" />
                          {label}
                        </a>
                      ) : (
                        <Link
                          href={href}
                          className="text-muted-foreground hover:text-foreground text-sm transition-colors"
                        >
                          {label}
                        </Link>
                      )}
                    </li>
                  )
                })}
              </ul>
            </div>

            {/* Install snippet */}
            <div className="space-y-3">
              <h4 className="text-sm font-semibold">Install</h4>
              <pre className="bg-muted rounded-md px-3 py-2 font-mono text-sm">
                npm i -g ppg-cli
              </pre>
            </div>
          </div>
        </div>

        {/* Bottom */}
        <div className="text-muted-foreground mt-8 flex flex-col gap-2 border-t pt-6 text-xs sm:flex-row sm:items-center sm:justify-between">
          <p>&copy; 2025 PPG</p>
          <p>Local-first AI agent orchestration</p>
        </div>
      </div>
    </footer>
  )
}
