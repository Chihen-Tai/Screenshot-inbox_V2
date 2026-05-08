using Microsoft.Data.Sqlite;
using ScreenshotInbox.CoreBridge.Models;

namespace ScreenshotInbox.CoreBridge.Services;

public sealed class ScreenshotLibraryReader
{
    public LibraryOpenResult OpenReadOnly(string libraryRoot, string? searchQuery = null)
    {
        var resolver = new LibraryPathResolver(libraryRoot);
        var warnings = new List<string>();
        if (!File.Exists(resolver.DatabasePath))
        {
            throw new FileNotFoundException("Screenshot Inbox database not found.", resolver.DatabasePath);
        }

        var screenshots = ReadScreenshots(resolver, searchQuery, warnings);
        return new LibraryOpenResult(resolver.LibraryRoot, resolver.DatabasePath, screenshots, warnings);
    }

    private static IReadOnlyList<ScreenshotRecord> ReadScreenshots(
        LibraryPathResolver resolver,
        string? searchQuery,
        List<string> libraryWarnings)
    {
        var records = new List<ScreenshotRecord>();
        var builder = new SqliteConnectionStringBuilder
        {
            DataSource = resolver.DatabasePath,
            Mode = SqliteOpenMode.ReadOnly,
            Cache = SqliteCacheMode.Shared
        };

        using var connection = new SqliteConnection(builder.ToString());
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT
                s.uuid,
                s.filename,
                s.library_path,
                s.original_path,
                s.file_hash,
                s.width,
                s.height,
                s.file_size,
                s.format,
                s.source_app,
                s.created_at,
                s.imported_at,
                s.modified_at,
                s.is_favorite,
                s.is_trashed,
                s.trash_date,
                s.sort_index,
                o.text
            FROM screenshots s
            LEFT JOIN ocr_results o ON o.screenshot_uuid = s.uuid
            WHERE $query IS NULL
               OR s.filename LIKE '%' || $query || '%' COLLATE NOCASE
               OR o.text LIKE '%' || $query || '%' COLLATE NOCASE
            ORDER BY s.imported_at DESC, s.filename ASC;
            """;
        command.Parameters.AddWithValue("$query", string.IsNullOrWhiteSpace(searchQuery) ? DBNull.Value : searchQuery);

        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            var uuid = GetString(reader, 0) ?? string.Empty;
            var filename = GetString(reader, 1) ?? "(unnamed)";
            var libraryPath = GetString(reader, 2);
            var originalPath = GetString(reader, 3);
            var managedPath = resolver.ResolveManagedPath(libraryPath);
            var smallThumbnail = resolver.SmallThumbnailPath(uuid);
            var largeThumbnail = resolver.LargeThumbnailPath(uuid);
            var portabilityWarnings = resolver.PortabilityWarnings(libraryPath, originalPath);
            foreach (var warning in portabilityWarnings)
            {
                libraryWarnings.Add($"{filename}: {warning}");
            }

            records.Add(new ScreenshotRecord(
                Uuid: uuid,
                Filename: filename,
                LibraryPath: libraryPath,
                OriginalPath: originalPath,
                FileHash: GetString(reader, 4),
                Width: GetInt(reader, 5),
                Height: GetInt(reader, 6),
                FileSize: GetLong(reader, 7),
                Format: GetString(reader, 8) ?? string.Empty,
                SourceApp: GetString(reader, 9),
                CreatedAt: FromUnixSeconds(GetDouble(reader, 10)),
                ImportedAt: FromUnixSeconds(GetDouble(reader, 11)),
                ModifiedAt: FromUnixSeconds(GetDouble(reader, 12)),
                IsFavorite: GetLong(reader, 13) != 0,
                IsTrashed: GetLong(reader, 14) != 0,
                TrashDate: reader.IsDBNull(15) ? null : FromUnixSeconds(GetDouble(reader, 15)),
                SortIndex: GetInt(reader, 16),
                OcrText: GetString(reader, 17),
                ManagedImagePath: managedPath,
                SmallThumbnailPath: smallThumbnail,
                LargeThumbnailPath: largeThumbnail,
                ManagedImageExists: managedPath is not null && File.Exists(managedPath),
                SmallThumbnailExists: File.Exists(smallThumbnail),
                LargeThumbnailExists: File.Exists(largeThumbnail),
                PortabilityWarnings: portabilityWarnings
            ));
        }

        return records;
    }

    private static string? GetString(SqliteDataReader reader, int ordinal)
    {
        return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    }

    private static int GetInt(SqliteDataReader reader, int ordinal)
    {
        return Convert.ToInt32(GetLong(reader, ordinal));
    }

    private static long GetLong(SqliteDataReader reader, int ordinal)
    {
        return reader.IsDBNull(ordinal) ? 0 : reader.GetInt64(ordinal);
    }

    private static double GetDouble(SqliteDataReader reader, int ordinal)
    {
        return reader.IsDBNull(ordinal) ? 0 : reader.GetDouble(ordinal);
    }

    private static DateTimeOffset FromUnixSeconds(double seconds)
    {
        return DateTimeOffset.FromUnixTimeMilliseconds(Convert.ToInt64(seconds * 1000));
    }
}
