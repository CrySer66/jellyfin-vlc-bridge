using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace JellyfinVlcBridge.Core;

public interface ISecretStore
{
    string? Read(string key);
    void Write(string key, string secret);
    void Delete(string key);
}

public sealed class EnvironmentOrWindowsCredentialStore : ISecretStore
{
    public string? Read(string key)
    {
        var fromEnvironment = Environment.GetEnvironmentVariable("JELLYFIN_VLC_TOKEN");
        if (!string.IsNullOrWhiteSpace(fromEnvironment)) return fromEnvironment;
        if (!OperatingSystem.IsWindows()) return null;

        if (!CredRead(key, 1, 0, out var pointer)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<CREDENTIAL>(pointer);
            if (credential.CredentialBlobSize == 0) return "";
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.Unicode.GetString(bytes);
        }
        finally { CredFree(pointer); }
    }

    public void Write(string key, string secret)
    {
        if (!OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("Sur Linux/macOS, utilisez temporairement JELLYFIN_VLC_TOKEN.");
        var bytes = Encoding.Unicode.GetBytes(secret);
        var blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new CREDENTIAL
            {
                Type = 1,
                TargetName = key,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = 2,
                UserName = "Jellyfin VLC Bridge"
            };
            if (!CredWrite(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        finally { Marshal.FreeCoTaskMem(blob); }
    }

    public void Delete(string key)
    {
        if (!OperatingSystem.IsWindows()) return;
        if (!CredDelete(key, 1, 0))
        {
            var error = Marshal.GetLastWin32Error();
            if (error != 1168) throw new Win32Exception(error); // ERROR_NOT_FOUND
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref CREDENTIAL credential, uint flags);
    [DllImport("advapi32", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);
}

public static class SecretKeys
{
    public static string ForServer(string serverUrl) => "JellyfinVlcBridge:" + new Uri(serverUrl).Authority.ToLowerInvariant();
}
