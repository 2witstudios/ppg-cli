using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Windows;
using PPGDesktop.Models;

namespace PPGDesktop.Services;

public class WebSocketService : IDisposable
{
    private ClientWebSocket? _ws;
    private CancellationTokenSource? _cts;
    private int _reconnectAttempt;
    private bool _disposed;
    private string _url = "";
    private string? _token;
    private Timer? _pingTimer;

    public event Action<Manifest>? ManifestUpdated;
    public event Action<string, string>? AgentStatusChanged;
    public event Action<string, string>? WorktreeStatusChanged;
    public event Action<string, string>? TerminalOutput;
    public event Action<string>? ConnectionStateChanged;
    public event Action<string, string>? ErrorReceived;

    public string State { get; private set; } = "disconnected";

    public async Task ConnectAsync(string serverUrl, string? token)
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();

        var wsUrl = serverUrl.Replace("http://", "ws://").Replace("https://", "wss://").TrimEnd('/');
        _url = $"{wsUrl}/ws";
        _token = token;
        _reconnectAttempt = 0;

        await ConnectInternalAsync(_cts.Token);
    }

    private async Task ConnectInternalAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                SetState("connecting");
                _ws?.Dispose();
                _ws = new ClientWebSocket();

                var uri = string.IsNullOrEmpty(_token)
                    ? new Uri(_url)
                    : new Uri($"{_url}?token={Uri.EscapeDataString(_token)}");

                await _ws.ConnectAsync(uri, ct);
                _reconnectAttempt = 0;
                SetState("connected");

                StartPing(ct);
                await ReceiveLoopAsync(ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                StopPing();
                if (ct.IsCancellationRequested) break;

                _reconnectAttempt++;
                var delay = Math.Min(1000 * (1 << Math.Min(_reconnectAttempt, 5)), 30000);
                SetState($"reconnecting (attempt {_reconnectAttempt})");
                await Task.Delay(delay, ct);
            }
        }

        SetState("disconnected");
    }

    private async Task ReceiveLoopAsync(CancellationToken ct)
    {
        var buffer = new byte[65536];
        var messageBuffer = new List<byte>();

        while (_ws?.State == WebSocketState.Open && !ct.IsCancellationRequested)
        {
            var result = await _ws.ReceiveAsync(buffer, ct);

            if (result.MessageType == WebSocketMessageType.Close)
                break;

            messageBuffer.AddRange(buffer.AsSpan(0, result.Count).ToArray());

            if (result.EndOfMessage)
            {
                var json = Encoding.UTF8.GetString(messageBuffer.ToArray());
                messageBuffer.Clear();
                ProcessMessage(json);
            }
        }
    }

    private void ProcessMessage(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var type = root.GetProperty("type").GetString();

            Application.Current?.Dispatcher.Invoke(() =>
            {
                switch (type)
                {
                    case "manifest:updated":
                        if (root.TryGetProperty("manifest", out var manifestEl))
                        {
                            var manifest = JsonSerializer.Deserialize<Manifest>(manifestEl.GetRawText());
                            if (manifest is not null)
                                ManifestUpdated?.Invoke(manifest);
                        }
                        break;

                    case "agent:status":
                        var agentId = root.GetProperty("agentId").GetString() ?? "";
                        var status = root.GetProperty("status").GetString() ?? "";
                        AgentStatusChanged?.Invoke(agentId, status);
                        break;

                    case "worktree:status":
                        var wtId = root.GetProperty("worktreeId").GetString() ?? "";
                        var wtStatus = root.GetProperty("status").GetString() ?? "";
                        WorktreeStatusChanged?.Invoke(wtId, wtStatus);
                        break;

                    case "terminal:output":
                        var termAgentId = root.GetProperty("agentId").GetString() ?? "";
                        var data = root.GetProperty("data").GetString() ?? "";
                        TerminalOutput?.Invoke(termAgentId, data);
                        break;

                    case "error":
                        var code = root.TryGetProperty("code", out var codeEl) ? codeEl.GetString() ?? "" : "";
                        var message = root.GetProperty("message").GetString() ?? "";
                        ErrorReceived?.Invoke(code, message);
                        break;

                    case "pong":
                        break;
                }
            });
        }
        catch
        {
            // Ignore malformed messages
        }
    }

    public async Task SendAsync(object message, CancellationToken ct = default)
    {
        if (_ws?.State != WebSocketState.Open) return;

        var json = JsonSerializer.Serialize(message);
        var bytes = Encoding.UTF8.GetBytes(json);
        await _ws.SendAsync(bytes, WebSocketMessageType.Text, true, ct);
    }

    public Task SubscribeTerminalAsync(string agentId, CancellationToken ct = default)
        => SendAsync(new { type = "terminal:subscribe", agentId }, ct);

    public Task UnsubscribeTerminalAsync(string agentId, CancellationToken ct = default)
        => SendAsync(new { type = "terminal:unsubscribe", agentId }, ct);

    public Task SendTerminalInputAsync(string agentId, string data, CancellationToken ct = default)
        => SendAsync(new { type = "terminal:input", agentId, data }, ct);

    private void StartPing(CancellationToken ct)
    {
        StopPing();
        _pingTimer = new Timer(async _ =>
        {
            try { await SendAsync(new { type = "ping" }, ct); }
            catch { /* ignore */ }
        }, null, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(30));
    }

    private void StopPing()
    {
        _pingTimer?.Dispose();
        _pingTimer = null;
    }

    private void SetState(string state)
    {
        State = state;
        try
        {
            Application.Current?.Dispatcher.Invoke(() => ConnectionStateChanged?.Invoke(state));
        }
        catch
        {
            // App may be shutting down
        }
    }

    public async Task DisconnectAsync()
    {
        _cts?.Cancel();
        StopPing();

        if (_ws?.State == WebSocketState.Open)
        {
            try
            {
                await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", CancellationToken.None);
            }
            catch { /* ignore */ }
        }

        SetState("disconnected");
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _cts?.Cancel();
        StopPing();
        _ws?.Dispose();
        _cts?.Dispose();
        GC.SuppressFinalize(this);
    }
}
