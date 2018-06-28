struct IAMResponseModel {
    static let listServerCertificates = """
    {
      "ListServerCertificatesResponse" : {
        "ListServerCertificatesResult" : {
          "ServerCertificateMetadataList" : {
            "Member" : [
              {
                "Arn" : "arn:aws:iam::427300000128:server-certificate/fake-certificate-one",
                "ServerCertificateId" : "ASCAJCFVCSR2EWGIMMEH",
                "Expiration" : "2018-09-21T12:00:00Z",
                "ServerCertificateName" : "fake-certificate-one",
                "Path" : "/",
                "UploadDate" : "2017-10-21T23:15:37Z"
              },
              {
                "Arn" : "arn:aws:iam::427300000128:server-certificate/cloudfront/fake-certificate-two-cloudfront",
                "ServerCertificateId" : "ASCAIKWM24REUYJIMMEH",
                "Expiration" : "2018-07-07T12:00:00Z",
                "ServerCertificateName" : "fake-certificate-two-cloudfront",
                "Path" : "/cloudfront/",
                "UploadDate" : "2017-10-25T19:45:01Z"
              },
              {
                "Arn" : "arn:aws:iam::427300000128:server-certificate/cloudfront/fake-certificate-three-cloudfront",
                "ServerCertificateId" : "ASCAI2GPFDK56HIMMEH",
                "Expiration" : "2019-03-21T12:00:00Z",
                "ServerCertificateName" : "fake-certificate-three-cloudfront",
                "Path" : "/cloudfront/",
                "UploadDate" : "2018-04-16T22:42:46Z"
              }
            ]
          },
          "IsTruncated" : false
        },
        "ResponseMetadata" : {
          "RequestId" : "415bb910-7d2f-999d-8b43-b5ca21b845d1"
        }
      }
    }
    """
}
