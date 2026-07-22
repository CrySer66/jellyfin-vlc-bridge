namespace JellyfinVlcBridge.Core;

public static class PathMapper
{
    public static string Map(string serverPath, IEnumerable<PathMapping> mappings)
    {
        if (string.IsNullOrWhiteSpace(serverPath))
            throw new ArgumentException("Le chemin serveur est vide.", nameof(serverPath));

        foreach (var mapping in mappings
            .Where(mapping => !string.IsNullOrWhiteSpace(mapping.ServerPrefix) && !string.IsNullOrWhiteSpace(mapping.ClientPrefix))
            .OrderByDescending(x => x.ServerPrefix.Length))
        {
            var prefix = mapping.ServerPrefix.TrimEnd('\\', '/');
            if (!IsPathPrefix(serverPath, prefix)) continue;
            var remainder = serverPath[prefix.Length..].TrimStart('\\', '/');
            return Path.Combine(mapping.ClientPrefix, remainder);
        }
        throw new InvalidOperationException($"Aucun mapping SMB ne correspond au chemin serveur : {serverPath}");
    }

    private static bool IsPathPrefix(string path, string prefix)
    {
        if (path.Equals(prefix, StringComparison.OrdinalIgnoreCase)) return true;
        if (!path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || path.Length <= prefix.Length) return false;
        return path[prefix.Length] is '\\' or '/';
    }
}
