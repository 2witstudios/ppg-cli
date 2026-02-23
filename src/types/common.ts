export interface CommandResult<T = void> {
  success: boolean;
  data?: T;
  error?: string;
}

export interface GlobalOptions {
  json?: boolean;
  verbose?: boolean;
  cwd?: string;
}
