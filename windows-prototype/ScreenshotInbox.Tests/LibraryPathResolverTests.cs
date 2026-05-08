using ScreenshotInbox.CoreBridge.Services;
using Xunit;

namespace ScreenshotInbox.Tests;

public sealed class LibraryPathResolverTests
{
    [Fact]
    public void ResolveManagedPathCombinesRelativeLibraryPathWithRoot()
    {
        var resolver = new LibraryPathResolver(Path.Combine("C:", "Library"));

        var resolved = resolver.ResolveManagedPath("Originals/2026/04/example.png");

        Assert.EndsWith(Path.Combine("Library", "Originals", "2026", "04", "example.png"), resolved);
    }

    [Fact]
    public void WarnsWhenLibraryPathIsAbsolute()
    {
        var resolver = new LibraryPathResolver(Path.Combine("C:", "Library"));

        var warnings = resolver.PortabilityWarnings(Path.Combine("C:", "Users", "me", "image.png"), null);

        Assert.Contains(warnings, warning => warning.Contains("library_path is absolute", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void WarnsWhenOriginalPathLooksMacSpecific()
    {
        var resolver = new LibraryPathResolver(Path.Combine("C:", "Library"));

        var warnings = resolver.PortabilityWarnings("Originals/2026/04/example.png", "/Users/aery/Desktop/example.png");

        Assert.Contains(warnings, warning => warning.Contains("original_path looks macOS-specific", StringComparison.OrdinalIgnoreCase));
    }
}
