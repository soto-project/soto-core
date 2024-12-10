//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public typealias CRC32 = UInt32

let crc32Table: [CRC32] =
    [
        0x0000_0000, 0x7707_3096, 0xEE0E_612C, 0x9909_51BA, 0x076D_C419,
        0x706A_F48F, 0xE963_A535, 0x9E64_95A3, 0x0EDB_8832, 0x79DC_B8A4,
        0xE0D5_E91E, 0x97D2_D988, 0x09B6_4C2B, 0x7EB1_7CBD, 0xE7B8_2D07,
        0x90BF_1D91, 0x1DB7_1064, 0x6AB0_20F2, 0xF3B9_7148, 0x84BE_41DE,
        0x1ADA_D47D, 0x6DDD_E4EB, 0xF4D4_B551, 0x83D3_85C7, 0x136C_9856,
        0x646B_A8C0, 0xFD62_F97A, 0x8A65_C9EC, 0x1401_5C4F, 0x6306_6CD9,
        0xFA0F_3D63, 0x8D08_0DF5, 0x3B6E_20C8, 0x4C69_105E, 0xD560_41E4,
        0xA267_7172, 0x3C03_E4D1, 0x4B04_D447, 0xD20D_85FD, 0xA50A_B56B,
        0x35B5_A8FA, 0x42B2_986C, 0xDBBB_C9D6, 0xACBC_F940, 0x32D8_6CE3,
        0x45DF_5C75, 0xDCD6_0DCF, 0xABD1_3D59, 0x26D9_30AC, 0x51DE_003A,
        0xC8D7_5180, 0xBFD0_6116, 0x21B4_F4B5, 0x56B3_C423, 0xCFBA_9599,
        0xB8BD_A50F, 0x2802_B89E, 0x5F05_8808, 0xC60C_D9B2, 0xB10B_E924,
        0x2F6F_7C87, 0x5868_4C11, 0xC161_1DAB, 0xB666_2D3D, 0x76DC_4190,
        0x01DB_7106, 0x98D2_20BC, 0xEFD5_102A, 0x71B1_8589, 0x06B6_B51F,
        0x9FBF_E4A5, 0xE8B8_D433, 0x7807_C9A2, 0x0F00_F934, 0x9609_A88E,
        0xE10E_9818, 0x7F6A_0DBB, 0x086D_3D2D, 0x9164_6C97, 0xE663_5C01,
        0x6B6B_51F4, 0x1C6C_6162, 0x8565_30D8, 0xF262_004E, 0x6C06_95ED,
        0x1B01_A57B, 0x8208_F4C1, 0xF50F_C457, 0x65B0_D9C6, 0x12B7_E950,
        0x8BBE_B8EA, 0xFCB9_887C, 0x62DD_1DDF, 0x15DA_2D49, 0x8CD3_7CF3,
        0xFBD4_4C65, 0x4DB2_6158, 0x3AB5_51CE, 0xA3BC_0074, 0xD4BB_30E2,
        0x4ADF_A541, 0x3DD8_95D7, 0xA4D1_C46D, 0xD3D6_F4FB, 0x4369_E96A,
        0x346E_D9FC, 0xAD67_8846, 0xDA60_B8D0, 0x4404_2D73, 0x3303_1DE5,
        0xAA0A_4C5F, 0xDD0D_7CC9, 0x5005_713C, 0x2702_41AA, 0xBE0B_1010,
        0xC90C_2086, 0x5768_B525, 0x206F_85B3, 0xB966_D409, 0xCE61_E49F,
        0x5EDE_F90E, 0x29D9_C998, 0xB0D0_9822, 0xC7D7_A8B4, 0x59B3_3D17,
        0x2EB4_0D81, 0xB7BD_5C3B, 0xC0BA_6CAD, 0xEDB8_8320, 0x9ABF_B3B6,
        0x03B6_E20C, 0x74B1_D29A, 0xEAD5_4739, 0x9DD2_77AF, 0x04DB_2615,
        0x73DC_1683, 0xE363_0B12, 0x9464_3B84, 0x0D6D_6A3E, 0x7A6A_5AA8,
        0xE40E_CF0B, 0x9309_FF9D, 0x0A00_AE27, 0x7D07_9EB1, 0xF00F_9344,
        0x8708_A3D2, 0x1E01_F268, 0x6906_C2FE, 0xF762_575D, 0x8065_67CB,
        0x196C_3671, 0x6E6B_06E7, 0xFED4_1B76, 0x89D3_2BE0, 0x10DA_7A5A,
        0x67DD_4ACC, 0xF9B9_DF6F, 0x8EBE_EFF9, 0x17B7_BE43, 0x60B0_8ED5,
        0xD6D6_A3E8, 0xA1D1_937E, 0x38D8_C2C4, 0x4FDF_F252, 0xD1BB_67F1,
        0xA6BC_5767, 0x3FB5_06DD, 0x48B2_364B, 0xD80D_2BDA, 0xAF0A_1B4C,
        0x3603_4AF6, 0x4104_7A60, 0xDF60_EFC3, 0xA867_DF55, 0x316E_8EEF,
        0x4669_BE79, 0xCB61_B38C, 0xBC66_831A, 0x256F_D2A0, 0x5268_E236,
        0xCC0C_7795, 0xBB0B_4703, 0x2202_16B9, 0x5505_262F, 0xC5BA_3BBE,
        0xB2BD_0B28, 0x2BB4_5A92, 0x5CB3_6A04, 0xC2D7_FFA7, 0xB5D0_CF31,
        0x2CD9_9E8B, 0x5BDE_AE1D, 0x9B64_C2B0, 0xEC63_F226, 0x756A_A39C,
        0x026D_930A, 0x9C09_06A9, 0xEB0E_363F, 0x7207_6785, 0x0500_5713,
        0x95BF_4A82, 0xE2B8_7A14, 0x7BB1_2BAE, 0x0CB6_1B38, 0x92D2_8E9B,
        0xE5D5_BE0D, 0x7CDC_EFB7, 0x0BDB_DF21, 0x86D3_D2D4, 0xF1D4_E242,
        0x68DD_B3F8, 0x1FDA_836E, 0x81BE_16CD, 0xF6B9_265B, 0x6FB0_77E1,
        0x18B7_4777, 0x8808_5AE6, 0xFF0F_6A70, 0x6606_3BCA, 0x1101_0B5C,
        0x8F65_9EFF, 0xF862_AE69, 0x616B_FFD3, 0x166C_CF45, 0xA00A_E278,
        0xD70D_D2EE, 0x4E04_8354, 0x3903_B3C2, 0xA767_2661, 0xD060_16F7,
        0x4969_474D, 0x3E6E_77DB, 0xAED1_6A4A, 0xD9D6_5ADC, 0x40DF_0B66,
        0x37D8_3BF0, 0xA9BC_AE53, 0xDEBB_9EC5, 0x47B2_CF7F, 0x30B5_FFE9,
        0xBDBD_F21C, 0xCABA_C28A, 0x53B3_9330, 0x24B4_A3A6, 0xBAD0_3605,
        0xCDD7_0693, 0x54DE_5729, 0x23D9_67BF, 0xB366_7A2E, 0xC461_4AB8,
        0x5D68_1B02, 0x2A6F_2B94, 0xB40B_BE37, 0xC30C_8EA1, 0x5A05_DF1B,
        0x2D02_EF8D,
    ]

let crc32cTable: [CRC32] =
    [
        0x0000_0000, 0xF26B_8303, 0xE13B_70F7, 0x1350_F3F4, 0xC79A_971F,
        0x35F1_141C, 0x26A1_E7E8, 0xD4CA_64EB, 0x8AD9_58CF, 0x78B2_DBCC,
        0x6BE2_2838, 0x9989_AB3B, 0x4D43_CFD0, 0xBF28_4CD3, 0xAC78_BF27,
        0x5E13_3C24, 0x105E_C76F, 0xE235_446C, 0xF165_B798, 0x030E_349B,
        0xD7C4_5070, 0x25AF_D373, 0x36FF_2087, 0xC494_A384, 0x9A87_9FA0,
        0x68EC_1CA3, 0x7BBC_EF57, 0x89D7_6C54, 0x5D1D_08BF, 0xAF76_8BBC,
        0xBC26_7848, 0x4E4D_FB4B, 0x20BD_8EDE, 0xD2D6_0DDD, 0xC186_FE29,
        0x33ED_7D2A, 0xE727_19C1, 0x154C_9AC2, 0x061C_6936, 0xF477_EA35,
        0xAA64_D611, 0x580F_5512, 0x4B5F_A6E6, 0xB934_25E5, 0x6DFE_410E,
        0x9F95_C20D, 0x8CC5_31F9, 0x7EAE_B2FA, 0x30E3_49B1, 0xC288_CAB2,
        0xD1D8_3946, 0x23B3_BA45, 0xF779_DEAE, 0x0512_5DAD, 0x1642_AE59,
        0xE429_2D5A, 0xBA3A_117E, 0x4851_927D, 0x5B01_6189, 0xA96A_E28A,
        0x7DA0_8661, 0x8FCB_0562, 0x9C9B_F696, 0x6EF0_7595, 0x417B_1DBC,
        0xB310_9EBF, 0xA040_6D4B, 0x522B_EE48, 0x86E1_8AA3, 0x748A_09A0,
        0x67DA_FA54, 0x95B1_7957, 0xCBA2_4573, 0x39C9_C670, 0x2A99_3584,
        0xD8F2_B687, 0x0C38_D26C, 0xFE53_516F, 0xED03_A29B, 0x1F68_2198,
        0x5125_DAD3, 0xA34E_59D0, 0xB01E_AA24, 0x4275_2927, 0x96BF_4DCC,
        0x64D4_CECF, 0x7784_3D3B, 0x85EF_BE38, 0xDBFC_821C, 0x2997_011F,
        0x3AC7_F2EB, 0xC8AC_71E8, 0x1C66_1503, 0xEE0D_9600, 0xFD5D_65F4,
        0x0F36_E6F7, 0x61C6_9362, 0x93AD_1061, 0x80FD_E395, 0x7296_6096,
        0xA65C_047D, 0x5437_877E, 0x4767_748A, 0xB50C_F789, 0xEB1F_CBAD,
        0x1974_48AE, 0x0A24_BB5A, 0xF84F_3859, 0x2C85_5CB2, 0xDEEE_DFB1,
        0xCDBE_2C45, 0x3FD5_AF46, 0x7198_540D, 0x83F3_D70E, 0x90A3_24FA,
        0x62C8_A7F9, 0xB602_C312, 0x4469_4011, 0x5739_B3E5, 0xA552_30E6,
        0xFB41_0CC2, 0x092A_8FC1, 0x1A7A_7C35, 0xE811_FF36, 0x3CDB_9BDD,
        0xCEB0_18DE, 0xDDE0_EB2A, 0x2F8B_6829, 0x82F6_3B78, 0x709D_B87B,
        0x63CD_4B8F, 0x91A6_C88C, 0x456C_AC67, 0xB707_2F64, 0xA457_DC90,
        0x563C_5F93, 0x082F_63B7, 0xFA44_E0B4, 0xE914_1340, 0x1B7F_9043,
        0xCFB5_F4A8, 0x3DDE_77AB, 0x2E8E_845F, 0xDCE5_075C, 0x92A8_FC17,
        0x60C3_7F14, 0x7393_8CE0, 0x81F8_0FE3, 0x5532_6B08, 0xA759_E80B,
        0xB409_1BFF, 0x4662_98FC, 0x1871_A4D8, 0xEA1A_27DB, 0xF94A_D42F,
        0x0B21_572C, 0xDFEB_33C7, 0x2D80_B0C4, 0x3ED0_4330, 0xCCBB_C033,
        0xA24B_B5A6, 0x5020_36A5, 0x4370_C551, 0xB11B_4652, 0x65D1_22B9,
        0x97BA_A1BA, 0x84EA_524E, 0x7681_D14D, 0x2892_ED69, 0xDAF9_6E6A,
        0xC9A9_9D9E, 0x3BC2_1E9D, 0xEF08_7A76, 0x1D63_F975, 0x0E33_0A81,
        0xFC58_8982, 0xB215_72C9, 0x407E_F1CA, 0x532E_023E, 0xA145_813D,
        0x758F_E5D6, 0x87E4_66D5, 0x94B4_9521, 0x66DF_1622, 0x38CC_2A06,
        0xCAA7_A905, 0xD9F7_5AF1, 0x2B9C_D9F2, 0xFF56_BD19, 0x0D3D_3E1A,
        0x1E6D_CDEE, 0xEC06_4EED, 0xC38D_26C4, 0x31E6_A5C7, 0x22B6_5633,
        0xD0DD_D530, 0x0417_B1DB, 0xF67C_32D8, 0xE52C_C12C, 0x1747_422F,
        0x4954_7E0B, 0xBB3F_FD08, 0xA86F_0EFC, 0x5A04_8DFF, 0x8ECE_E914,
        0x7CA5_6A17, 0x6FF5_99E3, 0x9D9E_1AE0, 0xD3D3_E1AB, 0x21B8_62A8,
        0x32E8_915C, 0xC083_125F, 0x1449_76B4, 0xE622_F5B7, 0xF572_0643,
        0x0719_8540, 0x590A_B964, 0xAB61_3A67, 0xB831_C993, 0x4A5A_4A90,
        0x9E90_2E7B, 0x6CFB_AD78, 0x7FAB_5E8C, 0x8DC0_DD8F, 0xE330_A81A,
        0x115B_2B19, 0x020B_D8ED, 0xF060_5BEE, 0x24AA_3F05, 0xD6C1_BC06,
        0xC591_4FF2, 0x37FA_CCF1, 0x69E9_F0D5, 0x9B82_73D6, 0x88D2_8022,
        0x7AB9_0321, 0xAE73_67CA, 0x5C18_E4C9, 0x4F48_173D, 0xBD23_943E,
        0xF36E_6F75, 0x0105_EC76, 0x1255_1F82, 0xE03E_9C81, 0x34F4_F86A,
        0xC69F_7B69, 0xD5CF_889D, 0x27A4_0B9E, 0x79B7_37BA, 0x8BDC_B4B9,
        0x988C_474D, 0x6AE7_C44E, 0xBE2D_A0A5, 0x4C46_23A6, 0x5F16_D052,
        0xAD7D_5351,
    ]

private func crc32_with_table(crc: CRC32, buffer: UnsafeBufferPointer<UInt8>, table: [CRC32]) -> CRC32 {
    // use unsafe buffer pointer to avoid array bounds checking on table
    table.withUnsafeBufferPointer { table in
        var crc = crc
        var length = buffer.count
        crc = crc ^ 0xFFFF_FFFF
        guard var bufferPtr = buffer.baseAddress else { return 0 }
        while length >= 8 {
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            length -= 8
        }
        while length > 0 {
            crc = table[Int(crc ^ CRC32(bufferPtr.pointee)) & 0xFF] ^ (crc >> 8)
            bufferPtr = bufferPtr.advanced(by: 1)
            length -= 1
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Calculate CRC32 checksum
/// - Parameters:
///   - crc: base crc
///   - bytes: buffer to calculate CRC32 for
/// - Returns: crc32 checksum
public func soto_crc32(_ crc: CRC32, bytes: some Collection<UInt8>) -> CRC32 {
    if let rest = bytes.withContiguousStorageIfAvailable({ buffer -> CRC32 in
        crc32_with_table(crc: crc, buffer: buffer, table: crc32Table)
    }) {
        return rest
    }
    return soto_crc32(crc, bytes: Array(bytes))
}

/// Calculate CRC32C checksum
///
/// CRC32C uses the same calculation as CRC32 but uses the Castagnoli polynomial (0x1EDC6F41 / 0x82F63B78)
/// for generating the lookup table
/// - Parameters:
///   - crc: base crc
///   - bytes: buffer to calculate CRC32 for
/// - Returns: crc32c checksum
public func soto_crc32c(_ crc: CRC32, bytes: some Collection<UInt8>) -> CRC32 {
    if let rest = bytes.withContiguousStorageIfAvailable({ buffer -> CRC32 in
        crc32_with_table(crc: crc, buffer: buffer, table: crc32cTable)
    }) {
        return rest
    }
    return soto_crc32c(crc, bytes: Array(bytes))
}
