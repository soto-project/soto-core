import SotoSignerV4
@_spi(SotoInternal) import SotoSignerV4
import XCTest

final class SigV4aTests: XCTestCase {

    func testCompareConstantTime() {

        let lhs1: [UInt8] = [0x00, 0x00, 0x00]
        let rhs1: [UInt8] = [0x00, 0x00, 0x01]
        let lhs2: [UInt8] = [0xAB, 0xCD, 0x80, 0xFF, 0x01, 0x0A]
        let rhs2: [UInt8] = [0xAB, 0xCD, 0x80, 0xFF, 0x01, 0x0A]
        let lhs3: [UInt8] = [0xFF, 0xCD, 0x80, 0xFF, 0x01, 0x0A]
        let rhs3: [UInt8] = [0xFE, 0xCD, 0x80, 0xFF, 0x01, 0x0A]

        XCTAssertEqual(SigV4aKeyPair.compareConstantTime(lhs: lhs1, rhs: rhs1), -1)
        XCTAssertEqual(SigV4aKeyPair.compareConstantTime(lhs: lhs2, rhs: rhs2), 0)
        XCTAssertEqual(SigV4aKeyPair.compareConstantTime(lhs: lhs3, rhs: rhs3), 1)

    }

    func testAddOne() {
        XCTAssertEqual([0x00, 0x00, 0x00].addingOne(), [0x00, 0x00, 0x01])
        XCTAssertEqual([0x00, 0x00, 0xFF].addingOne(), [0x00, 0x01, 0x00])
        XCTAssertEqual([0x00, 0xFF, 0xFF].addingOne(), [0x01, 0x00, 0x00])
        XCTAssertEqual([0xFF, 0xFF, 0xFF, 0xFF].addingOne(), [0x00, 0x00, 0x00, 0x00])
    }

    func testDerivedStaticKey() {
        let accessKey = "AKISORANDOMAASORANDOM"
        let secretAccessKey = "q+jcrXGc+0zWN6uzclKVhvMmUsIfRPa4rlRandom"

        let expectedPrivateKeyHex = "7fd3bd010c0d9c292141c2b77bfbde1042c92e6836fff749d1269ec890fca1bd"

        let credential = StaticCredential(accessKeyId: accessKey, secretAccessKey: secretAccessKey)

        let result = SigV4aKeyPair(credential: credential)
        XCTAssertEqual(result.key.rawRepresentation.hexDigest(), expectedPrivateKeyHex)
    }

    func testDeriveLongKey() {
        let accessKey = """
            AKISORANDOMAASORANDOMFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF\
            FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF\
            FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFf
            """
        let secretAccessKey = "q+jcrXGc+0zWN6uzclKVhvMmUsIfRPa4rlRandom"

        let expectedPrivateKeyHex = "bc0fd68955922f2cccd5c27f8aa04394a467ef1076d889b66569c6d2e764faf3"

        let credential = StaticCredential(accessKeyId: accessKey, secretAccessKey: secretAccessKey)

        let result = SigV4aKeyPair(credential: credential)
        XCTAssertEqual(result.key.rawRepresentation.hexDigest(), expectedPrivateKeyHex)
        XCTAssertEqual(String(decoding: HexEncoding(result.key.rawRepresentation), as: Unicode.UTF8.self), expectedPrivateKeyHex)
    }

    func testHexEncoding() {
        XCTAssertEqual(String(decoding: HexEncoding([0]), as: Unicode.UTF8.self), "00")
        XCTAssertEqual(String(decoding: HexEncoding([1]), as: Unicode.UTF8.self), "01")
        XCTAssertEqual(String(decoding: HexEncoding([254]), as: Unicode.UTF8.self), "fe")
        XCTAssertEqual(String(decoding: HexEncoding([255]), as: Unicode.UTF8.self), "ff")
        XCTAssertEqual(String(decoding: HexEncoding([254, 255, 0]), as: Unicode.UTF8.self), "feff00")
    }
}
