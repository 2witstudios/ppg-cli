using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;

namespace PPGDesktop.Converters;

public class StatusToColorConverter : IValueConverter
{
    private static readonly Dictionary<string, Color> StatusColors = new()
    {
        ["running"] = Color.FromRgb(52, 211, 153),    // emerald
        ["idle"] = Color.FromRgb(251, 191, 36),        // amber
        ["exited"] = Color.FromRgb(96, 165, 250),      // blue
        ["completed"] = Color.FromRgb(96, 165, 250),   // blue
        ["failed"] = Color.FromRgb(248, 113, 113),     // red
        ["gone"] = Color.FromRgb(156, 163, 175),       // gray
        ["killed"] = Color.FromRgb(251, 146, 60),      // orange
        ["spawning"] = Color.FromRgb(251, 191, 36),    // amber
        ["waiting"] = Color.FromRgb(251, 191, 36),     // amber
        ["lost"] = Color.FromRgb(156, 163, 175),       // gray
        ["active"] = Color.FromRgb(52, 211, 153),      // emerald
        ["merging"] = Color.FromRgb(167, 139, 250),    // violet
        ["merged"] = Color.FromRgb(96, 165, 250),      // blue
        ["cleaned"] = Color.FromRgb(156, 163, 175),    // gray
    };

    private static readonly Color DefaultColor = Color.FromRgb(156, 163, 175); // gray

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var status = value as string ?? "";
        var color = StatusColors.GetValueOrDefault(status.ToLowerInvariant(), DefaultColor);
        return new SolidColorBrush(color);
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
