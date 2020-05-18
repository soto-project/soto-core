#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

internal enum Environment {
    internal static subscript(_ name: String) -> String? {
        guard let value = getenv(name) else {
            return nil
        }
        return String(cString: value)
    }
}
