namespace ScreenshotInbox.CoreBridge.Services;

public sealed class LibraryPathResolver
{
    public string LibraryRoot { get; }

    public LibraryPathResolver(string libraryRoot)
    {
        LibraryRoot = Path.GetFullPath(libraryRoot);
    }

    public string DatabasePath => Path.Combine(LibraryRoot, "screenshot-inbox.sqlite");

    public string? ResolveManagedPath(string? storedPath)
    {
        if (string.IsNullOrWhiteSpace(storedPath))
        {
            return null;
        }

        if (IsWindowsAbsolutePath(storedPath))
        {
            return storedPath;
        }

        if (Path.IsPathRooted(storedPath))
        {
            return Path.GetFullPath(storedPath);
        }

        var normalized = storedPath
            .Replace('/', Path.DirectorySeparatorChar)
            .Replace('\\', Path.DirectorySeparatorChar);
        return Path.GetFullPath(Path.Combine(LibraryRoot, normalized));
    }

    public string SmallThumbnailPath(string uuid)
    {
        return Path.Combine(LibraryRoot, "Thumbnails", "small", $"{uuid.ToLowerInvariant()}.jpg");
    }

    public string LargeThumbnailPath(string uuid)
    {
        return Path.Combine(LibraryRoot, "Thumbnails", "large", $"{uuid.ToLowerInvariant()}.jpg");
    }

    public IReadOnlyList<string> PortabilityWarnings(string? libraryPath, string? originalPath)
    {
        var warnings = new List<string>();
        if (string.IsNullOrWhiteSpace(libraryPath))
        {
            warnings.Add("Missing library_path; managed image cannot be resolved.");
        }
        else if (IsAbsoluteStoredPath(libraryPath))
        {
            warnings.Add("library_path is absolute. Cross-platform libraries should store managed paths relative to the library root.");
        }

        if (!string.IsNullOrWhiteSpace(originalPath) && LooksLikeMacPath(originalPath))
        {
            warnings.Add("original_path looks macOS-specific. This is acceptable provenance, but Windows should not rely on it for the managed copy.");
        }

        return warnings;
    }

    private static bool LooksLikeMacPath(string path)
    {
        return path.StartsWith("/Users/", StringComparison.OrdinalIgnoreCase) ||
               path.StartsWith("/Volumes/", StringComparison.OrdinalIgnoreCase) ||
               path.StartsWith("/Applications/", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsAbsoluteStoredPath(string path)
    {
        if (Path.IsPathRooted(path))
        {
            return true;
        }

        return IsWindowsAbsolutePath(path);
    }

    private static bool IsWindowsAbsolutePath(string path)
    {
        return (path.Length >= 3 &&
                char.IsAsciiLetter(path[0]) &&
                path[1] == ':' &&
                (path[2] == '\\' || path[2] == '/')) ||
               path.StartsWith(@"\\", StringComparison.Ordinal);
    }
}
