# Contributing

## Legal
By submitting a pull request, you represent that you have the right to license your contribution to the community, and agree by submitting the patch
that your contributions are licensed under the Apache 2.0 license (see [LICENSE](LICENSE.txt)).

## Contributor Conduct
All contributors are expected to adhere to the project's [Code of Conduct](CODE_OF_CONDUCT.md).

## Submitting a bug or issue
Please ensure to include the following in your bug report
- A consise description of the issue, what happened and what you expected.
- Simple reproduction steps
- Version of the library you are using
- Contextual information (Swift version, OS etc)

## Submitting a Pull Request

Please ensure to include the following in your Pull Request
- A description of what you are trying to do. What the PR provides to the library, additional functionality, fixing a bug etc
- A description of the code changes
- Documentation on how these changes are being tested
- Additional tests to show your code working and to ensure future changes don't break your code.

Please keep you PRs to a minimal number of changes. If a PR is large try to split it up into smaller PRs. Don't move code around unnecessarily it makes comparing old with new very hard. 

The main development branch of the repository is  `main`. Each major version release has it's own branch named "version number".x.x eg `4.x.x` . If you are submitting code for an older version then you should use the version branch as the base for your code changes. 

### Formatting

We use Nick Lockwood's SwiftFormat for formatting code. PRs will not be accepted if they haven't be formatted. The current version of SwiftFormat we are using is v0.47.13.

All new files need to include the following file header at the top
```swift
//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
```
Please ensure the dates are correct in the header.

## Community

You can also contribute by becoming an active member of the Soto community.  Join us on the soto-aws [slack](https://join.slack.com/t/soto-project/shared_invite/zt-juqk6l9w-z9zruW5pjlod4AscdWlz7Q).
