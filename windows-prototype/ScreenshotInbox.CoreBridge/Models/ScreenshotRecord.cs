namespace ScreenshotInbox.CoreBridge.Models;

public sealed record ScreenshotRecord(
    string Uuid,
    string Filename,
    string? LibraryPath,
    string? OriginalPath,
    string? FileHash,
    int Width,
    int Height,
    long FileSize,
    string Format,
    string? SourceApp,
    DateTimeOffset CreatedAt,
    DateTimeOffset ImportedAt,
    DateTimeOffset ModifiedAt,
    bool IsFavorite,
    bool IsTrashed,
    DateTimeOffset? TrashDate,
    int SortIndex,
    string? OcrText,
    string? ManagedImagePath,
    string? SmallThumbnailPath,
    string? LargeThumbnailPath,
    bool ManagedImageExists,
    bool SmallThumbnailExists,
    bool LargeThumbnailExists,
    IReadOnlyList<string> PortabilityWarnings
);
