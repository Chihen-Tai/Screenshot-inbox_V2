using Avalonia.Controls;
using Avalonia.Platform.Storage;
using ScreenshotInbox.Windows.ViewModels;

namespace ScreenshotInbox.Windows;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private async void OpenLibrary_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Choose Screenshot Inbox Library",
            AllowMultiple = false
        });

        var folder = folders.FirstOrDefault();
        if (folder?.Path.LocalPath is { Length: > 0 } path &&
            DataContext is MainWindowViewModel viewModel)
        {
            viewModel.OpenLibrary(path);
        }
    }
}
