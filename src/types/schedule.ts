export interface ScheduleEntry {
  name: string;
  swarm?: string;
  prompt?: string;
  cron: string;
  vars?: Record<string, string>;
}

export interface SchedulesConfig {
  schedules: ScheduleEntry[];
}
