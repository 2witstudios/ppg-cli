using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using PPGDesktop.Services;
using PPGDesktop.ViewModels;

namespace PPGDesktop;

public partial class App : Application
{
    private ServiceProvider? _serviceProvider;

    public static ServiceProvider Services { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var services = new ServiceCollection();

        // Services
        services.AddSingleton<SettingsService>();
        services.AddSingleton<PpgApiClient>(sp =>
        {
            var settings = sp.GetRequiredService<SettingsService>();
            var appSettings = settings.Load();
            return new PpgApiClient(appSettings.ServerUrl, appSettings.Token);
        });
        services.AddSingleton<WebSocketService>();

        // ViewModels
        services.AddSingleton<MainViewModel>();
        services.AddSingleton<SidebarViewModel>();
        services.AddSingleton<HomeDashboardViewModel>();
        services.AddTransient<TerminalViewModel>();
        services.AddTransient<SpawnDialogViewModel>();
        services.AddSingleton<SettingsViewModel>();

        // Windows
        services.AddSingleton<MainWindow>();

        _serviceProvider = services.BuildServiceProvider();
        Services = _serviceProvider;

        var mainWindow = _serviceProvider.GetRequiredService<MainWindow>();
        mainWindow.Show();

        // Start WebSocket connection
        _ = StartServicesAsync();
    }

    private async Task StartServicesAsync()
    {
        var settings = Services.GetRequiredService<SettingsService>().Load();
        if (!string.IsNullOrEmpty(settings.ServerUrl))
        {
            var ws = Services.GetRequiredService<WebSocketService>();
            await ws.ConnectAsync(settings.ServerUrl, settings.Token);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        var ws = _serviceProvider?.GetService<WebSocketService>();
        ws?.Dispose();
        _serviceProvider?.Dispose();
        base.OnExit(e);
    }
}
