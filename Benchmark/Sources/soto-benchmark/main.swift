import Benchmark

let suites = [
    awsSignerV4Suite,
    queryEncoderSuite,
    xmlEncoderSuite,
    xmlDecoderSuite,
    awsClientSuite,
]

Benchmark.main(suites)
