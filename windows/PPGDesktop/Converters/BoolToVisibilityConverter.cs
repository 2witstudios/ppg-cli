using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace PPGDesktop.Converters;

public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var invert = parameter as string == "invert";
        var isVisible = value switch
        {
            bool b => b,
            int i => i > 0,
            string s => !string.IsNullOrEmpty(s),
            null => false,
            _ => true
        };

        if (invert) isVisible = !isVisible;
        return isVisible ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
