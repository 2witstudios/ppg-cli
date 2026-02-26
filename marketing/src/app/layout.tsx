import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

import { ThemeProvider } from "@/components/theme-provider";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "PPG — Orchestrate AI Agents in Parallel",
  description:
    "Local orchestration runtime for parallel AI coding agents. Spawn, monitor, and merge agents from a native macOS dashboard.",
  openGraph: {
    title: "PPG — Orchestrate AI Agents in Parallel",
    description:
      "Local orchestration runtime for parallel AI coding agents. Spawn, monitor, and merge agents from a native macOS dashboard.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "PPG — Orchestrate AI Agents in Parallel",
    description:
      "Local orchestration runtime for parallel AI coding agents. Spawn, monitor, and merge agents from a native macOS dashboard.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        <ThemeProvider
          attribute="class"
          defaultTheme="dark"
          enableSystem
          disableTransitionOnChange
        >
          <div className="flex min-h-screen flex-col">
            <SiteHeader />
            <main className="flex-1">{children}</main>
            <SiteFooter />
          </div>
        </ThemeProvider>
      </body>
    </html>
  );
}
