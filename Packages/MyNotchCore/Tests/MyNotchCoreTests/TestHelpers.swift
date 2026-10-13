import SwiftUI
@testable import MyNotchCore

func activity(_ id: String, _ priority: ActivityPriority = .normal, expiresAfter: Duration? = nil) -> LiveActivity {
    LiveActivity(id: id, priority: priority, expiresAfter: expiresAfter, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()))
}
