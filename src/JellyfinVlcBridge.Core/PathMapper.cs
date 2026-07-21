namespace JellyfinVlcBridge.Core;

public static class PathMapper
{
    public static string Map(string serverPath, IEnumerable<PathMapping> mappings)
    {
        foreach (var mapping in mappings.OrderByDescending(x => x.ServerPrefix.Length))
        {
            if (!serverPath.StartsWith(mapping.ServerPrefix, StringComparison.OrdinalIgnoreCase)) continue;
            var remainder = serverPath[mapping.ServerPrefix.Length..].TrimStart('\\', '/');
            return Path.Combine(mapping.ClientPrefix, remainder);
        }
        throw new InvalidOperationException($"Aucun mapping SMB ne correspond au chemin serveur : {serverPath}");
    }
}
