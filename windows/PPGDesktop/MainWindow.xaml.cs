using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using PPGDesktop.ViewModels;

namespace PPGDesktop;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;

    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;

        // Wire sidebar selection to navigation
        viewModel.Sidebar.AgentSelected += agent =>
        {
            var terminalVm = App.Services.GetRequiredService<TerminalViewModel>();
            viewModel.CurrentView = terminalVm;
            _ = terminalVm.AttachAsync(agent.Id, agent.DisplayName);
        };

        viewModel.Sidebar.WorktreeSelected += worktree =>
        {
            viewModel.CurrentView = worktree;
        };

        // Wire spawn dialog to open as modal
        viewModel.SpawnDialogRequested += ShowSpawnDialog;
    }

    private void ShowSpawnDialog()
    {
        var vm = App.Services.GetRequiredService<SpawnDialogViewModel>();
        var dialog = new Views.SpawnDialog { Owner = this, DataContext = vm };
        vm.SpawnCompleted += () => dialog.DialogResult = true;
        vm.DialogClosed += () => dialog.DialogResult = false;
        dialog.ShowDialog();
    }
}
