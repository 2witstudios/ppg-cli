using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PPGDesktop.Models;
using PPGDesktop.Services;

namespace PPGDesktop.ViewModels;

public partial class SettingsViewModel : ObservableObject
{
    private readonly SettingsService _settingsService;
    private readonly PpgApiClient _api;
    private readonly WebSocketService _ws;

    [ObservableProperty]
    private string _serverUrl = "http://localhost:3000";

    [ObservableProperty]
    private string _token = "";

    [ObservableProperty]
    private string _terminalFontFamily = "Cascadia Code";

    [ObservableProperty]
    private int _terminalFontSize = 14;

    [ObservableProperty]
    private string _appearance = "dark";

    [ObservableProperty]
    private string? _connectionTestResult;

    [ObservableProperty]
    private bool _isTesting;

    [ObservableProperty]
    private bool _isSaved;

    public string[] FontFamilies { get; } =
    [
        "Cascadia Code",
        "Cascadia Mono",
        "Consolas",
        "Courier New",
        "Fira Code",
        "JetBrains Mono",
        "Source Code Pro",
    ];

    public string[] Appearances { get; } = ["dark", "light", "system"];

    public SettingsViewModel(SettingsService settingsService, PpgApiClient api, WebSocketService ws)
    {
        _settingsService = settingsService;
        _api = api;
        _ws = ws;
        LoadSettings();
    }

    private void LoadSettings()
    {
        var settings = _settingsService.Load();
        ServerUrl = settings.ServerUrl;
        Token = settings.Token ?? "";
        TerminalFontFamily = settings.TerminalFontFamily;
        TerminalFontSize = settings.TerminalFontSize;
        Appearance = settings.Appearance;
    }

    [RelayCommand]
    private void Save()
    {
        var settings = new AppSettings
        {
            ServerUrl = ServerUrl,
            Token = string.IsNullOrWhiteSpace(Token) ? null : Token,
            TerminalFontFamily = TerminalFontFamily,
            TerminalFontSize = TerminalFontSize,
            Appearance = Appearance,
        };

        _settingsService.Save(settings);
        _api.Configure(settings.ServerUrl, settings.Token);

        IsSaved = true;
        Task.Delay(2000).ContinueWith(_ =>
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() => IsSaved = false);
        });
    }

    [RelayCommand]
    private async Task TestConnectionAsync()
    {
        IsTesting = true;
        ConnectionTestResult = null;

        try
        {
            // Temporarily configure with current values
            _api.Configure(ServerUrl, string.IsNullOrWhiteSpace(Token) ? null : Token);
            var (success, message) = await _api.TestConnectionAsync();
            ConnectionTestResult = success ? $"OK: {message}" : $"Failed: {message}";
        }
        catch (Exception ex)
        {
            ConnectionTestResult = $"Error: {ex.Message}";
        }
        finally
        {
            IsTesting = false;
        }
    }

    [RelayCommand]
    private async Task ReconnectAsync()
    {
        Save();
        var settings = _settingsService.Load();
        await _ws.ConnectAsync(settings.ServerUrl, settings.Token);
    }
}
