using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using PPGDesktop.Models;
using PPGDesktop.Services;

namespace PPGDesktop.ViewModels;

public partial class HomeDashboardViewModel : ObservableObject
{
    private readonly PpgApiClient _api;
    private readonly WebSocketService _ws;

    [ObservableProperty]
    private int _runningCount;

    [ObservableProperty]
    private int _completedCount;

    [ObservableProperty]
    private int _failedCount;

    [ObservableProperty]
    private int _killedCount;

    [ObservableProperty]
    private int _totalWorktrees;

    [ObservableProperty]
    private string _connectionStatus = "Disconnected";

    [ObservableProperty]
    private ObservableCollection<CommitDay> _commitHeatmap = [];

    [ObservableProperty]
    private ObservableCollection<RecentCommit> _recentCommits = [];

    public HomeDashboardViewModel(PpgApiClient api, WebSocketService ws)
    {
        _api = api;
        _ws = ws;

        _ws.ManifestUpdated += OnManifestUpdated;
        _ws.ConnectionStateChanged += state => ConnectionStatus = state;

        InitializeHeatmap();
    }

    private void OnManifestUpdated(Manifest manifest)
    {
        var running = 0;
        var completed = 0;
        var failed = 0;
        var killed = 0;

        foreach (var wt in manifest.Worktrees.Values)
        {
            foreach (var agent in wt.Agents.Values)
            {
                switch (agent.Status)
                {
                    case "running": running++; break;
                    case "completed" or "exited": completed++; break;
                    case "failed" or "gone": failed++; break;
                    case "killed": killed++; break;
                }
            }
        }

        RunningCount = running;
        CompletedCount = completed;
        FailedCount = failed;
        KilledCount = killed;
        TotalWorktrees = manifest.Worktrees.Count;
    }

    private void InitializeHeatmap()
    {
        // Generate 91 days (13 weeks x 7 days) of empty data
        var today = DateTime.Today;
        var startOfWeek = today.AddDays(-(int)today.DayOfWeek);
        var start = startOfWeek.AddDays(-12 * 7);

        for (var d = start; d <= today; d = d.AddDays(1))
        {
            CommitHeatmap.Add(new CommitDay(d, 0, 0));
        }
    }

    public async Task RefreshAsync()
    {
        try
        {
            var status = await _api.GetStatusAsync();
            if (status is not null)
            {
                var manifest = new Manifest(
                    1, "", status.Session, status.Worktrees,
                    DateTime.UtcNow.ToString("o"), DateTime.UtcNow.ToString("o"));
                OnManifestUpdated(manifest);
            }
        }
        catch
        {
            // Ignore refresh errors
        }
    }
}

public record CommitDay(DateTime Date, int Count, int Level);

public record RecentCommit(string Hash, string Message, string RelativeTime, string Author);
