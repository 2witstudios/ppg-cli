"use client"

import { useState } from "react"
import Link from "next/link"
import { usePathname } from "next/navigation"
import { BookOpen, Bot, Layers, Menu, Monitor, Terminal } from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"

const sidebarLinks = [
  { href: "/docs", label: "Getting Started", icon: BookOpen },
  { href: "/docs/concepts", label: "Concepts", icon: Layers },
  { href: "/docs/dashboard", label: "Dashboard", icon: Monitor },
  { href: "/docs/cli", label: "CLI Reference", icon: Terminal },
  { href: "/docs/conductor", label: "Conductor Mode", icon: Bot },
] as const

function SidebarNav({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname()

  return (
    <nav className="flex flex-col gap-1">
      {sidebarLinks.map(({ href, label, icon: Icon }) => {
        const isActive = pathname === href

        return (
          <Link
            key={href}
            href={href}
            onClick={onNavigate}
            className={cn(
              "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
              isActive
                ? "bg-accent text-accent-foreground"
                : "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
            )}
          >
            <Icon className="size-4 shrink-0" />
            {label}
          </Link>
        )
      })}
    </nav>
  )
}

export default function DocsLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const [open, setOpen] = useState(false)

  return (
    <div className="mx-auto flex max-w-7xl">
      {/* Desktop sidebar */}
      <aside className="hidden w-64 shrink-0 border-r lg:block">
        <div className="sticky top-14 overflow-y-auto py-6 pr-4 pl-4">
          <p className="mb-4 px-3 text-xs font-semibold tracking-wider text-muted-foreground uppercase">
            Documentation
          </p>
          <SidebarNav />
        </div>
      </aside>

      {/* Mobile doc nav */}
      <div className="sticky top-14 z-40 flex h-12 w-full items-center border-b bg-background/80 px-4 backdrop-blur lg:hidden">
        <Button
          variant="ghost"
          size="sm"
          className="gap-2"
          onClick={() => setOpen(true)}
        >
          <Menu className="size-4" />
          Docs Menu
        </Button>
      </div>

      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="left">
          <SheetHeader>
            <SheetTitle className="font-mono tracking-tight">
              Documentation
            </SheetTitle>
          </SheetHeader>
          <div className="px-4">
            <SidebarNav onNavigate={() => setOpen(false)} />
          </div>
        </SheetContent>
      </Sheet>

      {/* Content area */}
      <div className="min-w-0 flex-1">
        <div className="mx-auto max-w-4xl px-4 py-8 sm:px-6 sm:py-12 lg:px-8">
          {children}
        </div>
      </div>
    </div>
  )
}
