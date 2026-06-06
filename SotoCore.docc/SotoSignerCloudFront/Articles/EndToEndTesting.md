# End-to-End Testing with CloudFront

Test signed URL and cookie generation against a real CloudFront distribution.

## Overview

This guide walks through setting up a private CloudFront distribution backed by S3, generating signed URLs with `SotoSignerCloudFront`, and verifying the signatures work end-to-end. Every step is copy-pasteable assuming you have the AWS CLI installed and configured.

## Prerequisites

- AWS CLI v2 installed and configured (`aws configure`)
- `jq` installed (used for JSON manipulation in key upload and cleanup)
- OpenSSL installed (ships with macOS)
- Swift 6.0+ toolchain
- `curl` for verification

## Step 1: Set Up Variables

Choose a unique prefix to avoid S3 bucket name collisions:

```bash
export CF_TEST_PREFIX="soto-cf-test-$(date +%s)"
export CF_BUCKET="${CF_TEST_PREFIX}-bucket"
export CF_REGION="us-east-1"
```

## Step 2: Generate an RSA Key Pair

```bash
mkdir -p /tmp/cf-test && cd /tmp/cf-test

# Generate 2048-bit RSA private key
openssl genrsa -out private-key.pem 2048

# Extract public key
openssl rsa -in private-key.pem -pubout -out public-key.pem

echo "Keys generated in /tmp/cf-test/"
```

## Step 3: Create an S3 Bucket with Test Content

```bash
# Create bucket
aws s3 mb "s3://${CF_BUCKET}" --region "${CF_REGION}"

# Upload test files
printf 'Hello from CloudFront signed URL\n' > /tmp/cf-test/test.txt
printf 'Premium content\n' > /tmp/cf-test/premium.txt

aws s3 cp /tmp/cf-test/test.txt "s3://${CF_BUCKET}/test.txt"
aws s3 cp /tmp/cf-test/premium.txt "s3://${CF_BUCKET}/premium/content.txt"

# Block all public access
aws s3api put-public-access-block \
  --bucket "${CF_BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

## Step 4: Create a CloudFront Origin Access Control (OAC)

```bash
export CF_OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
  "Name=${CF_TEST_PREFIX}-oac,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
  --query 'OriginAccessControl.Id' --output text)

echo "OAC ID: ${CF_OAC_ID}"
```

## Step 5: Upload the Public Key to CloudFront

The PEM file contains newlines that must be properly escaped in JSON. Use `jq --rawfile`
to handle this correctly:

```bash
jq -n \
  --arg cr "${CF_TEST_PREFIX}" \
  --arg name "${CF_TEST_PREFIX}-key" \
  --rawfile key /tmp/cf-test/public-key.pem \
  '{CallerReference: $cr, Name: $name, EncodedKey: $key}' \
  > /tmp/cf-test/pk-config.json

export CF_PUBLIC_KEY_ID=$(aws cloudfront create-public-key \
  --public-key-config file:///tmp/cf-test/pk-config.json \
  --query 'PublicKey.Id' --output text)

echo "Public Key ID: ${CF_PUBLIC_KEY_ID}"
```

## Step 6: Create a Key Group

```bash
export CF_KEY_GROUP_ID=$(aws cloudfront create-key-group \
  --key-group-config \
  "Name=${CF_TEST_PREFIX}-group,Items=${CF_PUBLIC_KEY_ID},Comment=e2e-test" \
  --query 'KeyGroup.Id' --output text)

echo "Key Group ID: ${CF_KEY_GROUP_ID}"
```

## Step 7: Create the CloudFront Distribution

```bash
cat > /tmp/cf-test/dist-config.json << EOF
{
  "CallerReference": "${CF_TEST_PREFIX}",
  "Comment": "SotoSignerCloudFront E2E test",
  "Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "s3-origin",
        "DomainName": "${CF_BUCKET}.s3.${CF_REGION}.amazonaws.com",
        "OriginAccessControlId": "${CF_OAC_ID}",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
    },
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "TrustedKeyGroups": {
      "Enabled": true,
      "Quantity": 1,
      "Items": ["${CF_KEY_GROUP_ID}"]
    }
  },
  "PriceClass": "PriceClass_100",
  "ViewerCertificate": {
    "CloudFrontDefaultCertificate": true
  }
}
EOF

export CF_DIST_ID=$(aws cloudfront create-distribution \
  --distribution-config file:///tmp/cf-test/dist-config.json \
  --query 'Distribution.Id' --output text)

export CF_DOMAIN=$(aws cloudfront get-distribution \
  --id "${CF_DIST_ID}" \
  --query 'Distribution.DomainName' --output text)

echo "Distribution ID: ${CF_DIST_ID}"
echo "Domain: ${CF_DOMAIN}"
```

## Step 8: Grant CloudFront Access to S3

```bash
export CF_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

cat > /tmp/cf-test/bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${CF_BUCKET}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${CF_ACCOUNT_ID}:distribution/${CF_DIST_ID}"
        }
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket "${CF_BUCKET}" --policy file:///tmp/cf-test/bucket-policy.json
```

## Step 9: Wait for Distribution to Deploy

```bash
echo "Waiting for distribution to deploy (this takes 3-5 minutes)..."
aws cloudfront wait distribution-deployed --id "${CF_DIST_ID}"
echo "Distribution is deployed!"
```

## Step 10: Verify Unsigned Access is Denied

```bash
# This should return 403
curl -s -o /dev/null -w "Unsigned request: HTTP %{http_code}\n" \
  "https://${CF_DOMAIN}/test.txt"
```

Expected output: `Unsigned request: HTTP 403`

## Step 11: Generate and Test Signed URLs with Swift

Create a test package. Update the `.package(path:)` to point at your local soto-core checkout:

```bash
mkdir -p /tmp/cf-test/swift-test/Sources/cf-e2e-test
cd /tmp/cf-test/swift-test

cat > Package.swift << 'EOF'
// swift-tools-version:6.1
import PackageDescription
let package = Package(
    name: "cf-e2e-test",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(path: "/path/to/soto-core"),  // <-- UPDATE THIS PATH
    ],
    targets: [
        .executableTarget(
            name: "cf-e2e-test",
            dependencies: [
                .product(name: "SotoSignerCloudFront", package: "soto-core"),
            ],
            path: "Sources/cf-e2e-test"
        ),
    ]
)
EOF
```

Now create the test program using a single-quoted heredoc (avoids shell interpolation issues
with string interpolation characters):

```bash
cat > Sources/cf-e2e-test/main.swift << 'SWIFTEOF'
import SotoSignerCloudFront
import NIOCore
import Foundation

let keyPairId = ProcessInfo.processInfo.environment["CF_PUBLIC_KEY_ID"]!
let domain = ProcessInfo.processInfo.environment["CF_DOMAIN"]!
let privateKeyPEM = try String(contentsOfFile: "/tmp/cf-test/private-key.pem")

// --- Test 1: Canned policy signed URL (SHA-1) ---
print("=== Test 1: Canned Policy Signed URL (SHA-1) ===")
let signerSHA1 = try CloudFrontSigner(keyPairId: keyPairId, privateKey: privateKeyPEM)
let cannedURL = try signerSHA1.signedURL(
    url: "https://\(domain)/test.txt",
    expires: .minutes(5)
)
print("URL: \(cannedURL)\n")

// --- Test 2: Canned policy signed URL (SHA-256) ---
print("=== Test 2: Canned Policy Signed URL (SHA-256) ===")
let signerSHA256 = try CloudFrontSigner(
    keyPairId: keyPairId,
    privateKey: privateKeyPEM,
    hashAlgorithm: .sha256
)
let sha256URL = try signerSHA256.signedURL(
    url: "https://\(domain)/test.txt",
    expires: .minutes(5)
)
print("URL: \(sha256URL)\n")

// --- Test 3: Custom policy with wildcard ---
print("=== Test 3: Custom Policy with Wildcard ===")
let customPolicy = CloudFrontSigner.CustomPolicy(
    resource: "https://\(domain)/premium/*",
    expires: .minutes(10)
)
let customURL = try signerSHA1.signedURL(
    url: "https://\(domain)/premium/content.txt",
    policy: customPolicy
)
print("URL: \(customURL)\n")

// --- Test 4: Signed cookies ---
print("=== Test 4: Signed Cookies (Canned) ===")
let cookies = try signerSHA1.signedCookies(
    url: "https://\(domain)/test.txt",
    expires: .minutes(5)
)
print("CloudFront-Expires: \(cookies.expires!)")
print("CloudFront-Signature: \(cookies.signature)")
print("CloudFront-Key-Pair-Id: \(cookies.keyPairId)\n")

// --- Test 5: Expired URL (should be rejected) ---
print("=== Test 5: Expired URL (expect 403) ===")
let expiredURL = try signerSHA1.signedURL(
    url: "https://\(domain)/test.txt",
    expires: .seconds(1),
    date: Date(timeIntervalSince1970: 0) // Epoch 0 = already expired
)
print("URL: \(expiredURL)\n")

// --- Print curl verification commands ---
print("=== Verify with curl (copy-paste these) ===\n")
print("curl -s -o /dev/null -w 'Test 1 (canned SHA1): HTTP %{http_code}\\n' '\(cannedURL)'\n")
print("curl -s -o /dev/null -w 'Test 2 (canned SHA256): HTTP %{http_code}\\n' '\(sha256URL)'\n")
print("curl -s -o /dev/null -w 'Test 3 (custom wildcard): HTTP %{http_code}\\n' '\(customURL)'\n")
print("curl -s -o /dev/null -w 'Test 4 (cookies): HTTP %{http_code}\\n' -H 'Cookie: CloudFront-Expires=\(cookies.expires!); CloudFront-Signature=\(cookies.signature); CloudFront-Key-Pair-Id=\(cookies.keyPairId)' 'https://\(domain)/test.txt'\n")
print("curl -s -o /dev/null -w 'Test 5 (expired): HTTP %{http_code}\\n' '\(expiredURL)'\n")
SWIFTEOF
```

Run the test:

```bash
cd /tmp/cf-test/swift-test
swift run cf-e2e-test 2>&1
```

## Step 12: Verify with curl

After running the Swift program, it prints curl commands. Execute them. Expected results:

| Test | Expected | Meaning |
|------|----------|---------|
| Test 1 (canned SHA-1) | HTTP 200 | Basic signed URL works |
| Test 2 (canned SHA-256) | HTTP 200 | SHA-256 hash algorithm accepted |
| Test 3 (custom wildcard) | HTTP 200 | Wildcard policy grants access to specific files |
| Test 4 (cookies) | HTTP 200 | Signed cookies authenticate the request |
| Test 5 (expired) | HTTP 403 | Expired signatures are correctly rejected |

## Cleanup

Remove all resources created during testing. The distribution must be disabled before it
can be deleted, which adds a wait step:

```bash
# 1. Disable the distribution (required before deletion)
export CF_ETAG=$(aws cloudfront get-distribution-config \
  --id "${CF_DIST_ID}" --query 'ETag' --output text)

aws cloudfront get-distribution-config --id "${CF_DIST_ID}" \
  --query 'DistributionConfig' --output json | \
  jq '.Enabled = false' > /tmp/cf-test/disable-config.json

aws cloudfront update-distribution \
  --id "${CF_DIST_ID}" \
  --distribution-config file:///tmp/cf-test/disable-config.json \
  --if-match "${CF_ETAG}"

echo "Waiting for distribution to disable (3-5 minutes)..."
aws cloudfront wait distribution-deployed --id "${CF_DIST_ID}"

# 2. Delete the distribution
export CF_ETAG=$(aws cloudfront get-distribution-config \
  --id "${CF_DIST_ID}" --query 'ETag' --output text)

aws cloudfront delete-distribution --id "${CF_DIST_ID}" --if-match "${CF_ETAG}"
echo "Distribution deleted."

# 3. Delete the key group
export CF_KG_ETAG=$(aws cloudfront get-key-group \
  --id "${CF_KEY_GROUP_ID}" --query 'ETag' --output text)

aws cloudfront delete-key-group --id "${CF_KEY_GROUP_ID}" --if-match "${CF_KG_ETAG}"
echo "Key group deleted."

# 4. Delete the public key
export CF_PK_ETAG=$(aws cloudfront get-public-key \
  --id "${CF_PUBLIC_KEY_ID}" --query 'ETag' --output text)

aws cloudfront delete-public-key --id "${CF_PUBLIC_KEY_ID}" --if-match "${CF_PK_ETAG}"
echo "Public key deleted."

# 5. Delete the OAC
export CF_OAC_ETAG=$(aws cloudfront get-origin-access-control \
  --id "${CF_OAC_ID}" --query 'ETag' --output text)

aws cloudfront delete-origin-access-control --id "${CF_OAC_ID}" --if-match "${CF_OAC_ETAG}"
echo "OAC deleted."

# 6. Empty and delete the S3 bucket
aws s3 rm "s3://${CF_BUCKET}" --recursive
aws s3 rb "s3://${CF_BUCKET}"
echo "S3 bucket deleted."

# 7. Remove local test files
rm -rf /tmp/cf-test
echo "Local files cleaned up."

echo ""
echo "=== All resources deleted ==="
```

## One-Shot Cleanup Script

If something went wrong mid-setup or you lost your shell session, use this after
re-exporting the resource IDs (check CloudFront console for the distribution ID):

```bash
# Safe cleanup — ignores errors for resources that don't exist

# Distribution
if [ -n "${CF_DIST_ID}" ]; then
  CF_ETAG=$(aws cloudfront get-distribution-config --id "${CF_DIST_ID}" --query 'ETag' --output text 2>/dev/null)
  if [ -n "${CF_ETAG}" ]; then
    aws cloudfront get-distribution-config --id "${CF_DIST_ID}" --query 'DistributionConfig' --output json 2>/dev/null | \
      jq '.Enabled = false' > /tmp/cf-disable.json 2>/dev/null
    aws cloudfront update-distribution --id "${CF_DIST_ID}" \
      --distribution-config file:///tmp/cf-disable.json --if-match "${CF_ETAG}" 2>/dev/null
    echo "Waiting for disable..."
    aws cloudfront wait distribution-deployed --id "${CF_DIST_ID}" 2>/dev/null
    CF_ETAG=$(aws cloudfront get-distribution-config --id "${CF_DIST_ID}" --query 'ETag' --output text 2>/dev/null)
    aws cloudfront delete-distribution --id "${CF_DIST_ID}" --if-match "${CF_ETAG}" 2>/dev/null
  fi
fi

# Key group
[ -n "${CF_KEY_GROUP_ID}" ] && {
  ETAG=$(aws cloudfront get-key-group --id "${CF_KEY_GROUP_ID}" --query 'ETag' --output text 2>/dev/null)
  aws cloudfront delete-key-group --id "${CF_KEY_GROUP_ID}" --if-match "${ETAG}" 2>/dev/null
}

# Public key
[ -n "${CF_PUBLIC_KEY_ID}" ] && {
  ETAG=$(aws cloudfront get-public-key --id "${CF_PUBLIC_KEY_ID}" --query 'ETag' --output text 2>/dev/null)
  aws cloudfront delete-public-key --id "${CF_PUBLIC_KEY_ID}" --if-match "${ETAG}" 2>/dev/null
}

# OAC
[ -n "${CF_OAC_ID}" ] && {
  ETAG=$(aws cloudfront get-origin-access-control --id "${CF_OAC_ID}" --query 'ETag' --output text 2>/dev/null)
  aws cloudfront delete-origin-access-control --id "${CF_OAC_ID}" --if-match "${ETAG}" 2>/dev/null
}

# S3
[ -n "${CF_BUCKET}" ] && {
  aws s3 rm "s3://${CF_BUCKET}" --recursive 2>/dev/null
  aws s3 rb "s3://${CF_BUCKET}" 2>/dev/null
}

rm -rf /tmp/cf-test /tmp/cf-disable.json
echo "Cleanup complete."
```

## Troubleshooting

### `create-public-key` fails with JSON parse errors

The PEM file contains newlines that must be JSON-escaped. Use `jq --rawfile` as shown in
Step 5. Do not try to use `cat | jq -Rs` in a subshell — different shells handle the
quoting differently.

### `create-key-group` fails with "Unknown parameter" or "Invalid type"

The CLI shorthand for `Items` is a simple comma-separated list of key IDs, not a nested
JSON structure. Use: `Items=KEY_ID1,KEY_ID2`

### Swift package fails to resolve

Make sure the `.package(path:)` in `Package.swift` points to your soto-core checkout and
uses `swift-tools-version:6.1` (matching soto-core's manifest). The executable target
needs an explicit `path: "Sources/cf-e2e-test"`.

### Distribution returns 403 even with a signed URL

- Verify the distribution has finished deploying (`Status: Deployed`)
- Check that the bucket policy references the correct distribution ARN
- Ensure the key pair ID in the signed URL matches the one in the trusted key group

## Cost Notes

This test setup incurs minimal AWS costs:
- **CloudFront**: Free tier covers 1 TB/month of data transfer and 10M requests/month
- **S3**: Negligible (a few bytes stored)
- **Key management**: Free (CloudFront key pairs have no charge)

Delete all resources promptly after testing to avoid any charges.
