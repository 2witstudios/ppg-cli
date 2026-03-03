using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace PPGDesktop.Services;

public static class TokenStorage
{
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "PPG Desktop", "credentials.dat");

    public static void SaveToken(string token)
    {
        var encrypted = ProtectedData.Protect(
            Encoding.UTF8.GetBytes(token),
            null,
            DataProtectionScope.CurrentUser);

        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        File.WriteAllBytes(FilePath, encrypted);
    }

    public static string? LoadToken()
    {
        if (!File.Exists(FilePath)) return null;

        try
        {
            var encrypted = File.ReadAllBytes(FilePath);
            var decrypted = ProtectedData.Unprotect(
                encrypted,
                null,
                DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(decrypted);
        }
        catch
        {
            return null;
        }
    }

    public static void ClearToken()
    {
        if (File.Exists(FilePath))
            File.Delete(FilePath);
    }
}
