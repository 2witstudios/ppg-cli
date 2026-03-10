using System.Text.Json;
using Microsoft.Web.WebView2.Wpf;
using PPGDesktop.ViewModels;

namespace PPGDesktop.Terminal;

public class TerminalBridge : IDisposable
{
    private readonly WebView2 _webView;
    private readonly TerminalViewModel _vm;
    private bool _disposed;
    private bool _ready;

    public TerminalBridge(WebView2 webView, TerminalViewModel vm)
    {
        _webView = webView;
        _vm = vm;

        _webView.WebMessageReceived += OnWebMessageReceived;
        _vm.OutputReceived += OnOutputReceived;
    }

    private async void OnWebMessageReceived(object? sender, Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            var json = e.WebMessageAsJson;
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var type = root.GetProperty("type").GetString();

            switch (type)
            {
                case "ready":
                    _ready = true;
                    break;

                case "input":
                    var data = root.GetProperty("data").GetString();
                    if (data is not null)
                        await _vm.SendInputAsync(data);
                    break;

                case "resize":
                    // Could forward resize info to server if needed
                    break;
            }
        }
        catch
        {
            // Ignore parse errors
        }
    }

    private void OnOutputReceived(string data)
    {
        if (!_ready || _disposed) return;

        try
        {
            var message = JsonSerializer.Serialize(new { type = "output", data });
            _webView.Dispatcher.Invoke(() =>
            {
                _webView.CoreWebView2?.PostWebMessageAsJson(message);
            });
        }
        catch
        {
            // WebView may be disposed
        }
    }

    public void SendClear()
    {
        if (!_ready || _disposed) return;

        try
        {
            var message = JsonSerializer.Serialize(new { type = "clear" });
            _webView.CoreWebView2.PostWebMessageAsJson(message);
        }
        catch
        {
            // WebView may be disposed
        }
    }

    public void Configure(string? fontFamily = null, int? fontSize = null)
    {
        if (!_ready || _disposed) return;

        try
        {
            var message = JsonSerializer.Serialize(new { type = "configure", fontFamily, fontSize });
            _webView.CoreWebView2.PostWebMessageAsJson(message);
        }
        catch
        {
            // WebView may be disposed
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _webView.WebMessageReceived -= OnWebMessageReceived;
        _vm.OutputReceived -= OnOutputReceived;
        GC.SuppressFinalize(this);
    }
}
