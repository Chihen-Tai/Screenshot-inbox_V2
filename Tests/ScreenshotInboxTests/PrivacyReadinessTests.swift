import Foundation
import Testing
@testable import ScreenshotInbox

struct PrivacyReadinessTests {
    @Test
    func privacyCopyStatesLocalFirstGuarantee() {
        #expect(AppPrivacyInfo.localFirstGuarantee == "Screenshot Inbox is local-first. It does not upload your screenshots or OCR text to any server.")
        #expect(AppPrivacyInfo.noTelemetryStatement == "No telemetry or network services are included.")
        #expect(AppPrivacyInfo.watchedFoldersStatement == "Only configured watched folders are monitored.")
        #expect(AppPrivacyInfo.originalSourceSafetyStatement == "Original source files are not modified by default.")
        #expect(AppPrivacyInfo.managedLibraryDescription.contains("SQLite database"))
    }

    @Test
    func folderAccessServiceReturnsStableNonSandboxStatus() {
        let service = FolderAccessService()
        let url = URL(fileURLWithPath: "/tmp/screenshot-inbox-privacy-test", isDirectory: true)
        let access = service.resolveAccess(for: url)

        #expect(access.url == url.standardizedFileURL)
        #expect(access.isSecurityScoped == false)
        #expect(access.bookmarkData == nil)
        #expect(FolderAccessService.isSandboxEnabled == false)
    }
}
