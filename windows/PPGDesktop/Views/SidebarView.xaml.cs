using System.Windows;
using System.Windows.Controls;
using PPGDesktop.ViewModels;

namespace PPGDesktop.Views;

public partial class SidebarView : UserControl
{
    public SidebarView()
    {
        InitializeComponent();
    }

    private void TreeView_SelectedItemChanged(object sender, RoutedPropertyChangedEventArgs<object> e)
    {
        if (DataContext is SidebarViewModel vm)
        {
            vm.SelectedItem = e.NewValue;
        }
    }
}
