import XCTest
@testable import AWSCrypto

final class AWSCryptoTests: XCTestCase {
    
    // create a buffer of random values. Will always create the same given you supply the same z and w values
    // Random number generator from https://www.codeproject.com/Articles/25172/Simple-Random-Number-Generation
    func createRandomBuffer(_ w: UInt, _ z: UInt, size: Int) -> [UInt8] {
        var z = z
        var w = w
        func getUInt8() -> UInt8
        {
            z = 36969 * (z & 65535) + (z >> 16);
            w = 18000 * (w & 65535) + (w >> 16);
            return UInt8(((z << 16) + w) & 0xff);
        }
        var data = Array<UInt8>(repeating: 0, count: size)
        for i in 0..<size {
            data[i] = getUInt8()
        }
        return data
    }
    
    func testMD5() {
        let data = createRandomBuffer(34, 2345, size: 234896)
        let digest = Insecure.MD5.hash(data: data)
        XCTAssertEqual(digest.hexDigest(), "3abdd8d79be09bc250d60ada1f000912")
    }

    func testSHA256() {
        let data = createRandomBuffer(872, 12489, size: 562741)
        let digest = SHA256.hash(data: data)
        XCTAssertEqual(digest.hexDigest(), "3cff070559024d8652d1257e5f455787e95ebd8e95378d62df1a466f78860f74")
    }
    
    func testSHA384() {
        let data = createRandomBuffer(872, 12489, size: 562741)
        let digest = SHA384.hash(data: data)
        XCTAssertEqual(digest.hexDigest(), "d03a6a749dd66fb7bb261e34014c69e217684440b0c853727ac5bc12147edddc304cadbec8df8f77ec2ee44cc6b53bc3")
    }
    
    func testSHA512() {
        let data = createRandomBuffer(872, 12489, size: 562741)
        let digest = SHA512.hash(data: data)
        XCTAssertEqual(digest.hexDigest(), "15fc2df3a1c3649b83baf0f28d1a611bee8339a050d9d2c2ac4afad18f3187f725530b09bb6b2044131648d11d608c394804bc02ce2110b76d231ea75201000d")
    }
    
    func testSHA256InitUpdateFinal() {
        let data = createRandomBuffer(8372, 12489, size: 562741)
        let digest = SHA256.hash(data: data)
        
        var sha256 = SHA256()
        sha256.update(data: data[0..<238768])
        sha256.update(data: data[238768..<562741])
        let digest2 = sha256.finalize()
        
        XCTAssertEqual(digest, digest2)
        XCTAssertEqual(digest.hexDigest(), digest2.hexDigest())
    }
    
    func testHMAC() {
        let data = createRandomBuffer(1, 91, size: 347237)
        let key = createRandomBuffer(102, 3, size: 32)
        let authenticationKey = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        XCTAssertEqual(authenticationKey.hexDigest(), "ddec250211f1b546254bab3fb027af1acc4842898e8af6eeadcdbf8e2c6c1ff5")
    }

    func testHMACInitUpdateFinal() {
        let data = createRandomBuffer(21, 81, size: 762061)
        let key = createRandomBuffer(102, 3, size: 32)
        let authenticationKey = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))

        var hmac = HMAC<SHA256>(key: SymmetricKey(data: key))
        hmac.update(data: data[0..<126749])
        hmac.update(data: data[126749..<762061])
        let authenticationKey2 = hmac.finalize()
        
        XCTAssertEqual(authenticationKey, authenticationKey2)
        XCTAssertEqual(authenticationKey.hexDigest(), authenticationKey2.hexDigest())
    }
    
    static var allTests = [
        ("testMD5", testMD5),
        ("testSHA256", testSHA256),
        ("testHMAC", testHMAC),
    ]
}

public extension Sequence where Element == UInt8 {
    /// return a hexEncoded string buffer from an array of bytes
    func hexDigest() -> String {
        return self.map{String(format: "%02x", $0)}.joined(separator: "")
    }
}
