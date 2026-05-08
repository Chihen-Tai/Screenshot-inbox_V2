namespace ScreenshotInbox.CoreBridge.Models;

public sealed record LibraryOpenResult(
    string LibraryRoot,
    string DatabasePath,
    IReadOnlyList<ScreenshotRecord> Screenshots,
    IReadOnlyList<string> Warnings
);
