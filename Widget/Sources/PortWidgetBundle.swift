import WidgetKit
import SwiftUI

/// `@main` for the Port widget extension. WidgetBundle is required
/// even when shipping a single widget — adding more (per-protocol /
/// per-process) means just appending to `body`.
@main
struct PortWidgetBundle: WidgetBundle {
    var body: some Widget {
        PortOpenWidget()
    }
}
