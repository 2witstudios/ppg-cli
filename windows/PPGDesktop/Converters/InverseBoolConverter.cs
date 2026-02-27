using System.Globalization;
using System.Windows.Data;

namespace PPGDesktop.Converters;

public class InverseBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        // Simple bool inversion
        if (value is bool b && parameter is null)
            return !b;

        // String equality check (for RadioButton binding)
        if (value is string s && parameter is string target)
            return s == target;

        // Bool with format parameter "TrueText|FalseText"
        if (value is bool bVal && parameter is string format && format.Contains('|'))
        {
            var parts = format.Split('|');
            return bVal ? parts[1] : parts[0];
        }

        return value;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        // Simple bool inversion
        if (value is bool b && parameter is null)
            return !b;

        // RadioButton: return the parameter string when checked
        if (value is bool isChecked && isChecked && parameter is string target)
            return target;

        return Binding.DoNothing;
    }
}
