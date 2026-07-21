namespace JellyfinVlcBridge.Core;

public static class BridgeLinks
{
    public const string ChromeWebStoreExtensionId = "hkjbodgdbjhignhlbecchiigcfigpidp";
    public const string DevelopmentExtensionId = "hpbbmehpokomkjfnemlbdlalbmckmkld";
    public const string ChromeWebStoreUrl =
        "https://chromewebstore.google.com/detail/" + ChromeWebStoreExtensionId;
    public const string GitHubRepository = "cryser66/jellyfin-vlc-bridge";
    public const string GitHubRepositoryUrl = "https://github.com/" + GitHubRepository;
    public const string GitHubLatestReleaseApiUrl =
        "https://api.github.com/repos/" + GitHubRepository + "/releases/latest";

    public static IReadOnlyList<string> AllowedExtensionIds { get; } =
        [ChromeWebStoreExtensionId, DevelopmentExtensionId];
}
