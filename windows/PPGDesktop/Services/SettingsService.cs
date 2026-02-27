using System.IO;
using System.Text.Json;
using PPGDesktop.Models;

namespace PPGDesktop.Services;

public class SettingsService
{
    private static readonly string SettingsDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "PPG Desktop");

    private static readonly string SettingsPath = Path.Combine(SettingsDir, "settings.json");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    private AppSettings? _cached;

    public AppSettings Load()
    {
        if (_cached is not null) return _cached;

        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                _cached = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
            }
            else
            {
                _cached = new AppSettings();
            }
        }
        catch
        {
            _cached = new AppSettings();
        }

        // Load token from secure storage
        var token = TokenStorage.LoadToken();
        if (token is not null)
            _cached.Token = token;

        return _cached;
    }

    public void Save(AppSettings settings)
    {
        _cached = settings;

        Directory.CreateDirectory(SettingsDir);

        // Save token separately in secure storage
        if (!string.IsNullOrEmpty(settings.Token))
        {
            TokenStorage.SaveToken(settings.Token);
        }

        // Don't write token to plain settings file
        var toSave = new AppSettings
        {
            ServerUrl = settings.ServerUrl,
            TerminalFontFamily = settings.TerminalFontFamily,
            TerminalFontSize = settings.TerminalFontSize,
            Appearance = settings.Appearance,
            RefreshInterval = settings.RefreshInterval,
            Connections = settings.Connections
        };

        var json = JsonSerializer.Serialize(toSave, JsonOptions);
        File.WriteAllText(SettingsPath, json);
    }
}
