namespace PPGDesktop.Models;

public record ServerConnection(
    string Url,
    string? Token,
    string Name = "Default"
);
