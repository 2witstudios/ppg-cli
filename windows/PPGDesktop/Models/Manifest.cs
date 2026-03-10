using System.Text.Json.Serialization;

namespace PPGDesktop.Models;

public record Manifest(
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("projectRoot")] string ProjectRoot,
    [property: JsonPropertyName("sessionName")] string SessionName,
    [property: JsonPropertyName("worktrees")] Dictionary<string, WorktreeEntry> Worktrees,
    [property: JsonPropertyName("createdAt")] string CreatedAt,
    [property: JsonPropertyName("updatedAt")] string UpdatedAt
);

public record WorktreeEntry(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("path")] string Path,
    [property: JsonPropertyName("branch")] string Branch,
    [property: JsonPropertyName("baseBranch")] string BaseBranch,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("tmuxWindow")] string TmuxWindow,
    [property: JsonPropertyName("prUrl")] string? PrUrl,
    [property: JsonPropertyName("agents")] Dictionary<string, AgentEntry> Agents,
    [property: JsonPropertyName("createdAt")] string CreatedAt,
    [property: JsonPropertyName("mergedAt")] string? MergedAt
);

public record AgentEntry(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("agentType")] string AgentType,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("tmuxTarget")] string TmuxTarget,
    [property: JsonPropertyName("prompt")] string Prompt,
    [property: JsonPropertyName("startedAt")] string StartedAt,
    [property: JsonPropertyName("exitCode")] int? ExitCode,
    [property: JsonPropertyName("sessionId")] string? SessionId
);

public record StatusResponse(
    [property: JsonPropertyName("session")] string Session,
    [property: JsonPropertyName("worktrees")] Dictionary<string, WorktreeEntry> Worktrees
);

public record SpawnRequest(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("agent")] string? Agent = null,
    [property: JsonPropertyName("prompt")] string? Prompt = null,
    [property: JsonPropertyName("template")] string? Template = null,
    [property: JsonPropertyName("vars")] Dictionary<string, string>? Vars = null,
    [property: JsonPropertyName("base")] string? Base = null,
    [property: JsonPropertyName("count")] int? Count = null
);

public record SpawnResponse(
    [property: JsonPropertyName("worktreeId")] string WorktreeId,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("branch")] string Branch,
    [property: JsonPropertyName("agents")] List<SpawnedAgent> Agents
);

public record SpawnedAgent(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("tmuxTarget")] string TmuxTarget,
    [property: JsonPropertyName("sessionId")] string? SessionId
);

public record AgentLogsResponse(
    [property: JsonPropertyName("agentId")] string AgentId,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("tmuxTarget")] string TmuxTarget,
    [property: JsonPropertyName("lines")] int Lines,
    [property: JsonPropertyName("output")] string Output
);

public record SendKeysRequest(
    [property: JsonPropertyName("text")] string Text,
    [property: JsonPropertyName("mode")] string Mode = "with-enter"
);

public record RestartRequest(
    [property: JsonPropertyName("prompt")] string? Prompt = null,
    [property: JsonPropertyName("agent")] string? Agent = null
);

public record RestartResponse(
    [property: JsonPropertyName("success")] bool Success,
    [property: JsonPropertyName("oldAgentId")] string OldAgentId,
    [property: JsonPropertyName("newAgent")] NewAgentInfo NewAgent
);

public record NewAgentInfo(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("tmuxTarget")] string TmuxTarget,
    [property: JsonPropertyName("sessionId")] string? SessionId,
    [property: JsonPropertyName("worktreeId")] string WorktreeId,
    [property: JsonPropertyName("worktreeName")] string WorktreeName,
    [property: JsonPropertyName("branch")] string Branch,
    [property: JsonPropertyName("path")] string Path
);

public record MergeRequest(
    [property: JsonPropertyName("strategy")] string? Strategy = null,
    [property: JsonPropertyName("cleanup")] bool? Cleanup = null,
    [property: JsonPropertyName("force")] bool? Force = null
);

public record ConfigResponse(
    [property: JsonPropertyName("sessionName")] string SessionName,
    [property: JsonPropertyName("defaultAgent")] string DefaultAgent,
    [property: JsonPropertyName("agents")] List<AgentConfig> Agents,
    [property: JsonPropertyName("envFiles")] List<string> EnvFiles,
    [property: JsonPropertyName("symlinkNodeModules")] bool SymlinkNodeModules
);

public record AgentConfig(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("command")] string Command,
    [property: JsonPropertyName("promptFlag")] string? PromptFlag,
    [property: JsonPropertyName("promptFileFlag")] string? PromptFileFlag,
    [property: JsonPropertyName("interactive")] bool Interactive
);

public record DiffResponse(
    [property: JsonPropertyName("worktreeId")] string WorktreeId,
    [property: JsonPropertyName("branch")] string Branch,
    [property: JsonPropertyName("baseBranch")] string BaseBranch,
    [property: JsonPropertyName("files")] List<DiffFile> Files
);

public record DiffFile(
    [property: JsonPropertyName("file")] string File,
    [property: JsonPropertyName("added")] int Added,
    [property: JsonPropertyName("removed")] int Removed
);

public record HealthResponse(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("uptime")] double Uptime,
    [property: JsonPropertyName("version")] string Version
);

public record ErrorResponse(
    [property: JsonPropertyName("error")] string Error,
    [property: JsonPropertyName("code")] string? Code
);
