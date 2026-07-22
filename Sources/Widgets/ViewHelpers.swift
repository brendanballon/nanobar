import Monitors
import SwiftUI

// MARK: - InteractiveRegion

/// Collects CGRects (in window/global coords) of interactive elements.
public struct InteractiveRegionKey: PreferenceKey {
    public static let defaultValue: [CGRect] = []
    public static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

public extension View {
    /// Reports this view's frame (in window coordinates) as an interactive region.
    func interactiveRegion() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: InteractiveRegionKey.self,
                    value: [geo.frame(in: .global)]
                )
            }
        )
    }
}

// MARK: - MonitorID environment key

private struct MonitorIDKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

public extension EnvironmentValues {
    var monitorID: Int {
        get { self[MonitorIDKey.self] }
        set { self[MonitorIDKey.self] = newValue }
    }
}

// MARK: - BarPosition environment key

private struct BarPositionKey: EnvironmentKey {
    static let defaultValue: BarPosition = .top
}

public extension EnvironmentValues {
    var barPosition: BarPosition {
        get { self[BarPositionKey.self] }
        set { self[BarPositionKey.self] = newValue }
    }
}
