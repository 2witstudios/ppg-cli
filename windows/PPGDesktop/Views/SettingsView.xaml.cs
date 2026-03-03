using System.Windows;
using System.Windows.Controls;
using PPGDesktop.ViewModels;

namespace PPGDesktop.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        // PasswordBox doesn't support binding, so sync manually
        if (DataContext is SettingsViewModel vm && !string.IsNullOrEmpty(vm.Token))
        {
            TokenBox.Password = vm.Token;
        }
    }

    private void TokenBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is SettingsViewModel vm)
        {
            vm.Token = TokenBox.Password;
        }
    }
}
