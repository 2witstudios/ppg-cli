using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PPGDesktop.Services;

namespace PPGDesktop.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly PpgApiClient _api;
    private readonly WebSocketService _ws;
    private readonly SettingsService _settings;

    [ObservableProperty]
    private SidebarViewModel _sidebar;

    [ObservableProperty]
    private object? _currentView;

    [ObservableProperty]
    private string _connectionState = "disconnected";

    [ObservableProperty]
    private string _title = "PPG Desktop";

    public HomeDashboardViewModel HomeDashboard { get; }
    public SettingsViewModel Settings { get; }

    public MainViewModel(
        PpgApiClient api,
        WebSocketService ws,
        SettingsService settings,
        SidebarViewModel sidebar,
        HomeDashboardViewModel homeDashboard,
        SettingsViewModel settingsVm)
    {
        _api = api;
        _ws = ws;
        _settings = settings;
        _sidebar = sidebar;
        HomeDashboard = homeDashboard;
        Settings = settingsVm;

        // Default view
        CurrentView = HomeDashboard;

        // Wire up WebSocket state
        _ws.ConnectionStateChanged += state =>
        {
            ConnectionState = state;
            Title = state == "connected" ? "PPG Desktop — Connected" : "PPG Desktop";
        };

        // Wire up manifest updates to sidebar
        _ws.ManifestUpdated += manifest => sidebar.UpdateFromManifest(manifest);
        _ws.AgentStatusChanged += (agentId, status) => sidebar.UpdateAgentStatus(agentId, status);
    }

    [RelayCommand]
    private void NavigateHome()
    {
        CurrentView = HomeDashboard;
    }

    [RelayCommand]
    private void NavigateSettings()
    {
        CurrentView = Settings;
    }

    public event Action? SpawnDialogRequested;

    [RelayCommand]
    private void ShowSpawnDialog()
    {
        SpawnDialogRequested?.Invoke();
    }

    [RelayCommand]
    private async Task RefreshAsync()
    {
        try
        {
            var status = await _api.GetStatusAsync();
            if (status is not null)
            {
                Sidebar.UpdateFromStatus(status);
                await HomeDashboard.RefreshAsync();
            }
        }
        catch
        {
            // Connection error — handled by connection state display
        }
    }

    [RelayCommand]
    private async Task ReconnectAsync()
    {
        var appSettings = _settings.Load();
        _api.Configure(appSettings.ServerUrl, appSettings.Token);
        await _ws.ConnectAsync(appSettings.ServerUrl, appSettings.Token);
    }
}
