using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PPGDesktop.Models;
using PPGDesktop.Services;

namespace PPGDesktop.ViewModels;

public partial class SpawnDialogViewModel : ObservableObject
{
    private readonly PpgApiClient _api;

    [ObservableProperty]
    private ObservableCollection<AgentVariant> _variants = new(AgentVariant.BuiltIn);

    [ObservableProperty]
    private AgentVariant? _selectedVariant;

    [ObservableProperty]
    private string _worktreeName = "";

    [ObservableProperty]
    private string _prompt = "";

    [ObservableProperty]
    private int _agentCount = 1;

    [ObservableProperty]
    private bool _isSpawning;

    [ObservableProperty]
    private string? _errorMessage;

    [ObservableProperty]
    private bool _showPromptPhase;

    public event Action? SpawnCompleted;
    public event Action? DialogClosed;

    public SpawnDialogViewModel(PpgApiClient api)
    {
        _api = api;
        SelectedVariant = Variants.FirstOrDefault();
    }

    [RelayCommand]
    private void SelectVariant(AgentVariant variant)
    {
        SelectedVariant = variant;
        ShowPromptPhase = true;
    }

    [RelayCommand]
    private void GoBack()
    {
        ShowPromptPhase = false;
        ErrorMessage = null;
    }

    [RelayCommand]
    private async Task SpawnAsync()
    {
        if (SelectedVariant is null || string.IsNullOrWhiteSpace(WorktreeName))
        {
            ErrorMessage = "Name is required";
            return;
        }

        IsSpawning = true;
        ErrorMessage = null;

        try
        {
            var request = new SpawnRequest(
                Name: WorktreeName.Trim(),
                Agent: SelectedVariant.Id == "terminal" ? null : SelectedVariant.Id,
                Prompt: string.IsNullOrWhiteSpace(Prompt) ? null : Prompt.Trim(),
                Count: AgentCount > 1 ? AgentCount : null
            );

            await _api.SpawnAsync(request);
            SpawnCompleted?.Invoke();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsSpawning = false;
        }
    }

    [RelayCommand]
    private void Cancel()
    {
        DialogClosed?.Invoke();
    }
}
