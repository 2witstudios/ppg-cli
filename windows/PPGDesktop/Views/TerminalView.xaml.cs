using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Core;
using PPGDesktop.Terminal;
using PPGDesktop.ViewModels;

namespace PPGDesktop.Views;

public partial class TerminalView : UserControl
{
    private TerminalBridge? _bridge;

    public TerminalView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        DataContextChanged += OnDataContextChanged;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await InitializeWebViewAsync();
    }

    private async Task InitializeWebViewAsync()
    {
        try
        {
            var env = await CoreWebView2Environment.CreateAsync();
            await TerminalWebView.EnsureCoreWebView2Async(env);

            var terminalHtmlPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Terminal", "terminal.html");
            if (File.Exists(terminalHtmlPath))
            {
                TerminalWebView.CoreWebView2.Navigate(new Uri(terminalHtmlPath).AbsoluteUri);
            }

            if (DataContext is TerminalViewModel vm)
            {
                _bridge = new TerminalBridge(TerminalWebView, vm);
            }
        }
        catch
        {
            // WebView2 runtime may not be installed
        }
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is TerminalViewModel vm && TerminalWebView.CoreWebView2 is not null)
        {
            _bridge?.Dispose();
            _bridge = new TerminalBridge(TerminalWebView, vm);
        }
    }
}
