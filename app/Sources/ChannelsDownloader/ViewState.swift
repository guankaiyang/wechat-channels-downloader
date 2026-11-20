import SwiftUI

/// The macOS 27 SDK resolves `@State` to a SwiftUI macro whose plugin ships only with Xcode.
/// Command Line Tools lack it, so views use the underlying property wrapper through this alias.
typealias ViewState = SwiftUI.State
