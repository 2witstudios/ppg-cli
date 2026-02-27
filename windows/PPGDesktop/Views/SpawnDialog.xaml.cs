using System.Windows;
using System.Windows.Input;
using PPGDesktop.Models;
using PPGDesktop.ViewModels;

namespace PPGDesktop.Views;

public partial class SpawnDialog : Window
{
    public SpawnDialog()
    {
        InitializeComponent();
    }

    private void VariantCard_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: AgentVariant variant }
            && DataContext is SpawnDialogViewModel vm)
        {
            vm.SelectVariantCommand.Execute(variant);
        }
    }
}
