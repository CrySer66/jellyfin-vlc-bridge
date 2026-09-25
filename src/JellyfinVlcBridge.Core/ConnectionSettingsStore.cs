namespace JellyfinVlcBridge.Core;

public static class ConnectionSettingsStore
{
    // The caller supplies a persistent store: an environment override must not
    // replace the saved credential when a failed setup is rolled back.
    public static void Save(BridgeConfig config, string token, ISecretStore credentialStore, string? configPath = null)
    {
        var validated = config.Validate();
        if (string.IsNullOrWhiteSpace(token))
            throw new ArgumentException("Le jeton Jellyfin est absent.", nameof(token));
        var key = SecretKeys.ForServer(validated.ServerUrl);
        var previousToken = credentialStore.Read(key);
        credentialStore.Write(key, token);
        try
        {
            validated.Save(configPath);
        }
        catch (Exception saveError)
        {
            try
            {
                if (previousToken is null) credentialStore.Delete(key);
                else credentialStore.Write(key, previousToken);
            }
            catch (Exception rollbackError)
            {
                throw new InvalidOperationException(
                    "La configuration n’a pas été enregistrée et l’ancienne connexion n’a pas pu être restaurée. Relancez Quick Connect.",
                    new AggregateException(saveError, rollbackError));
            }
            throw;
        }
    }
}
