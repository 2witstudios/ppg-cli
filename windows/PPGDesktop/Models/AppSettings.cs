using System.Text.Json.Serialization;

namespace PPGDesktop.Models;

public class AppSettings
{
    [JsonPropertyName("serverUrl")]
    public string ServerUrl { get; set; } = "http://localhost:3000";

    [JsonPropertyName("token")]
    public string? Token { get; set; }

    [JsonPropertyName("terminalFontFamily")]
    public string TerminalFontFamily { get; set; } = "Cascadia Code";

    [JsonPropertyName("terminalFontSize")]
    public int TerminalFontSize { get; set; } = 14;

    [JsonPropertyName("appearance")]
    public string Appearance { get; set; } = "dark";

    [JsonPropertyName("refreshInterval")]
    public double RefreshInterval { get; set; } = 2.0;

    [JsonPropertyName("connections")]
    public List<ServerConnection> Connections { get; set; } = [];
}
