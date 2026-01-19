import Foundation

// MARK: - String 扩展
extension String {
    /// Base64URL 解码
    var base64URLDecoded: String {
        var base64 =
            self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(
                toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }

        return base64
    }
}
