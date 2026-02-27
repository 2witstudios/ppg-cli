using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using PPGDesktop.Models;

namespace PPGDesktop.Services;

public class PpgApiClient : IDisposable
{
    private readonly HttpClient _http;
    private string _baseUrl;
    private string? _token;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public PpgApiClient(string baseUrl, string? token)
    {
        _baseUrl = baseUrl.TrimEnd('/');
        _token = token;
        _http = new HttpClient();
        UpdateAuth();
    }

    public void Configure(string baseUrl, string? token)
    {
        _baseUrl = baseUrl.TrimEnd('/');
        _token = token;
        UpdateAuth();
    }

    private void UpdateAuth()
    {
        _http.DefaultRequestHeaders.Authorization = !string.IsNullOrEmpty(_token)
            ? new AuthenticationHeaderValue("Bearer", _token)
            : null;
    }

    // Health (no auth required)
    public async Task<HealthResponse?> GetHealthAsync(CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{_baseUrl}/health", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<HealthResponse>(JsonOptions, ct);
    }

    // Status
    public async Task<StatusResponse?> GetStatusAsync(CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{_baseUrl}/api/status", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<StatusResponse>(JsonOptions, ct);
    }

    // Worktrees
    public async Task<WorktreeEntry?> GetWorktreeAsync(string id, CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{_baseUrl}/api/worktrees/{id}", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<WorktreeEntry>(JsonOptions, ct);
    }

    public async Task<DiffResponse?> GetWorktreeDiffAsync(string id, CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{_baseUrl}/api/worktrees/{id}/diff", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<DiffResponse>(JsonOptions, ct);
    }

    public async Task MergeWorktreeAsync(string id, MergeRequest? request = null, CancellationToken ct = default)
    {
        var response = await _http.PostAsJsonAsync($"{_baseUrl}/api/worktrees/{id}/merge", request ?? new MergeRequest(), JsonOptions, ct);
        response.EnsureSuccessStatusCode();
    }

    public async Task KillWorktreeAsync(string id, CancellationToken ct = default)
    {
        var response = await _http.PostAsync($"{_baseUrl}/api/worktrees/{id}/kill", null, ct);
        response.EnsureSuccessStatusCode();
    }

    // Spawn
    public async Task<SpawnResponse?> SpawnAsync(SpawnRequest request, CancellationToken ct = default)
    {
        var response = await _http.PostAsJsonAsync($"{_baseUrl}/api/spawn", request, JsonOptions, ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<SpawnResponse>(JsonOptions, ct);
    }

    // Agent operations
    public async Task<AgentLogsResponse?> GetAgentLogsAsync(string id, int lines = 200, CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{_baseUrl}/api/agents/{id}/logs?lines={lines}", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<AgentLogsResponse>(JsonOptions, ct);
    }

    public async Task SendKeysAsync(string agentId, string text, string mode = "with-enter", CancellationToken ct = default)
    {
        var request = new SendKeysRequest(text, mode);
        var response = await _http.PostAsJsonAsync($"{_baseUrl}/api/agents/{agentId}/send", request, JsonOptions, ct);
        response.EnsureSuccessStatusCode();
    }

    public async Task KillAgentAsync(string agentId, CancellationToken ct = default)
    {
        var response = await _http.PostAsync($"{_baseUrl}/api/agents/{agentId}/kill", null, ct);
        response.EnsureSuccessStatusCode();
    }

    public async Task<RestartResponse?> RestartAgentAsync(string agentId, RestartRequest? request = null, CancellationToken ct = default)
    {
        var response = await _http.PostAsJsonAsync($"{_baseUrl}/api/agents/{agentId}/restart", request ?? new RestartRequest(), JsonOptions, ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<RestartResponse>(JsonOptions, ct);
    }

    // Config
    public async Task<ConfigResponse?> GetConfigAsync(CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"{_baseUrl}/api/config", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<ConfigResponse>(JsonOptions, ct);
    }

    // Test connection
    public async Task<(bool Success, string Message)> TestConnectionAsync(CancellationToken ct = default)
    {
        try
        {
            var health = await GetHealthAsync(ct);
            if (health is null) return (false, "No response from server");
            return (true, $"Connected — v{health.Version}, uptime {health.Uptime:F0}s");
        }
        catch (HttpRequestException ex)
        {
            return (false, $"Connection failed: {ex.Message}");
        }
        catch (TaskCanceledException)
        {
            return (false, "Connection timed out");
        }
    }

    public void Dispose()
    {
        _http.Dispose();
        GC.SuppressFinalize(this);
    }
}
