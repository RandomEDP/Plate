import CloudKit
import PlateCore
import SwiftUI
import UIKit

/// Settings → Sharing: invite people to the household, see who's in it, or leave someone else's.
struct SharingSection: View {
    @Environment(CloudSync.self) private var cloud
    @State private var working = false
    @State private var error: String?
    @State private var confirmLeave = false

    var body: some View {
        @Bindable var cloud = cloud
        Section {
            Toggle("Share through iCloud", isOn: $cloud.enabled)
            if cloud.enabled {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(isProblem ? .orange : .secondary)
                switch cloud.scope {
                case .own:
                    ForEach(cloud.people, id: \.self) { Label($0, systemImage: "person.fill") }
                    Button {
                        invite()
                    } label: {
                        Label(cloud.people.isEmpty ? "Invite someone to this household" : "Invite or remove people",
                              systemImage: "person.badge.plus")
                    }
                    .disabled(working || !canShare)
                case .joined(_, let owner):
                    Label("You're in \(owner)'s household", systemImage: "house.fill")
                    ForEach(cloud.people, id: \.self) { Label($0, systemImage: "person.fill") }
                    Button("Leave this household", role: .destructive) { confirmLeave = true }
                        .disabled(working)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Sharing")
        } footer: {
            Text(footer)
        }
        .task { await cloud.loadPeople() }
        .confirmationDialog("Leave this household?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                working = true
                Task { await cloud.leave(); working = false }
            }
        } message: {
            Text("You'll keep a copy of everything on this phone, but you'll stop seeing their changes. They can invite you again.")
        }
    }

    private var canShare: Bool {
        if case .upToDate = cloud.status { return true }
        if case .working = cloud.status { return true }
        return false
    }

    private var isProblem: Bool {
        switch cloud.status {
        case .problem, .noAccount: return true
        default: return false
        }
    }

    private var statusText: String {
        switch cloud.status {
        case .off: return "Off on this device."
        case .starting: return "Connecting to iCloud…"
        case .working: return "Syncing…"
        case .noAccount: return "This device isn't signed in to iCloud, so Plate can't share. Sign in from the Settings app (your name at the top)."
        case .upToDate(let date):
            return "Up to date (checked \(date.formatted(date: .omitted, time: .shortened)))."
        case .problem(let text): return text
        }
    }

    private var footer: String {
        switch cloud.scope {
        case .own:
            return "Everyone you invite sees and changes the same kitchen, recipes, meal plan, shopping lists and home dashboard. Your other devices on the same iCloud account stay in step by themselves. Each person keeps their own food log, daily targets and AI setting."
        case .joined:
            return "You share this household's kitchen, recipes, meal plan, shopping lists and home dashboard. Your food log, daily targets and AI setting are yours."
        }
    }

    private func invite() {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let share = try await cloud.shareForInvite()
                SharingSheet.present(share: share, container: cloud.containerForSharing) {
                    Task { await cloud.loadPeople() }
                }
            } catch {
                self.error = CloudSync.explain(error)
            }
        }
    }
}

/// Apple's sheet for inviting people to a share and managing who's in it.
@MainActor
enum SharingSheet {
    private static var delegate: Delegate?

    static func present(share: CKShare, container: CKContainer, changed: @escaping () -> Void) {
        guard let top = topController() else { return }
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let d = Delegate(title: (share[CKShare.SystemFieldKey.title] as? String) ?? "Plate household", changed: changed)
        delegate = d
        controller.delegate = d
        controller.modalPresentationStyle = .formSheet
        if let pop = controller.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(controller, animated: true)
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let changed: () -> Void
        init(title: String, changed: @escaping () -> Void) { self.title = title; self.changed = changed }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            CloudSync.current?.reportShareProblem(error)
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { changed() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { changed() }
    }
}

/// Hands iCloud invite links to `CloudSync`. SwiftUI has no hook for them, so Plate gives its scenes this delegate.
final class PlateAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = PlateSceneDelegate.self
        return config
    }
}

final class PlateSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        // Plate was opened by tapping an invite.
        if let metadata = options.cloudKitShareMetadata { CloudSync.current?.received(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        CloudSync.current?.received(metadata)
    }
}
