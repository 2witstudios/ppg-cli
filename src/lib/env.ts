/**
 * Augmented environment for execa calls.
 *
 * On Apple Silicon Macs, Homebrew installs to /opt/homebrew/bin/ which may not
 * be in PATH when launched from non-login shells (IDEs, GUI apps, VSCode).
 * This ensures tmux, git, and other Homebrew-installed binaries are found.
 */

const extraDirs = [
  '/opt/homebrew/bin',
  '/opt/homebrew/sbin',
  '/opt/local/bin',        // MacPorts
];

const home = process.env.HOME ?? '';
if (home) {
  extraDirs.push(`${home}/.nix-profile/bin`);
}

const augmentedPath = [...extraDirs, process.env.PATH].filter(Boolean).join(':');

export const execaEnv = {
  env: { PATH: augmentedPath },
};
