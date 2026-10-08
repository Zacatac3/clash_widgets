import SwiftUI

extension View {
    @ViewBuilder
    func minimizeTabBarOnScrollIfAvailable(forceExpanded: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(forceExpanded ? .never : .onScrollDown)
        } else {
            self
        }
    }

    func adaptivePanelPresentation() -> some View {
        self.presentationDetents([.large])
            .presentationCompactAdaptation(horizontal: .sheet, vertical: .sheet)
            .presentationSizing(.page)
    }

    @ViewBuilder
    func monitorScenePhase(_ scenePhase: ScenePhase, handler: @escaping (ScenePhase) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: scenePhase) { _, newPhase in
                handler(newPhase)
            }
        } else {
            onChange(of: scenePhase) { newPhase in
                handler(newPhase)
            }
        }
    }

    @ViewBuilder
    func onChangeCompat<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}


private struct TabBarExpansionRequestKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var tabBarExpansionRequest: (Bool) -> Void {
        get { self[TabBarExpansionRequestKey.self] }
        set { self[TabBarExpansionRequestKey.self] = newValue }
    }
}

extension View {
    func trackTabBarScrollDirection() -> some View {
        modifier(TabBarScrollDirectionModifier())
    }
}

private struct TabBarScrollGeometry: Equatable {
    let offset: Double
    let viewportHeight: Double
}

private struct TabBarScrollDirectionModifier: ViewModifier {
    @Environment(\.tabBarExpansionRequest) private var requestExpansion
    @State private var isUserScrolling = false
    @State private var tracker = TabBarScrollDirectionTracker()

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    let userScrolling = phase == .interacting || phase == .decelerating
                    if userScrolling && !isUserScrolling { tracker.reset() }
                    isUserScrolling = userScrolling
                }
                .onScrollGeometryChange(for: TabBarScrollGeometry.self) { geometry in
                    TabBarScrollGeometry(
                        offset: Double(max(0, geometry.contentOffset.y + geometry.contentInsets.top)),
                        viewportHeight: Double(max(1, geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom))
                    )
                } action: { _, geometry in
                    guard isUserScrolling,
                          let expanded = tracker.update(offset: geometry.offset, viewportHeight: geometry.viewportHeight) else { return }
                    requestExpansion(expanded)
                }
        } else {
            content
        }
    }
}
