using CommunityToolkit.Mvvm.ComponentModel;
using PPGDesktop.Services;

namespace PPGDesktop.ViewModels;

public partial class TerminalViewModel : ObservableObject
{
    private readonly WebSocketService _ws;
    private readonly PpgApiClient _api;

    [ObservableProperty]
    private string _agentId = "";

    [ObservableProperty]
    private string _agentName = "";

    [ObservableProperty]
    private string _agentStatus = "";

    [ObservableProperty]
    private bool _isConnected;

    public event Action<string>? OutputReceived;

    public TerminalViewModel(PpgApiClient api, WebSocketService ws)
    {
        _api = api;
        _ws = ws;
    }

    public async Task AttachAsync(string agentId, string agentName)
    {
        // Detach from previous
        if (!string.IsNullOrEmpty(AgentId))
            await DetachAsync();

        AgentId = agentId;
        AgentName = agentName;

        _ws.TerminalOutput += OnTerminalOutput;

        // Subscribe to terminal events
        await _ws.SubscribeTerminalAsync(agentId);
        IsConnected = true;

        // Load initial log output
        try
        {
            var logs = await _api.GetAgentLogsAsync(agentId);
            if (logs is not null && !string.IsNullOrEmpty(logs.Output))
            {
                OutputReceived?.Invoke(logs.Output);
                AgentStatus = logs.Status;
            }
        }
        catch
        {
            // Agent may not be reachable
        }
    }

    public async Task DetachAsync()
    {
        if (string.IsNullOrEmpty(AgentId)) return;

        _ws.TerminalOutput -= OnTerminalOutput;
        await _ws.UnsubscribeTerminalAsync(AgentId);
        IsConnected = false;
        AgentId = "";
    }

    public async Task SendInputAsync(string data)
    {
        if (string.IsNullOrEmpty(AgentId)) return;
        await _ws.SendTerminalInputAsync(AgentId, data);
    }

    private void OnTerminalOutput(string agentId, string data)
    {
        if (agentId == AgentId)
            OutputReceived?.Invoke(data);
    }
}
