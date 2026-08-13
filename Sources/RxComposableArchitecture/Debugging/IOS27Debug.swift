import Foundation
import UIKit

/// Temporary diagnostic logging for the iOS 27 `ListStoreNode` rendering issue.
///
/// All output is prefixed with `IOS27_LISTNODE_DEBUG` so it can be filtered in
/// Console.app / Xcode. Uses `NSLog` so the output appears in the *device*
/// console, not only in the Xcode debug pane.
///
/// REMOVE THIS FILE once the root cause is fixed.
public enum IOS27Debug {
    public static let prefix = "IOS27_LISTNODE_DEBUG"

    /// Monotonic sequence so log ordering is unambiguous even with async layout.
    private static let lock = NSLock()
    private static var sequence: Int = 0

    private static func nextSeq() -> Int {
        lock.lock()
        defer { lock.unlock() }
        sequence += 1
        return sequence
    }

    public static func log(
        component: String,
        instance: String,
        event: String,
        fields: [(String, String)] = []
    ) {
        let seq = nextSeq()
        let thread = Thread.isMainThread ? "main" : "bg"
        var out = "\(prefix) #\(seq) [\(component)] id=\(instance) thread=\(thread) event=\(event)"
        if !fields.isEmpty {
            out += " || " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
        }
        NSLog("%@", out)
    }

    /// Short, stable identity for an object so we can tell instances apart
    /// across logout/login and background/foreground cycles.
    public static func identity(_ object: AnyObject) -> String {
        let raw = UInt(bitPattern: ObjectIdentifier(object).hashValue)
        return String(raw % 0xFFFF, radix: 16, uppercase: true)
    }
}

extension CGRect {
    internal var dbg: String {
        "(\(Int(origin.x)),\(Int(origin.y)) \(Int(width))x\(Int(height)))"
    }
}

extension CGSize {
    internal var dbg: String { "\(Int(width))x\(Int(height))" }
}

extension UIEdgeInsets {
    internal var dbg: String {
        "t\(Int(top))/l\(Int(left))/b\(Int(bottom))/r\(Int(right))"
    }
}
