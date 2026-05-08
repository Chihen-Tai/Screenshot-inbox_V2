using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using ScreenshotInbox.CoreBridge.Models;
using ScreenshotInbox.CoreBridge.Services;
using ScreenshotInbox.Windows.Models;

namespace ScreenshotInbox.Windows.ViewModels;

public sealed class MainWindowViewModel : INotifyPropertyChanged
{
    private readonly ScreenshotLibraryReader _reader = new();
    private readonly List<ScreenshotRecord> _allScreenshots = [];
    private string? _libraryPath;
    private string _searchText = string.Empty;
    private string _statusText = "Open a Screenshot Inbox library folder to begin.";
    private ScreenshotListItem? _selectedScreenshot;

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<ScreenshotListItem> Screenshots { get; } = [];
    public ObservableCollection<string> Warnings { get; } = [];

    public string? LibraryPath
    {
        get => _libraryPath;
        private set => SetField(ref _libraryPath, value);
    }

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetField(ref _searchText, value))
            {
                ApplySearch();
            }
        }
    }

    public string StatusText
    {
        get => _statusText;
        private set => SetField(ref _statusText, value);
    }

    public ScreenshotListItem? SelectedScreenshot
    {
        get => _selectedScreenshot;
        set => SetField(ref _selectedScreenshot, value);
    }

    public int ScreenshotCount => Screenshots.Count;

    public void OpenLibrary(string folderPath)
    {
        try
        {
            var result = _reader.OpenReadOnly(folderPath);
            LibraryPath = result.LibraryRoot;
            _allScreenshots.Clear();
            _allScreenshots.AddRange(result.Screenshots);
            Warnings.Clear();
            foreach (var warning in result.Warnings.Distinct())
            {
                Warnings.Add(warning);
            }
            SearchText = string.Empty;
            ApplySearch();
            StatusText = $"Opened read-only database: {result.DatabasePath}";
        }
        catch (Exception ex)
        {
            _allScreenshots.Clear();
            Screenshots.Clear();
            SelectedScreenshot = null;
            Warnings.Clear();
            StatusText = ex.Message;
            OnPropertyChanged(nameof(ScreenshotCount));
        }
    }

    private void ApplySearch()
    {
        var query = SearchText.Trim();
        var filtered = string.IsNullOrWhiteSpace(query)
            ? _allScreenshots
            : _allScreenshots.Where(s =>
                s.Filename.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                (s.OcrText?.Contains(query, StringComparison.OrdinalIgnoreCase) ?? false)).ToList();

        Screenshots.Clear();
        foreach (var record in filtered)
        {
            Screenshots.Add(new ScreenshotListItem(record));
        }
        SelectedScreenshot = Screenshots.FirstOrDefault();
        OnPropertyChanged(nameof(ScreenshotCount));
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
