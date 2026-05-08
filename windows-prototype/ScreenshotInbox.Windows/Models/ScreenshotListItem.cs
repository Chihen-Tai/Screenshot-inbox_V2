using ScreenshotInbox.CoreBridge.Models;

namespace ScreenshotInbox.Windows.Models;

public sealed class ScreenshotListItem
{
    public ScreenshotListItem(ScreenshotRecord record)
    {
        Record = record;
    }

    public ScreenshotRecord Record { get; }
    public string Filename => Record.Filename;
    public string SizeText => $"{Record.Width} x {Record.Height}";
    public string ImportedText => Record.ImportedAt.LocalDateTime.ToString("yyyy-MM-dd HH:mm");
    public string FavoriteText => Record.IsFavorite ? "Favorite" : string.Empty;
    public string TrashText => Record.IsTrashed ? "Trashed" : string.Empty;
    public string? ThumbnailPath => Record.SmallThumbnailExists
        ? Record.SmallThumbnailPath
        : Record.ManagedImageExists
            ? Record.ManagedImagePath
            : null;
}
