import SotoSignerV4
import Benchmark
import Foundation

let awsSignerV4Suite = BenchmarkSuite(name: "AWSSignerV4", settings: Iterations(1000), WarmupIterations(2)) { suite in
    let string = "testing, testing, 1,2,1,2"
    let credentials: Credential = StaticCredential(accessKeyId: "MYACCESSKEY", secretAccessKey: "MYSECRETACCESSKEY")
    let signer = AWSSigner(credentials: credentials, name: "s3", region: "eu-west-1")
    
    suite.benchmark("sign-headers") {
        _ = signer.signHeaders(url: URL(string: "https://test-bucket.s3.amazonaws.com/test-put.txt")!, method: .GET, headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8"], body: .string(string))
    }
    
    suite.benchmark("sign-url") {
        _ = signer.signURL(url: URL(string: "https://test-bucket.s3.amazonaws.com/test-put.txt")!, method: .GET, body: .string(string), expires: .hours(1))
    }
}
