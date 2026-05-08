using Microsoft.Data.Sqlite;
using ScreenshotInbox.CoreBridge.Services;
using Xunit;

namespace ScreenshotInbox.Tests;

public sealed class ScreenshotLibraryReaderTests
{
    [Fact]
    public void OpenReadOnlyLoadsScreenshotsAndFiltersByFilename()
    {
        var root = CreateLibrary();
        var dbPath = Path.Combine(root, "screenshot-inbox.sqlite");
        Directory.CreateDirectory(Path.Combine(root, "Originals", "2026", "04"));
        File.WriteAllText(Path.Combine(root, "Originals", "2026", "04", "one.png"), "image");
        CreateDatabase(dbPath);

        var reader = new ScreenshotLibraryReader();

        var all = reader.OpenReadOnly(root);
        var filtered = reader.OpenReadOnly(root, "invoice");

        Assert.Equal(2, all.Screenshots.Count);
        Assert.Single(filtered.Screenshots);
        Assert.Equal("invoice.png", filtered.Screenshots[0].Filename);
        Assert.True(filtered.Screenshots[0].ManagedImageExists);
        Assert.Empty(all.Warnings);
    }

    private static string CreateLibrary()
    {
        var root = Path.Combine(Path.GetTempPath(), "ScreenshotInboxWindowsReaderTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }

    private static void CreateDatabase(string dbPath)
    {
        using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = dbPath,
            Mode = SqliteOpenMode.ReadWriteCreate
        }.ToString());
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = """
            CREATE TABLE screenshots(
                uuid TEXT PRIMARY KEY,
                filename TEXT NOT NULL,
                library_path TEXT NOT NULL,
                file_hash TEXT NOT NULL,
                original_path TEXT,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                file_size INTEGER NOT NULL,
                format TEXT NOT NULL,
                source_app TEXT,
                created_at REAL NOT NULL,
                imported_at REAL NOT NULL,
                modified_at REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                is_trashed INTEGER NOT NULL DEFAULT 0,
                trash_date REAL,
                sort_index INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE ocr_results(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                screenshot_uuid TEXT NOT NULL UNIQUE,
                text TEXT,
                language TEXT,
                confidence REAL,
                status TEXT NOT NULL DEFAULT 'pending',
                error_message TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT
            );
            INSERT INTO screenshots(
                uuid, filename, library_path, file_hash, original_path,
                width, height, file_size, format, source_app,
                created_at, imported_at, modified_at,
                is_favorite, is_trashed, trash_date, sort_index
            ) VALUES
            ('00000000-0000-0000-0000-000000000001', 'invoice.png', 'Originals/2026/04/one.png', 'hash1', NULL, 100, 80, 5, 'PNG', NULL, 100, 200, 300, 1, 0, NULL, 0),
            ('00000000-0000-0000-0000-000000000002', 'notes.png', 'Originals/2026/04/missing.png', 'hash2', NULL, 100, 80, 5, 'PNG', NULL, 100, 100, 100, 0, 0, NULL, 1);
            INSERT INTO ocr_results(screenshot_uuid, text, language, confidence, status, created_at)
            VALUES ('00000000-0000-0000-0000-000000000002', 'meeting agenda', 'en-US', 0.9, 'complete', '2026-04-01');
            """;
        command.ExecuteNonQuery();
    }
}
