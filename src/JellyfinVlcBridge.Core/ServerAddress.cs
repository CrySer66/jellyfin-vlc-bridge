namespace JellyfinVlcBridge.Core;

public static class ServerAddress
{
    public static string Normalize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("L'adresse Jellyfin est obligatoire.", nameof(value));

        if (!Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri) ||
            (!uri.Scheme.Equals(Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) &&
             !uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)) ||
            string.IsNullOrWhiteSpace(uri.Host))
            throw new ArgumentException("L'adresse Jellyfin doit être une adresse HTTP ou HTTPS complète.", nameof(value));

        if (!string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
            throw new ArgumentException("L'adresse Jellyfin ne doit pas contenir d'identifiants, de paramètres ni de fragment.", nameof(value));

        return uri.GetLeftPart(UriPartial.Path).TrimEnd('/');
    }
}
