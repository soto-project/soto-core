import SotoSignerV4
import Testing

struct PercentEncodeTests {
    @Test(arguments: [
        ("abc", "abc"),
        ("ABC", "ABC"),
        ("8903", "8903"),
        ("~._-", "~._-"),
        ("!@$%^&*()/", "%21%40%24%25%5E%26%2A%28%29%2F"),
    ])
    func uriEncode(original: String, encoded: String) {
        #expect(original.addingAWSPercentEncoding(forURLComponent: .uriEncode) == encoded)
    }

    @Test(arguments: [
        ("abc", "abc"),
        ("ABC", "ABC"),
        ("8903", "8903"),
        ("~._-", "~._-"),
        ("!@$%^&*()/", "%21%40%24%25%5E%26%2A%28%29/"),
    ])
    func uriEncodePath(original: String, encoded: String) {
        #expect(original.addingAWSPercentEncoding(forURLComponent: .uriEncodePath) == encoded)
    }
}
