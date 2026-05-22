import Foundation
import NetworkExtension

// A NetworkExtension content filter on macOS is ONLY supported as a *system
// extension* (Apple: a filter data provider can't be an app extension). A
// system extension is a normal executable whose entry point calls
// `startSystemExtensionMode()`, which reads `NetworkExtension > NEProviderClasses`
// from Info.plist and instantiates FilterDataProvider.
//
// It must NOT use `_NSExtensionMain` (the appex/PlugInKit bootstrap): that
// path runs `xpc_main`, which aborts in `_xpc_copy_xpcservice_dictionary`
// because a system extension's Info.plist has no `NSExtension`/`XPCService`
// dictionary — the crash that made the provider die on every launch and the
// filter fail closed ("blocks everything").
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
