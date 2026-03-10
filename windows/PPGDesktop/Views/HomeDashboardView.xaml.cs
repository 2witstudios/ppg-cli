using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using PPGDesktop.ViewModels;

namespace PPGDesktop.Views;

public partial class HomeDashboardView : UserControl
{
    private static readonly Color[] HeatmapColors =
    [
        (Color)ColorConverter.ConvertFromString("#ebedf0"),
        (Color)ColorConverter.ConvertFromString("#9be9a8"),
        (Color)ColorConverter.ConvertFromString("#40c463"),
        (Color)ColorConverter.ConvertFromString("#30a14e"),
        (Color)ColorConverter.ConvertFromString("#216e39"),
    ];

    public HomeDashboardView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        RenderHeatmap();

        if (DataContext is HomeDashboardViewModel vm)
        {
            vm.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName == nameof(HomeDashboardViewModel.CommitHeatmap))
                    RenderHeatmap();
            };
        }
    }

    private void RenderHeatmap()
    {
        HeatmapCanvas.Children.Clear();

        if (DataContext is not HomeDashboardViewModel vm) return;

        const double cellSize = 14;
        const double gap = 2;
        var dayIndex = 0;

        foreach (var day in vm.CommitHeatmap)
        {
            var col = dayIndex / 7;
            var row = dayIndex % 7;

            var rect = new Rectangle
            {
                Width = cellSize,
                Height = cellSize,
                RadiusX = 2,
                RadiusY = 2,
                Fill = new SolidColorBrush(HeatmapColors[Math.Clamp(day.Level, 0, 4)]),
                ToolTip = $"{day.Date:yyyy-MM-dd}: {day.Count} commits"
            };

            Canvas.SetLeft(rect, col * (cellSize + gap));
            Canvas.SetTop(rect, row * (cellSize + gap));
            HeatmapCanvas.Children.Add(rect);

            dayIndex++;
        }
    }
}
