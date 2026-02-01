# eAIP Pad

A modern, feature-rich iOS and iPadOS application for aviation professionals, providing comprehensive access to China Aeronautical Information Publications (eAIP), airport data, weather information, and aeronautical charts.

## Overview

AIP Pad is a native iOS/iPadOS application built with Swift and SwiftUI, designed to deliver critical aviation information directly to aviation enthusiasts and aviation professionals. The application integrates multiple data sources including airport information, airport charts, weather updates, and regulatory documents in China, all optimized for quick access and intuitive navigation.

## Features

-**Aeronautical Charts & Documents**: Access and manage PDF-based eAIP aeronautical charts with pinning, annotation, and caching capabilities

-**Enroute Charts**: Comprehensive navigation information and enroute charts

-**Airport Details**: Browse comprehensive airport data including runway configurations, facilities, and contact information in AD

-**Weather Integration**: Real-time weather information and forecasts for aviation planning

-**AIRAC Management**: Automatic updates and management of AIRAC (Aeronautical Information Regulation And Control) cycles

-**Offline Access**: Cached content available without internet connectivity

-**Document Library**: Searchable and categorizable document management

-**Pinboard**: Quick-access pinned charts and favorite locations

-**Regulatory Information**: Updated regulatory documents and notices

-**Cross-Platform**: Seamless experience across iPhone and iPad with adaptive layouts, also with capability for macOS and visionOS

## Technical Stack

-**Language**: Swift 5.9+

-**UI Framework**: SwiftUI

-**Data Persistence**: SwiftData

-**Networking**: Native URLSession with custom BaseNetworkClient

-**Authentication**: Token-based authentication with Keychain storage

-**Architecture**: MVVM with Dependency Injection

-**PDF Handling**: Native PDF rendering and caching

## Requirements

- iOS 17.0 or later
- iPadOS 17.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Getting Started

### Prerequisites

Ensure you have the following installed:

- Xcode 15.0 or later
- Swift 5.9 or later
- CocoaPods or Swift Package Manager (for dependency management)

### Installation & Setup

1.**Clone the Repository**

```bash

git clone https://github.com/star-reader/eAIP-Pad-FrontEnd

cd eAIP-Pad-FrontEnd

```

2.**Configure API Keys**

- Copy `eAIP Pad/eAIP Pad/Configs/SharedKeyExample.swift` to `SharedKey.swift`
- Add your API endpoints and credentials:

  ```swift

  ```

// SharedKey.swift

structSharedKey {

staticlet apiBaseURL ="YOUR_API_BASE_URL"

staticlet authEndpoint ="YOUR_AUTH_ENDPOINT"

// Add other required keys

    }

    ```

3.**Open Xcode Project**

```bash

open "eAIP Pad/eAIP Pad.xcodeproj"

```

4.**Build & Run**

- Select your target device (iPhone simulator, iPad simulator, or physical device)
- Press Cmd+R or select Product > Run
- The application will build and launch on your selected device

### First Run

- Complete the onboarding flow to set up your account
- Authenticate using your credentials
- Subscribe to enable access to all premium features
- Allow necessary permissions for location and notifications

## Development

### Project Configuration

Key configuration files:

- [eAIP Pad/eAIP Pad/Configs/AppEnvironment.swift](eAIP%20Pad/eAIP%20Pad/Configs/AppEnvironment.swift): Environment-specific settings
- [eAIP Pad/eAIP Pad/Services/Network/APIEndpoints.swift](eAIP%20Pad/eAIP%20Pad/Services/Network/APIEndpoints.swift): API endpoint definitions
- [eAIP Pad/eAIP Pad/eAIP-Pad-Info.plist](eAIP%20Pad/eAIP%20Pad/eAIP-Pad-Info.plist): App configuration

### Building for Production

1. Select the "eAIP Pad" scheme
2. Select "Generic iOS Device" as the target
3. Press Cmd+B to build
4. Archive using Product > Archive
5. Distribute through App Store Connect

### Testing

- Unit tests for services and view models
- Integration tests for network requests
- UI tests for critical user flows
- Run all tests: Cmd+U in Xcode

## Contributing

Contributions are welcome and greatly appreciated. To contribute:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please ensure:

- Code follows Swift style guidelines
- All tests pass before submitting PR
- Commit messages are clear and descriptive
- Changes include relevant tests and documentation

## Code Style

- Use Swift naming conventions (camelCase for variables and functions, PascalCase for types)
- Keep functions concise and focused
- Add documentation comments for public APIs
- Use type inference appropriately
- Prefer guards over nested ifs for error handling

## Troubleshooting

### Build Issues

- Clean build folder: Cmd+Shift+K
- Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData/*`
- Update pods: `pod install`
- Restart Xcode

### Runtime Issues

- Check console output for error logs
- Enable verbose logging in AppEnvironment.swift
- Review network configuration in APIEndpoints.swift
- Verify API credentials in SharedKey.swift

### Authentication Problems

- Ensure tokens are properly stored in Keychain
- Check token expiration and refresh logic in TokenManager.swift
- Verify subscription status in SubscriptionService.swift

## Performance Considerations

- PDF caching reduces download and rendering time
- SwiftData queries are optimized with appropriate predicates
- Network requests use connection pooling
- UI updates are performed on the main thread
- Background downloads prevent blocking user interactions

## Security Considerations

- All sensitive data (tokens, credentials) stored in Keychain
- HTTPS enforced for all network communications
- API endpoints require valid authentication tokens
- Subscription validation through JWT signature verification
- User data masking for privacy protection

## License

This project is licensed under the [CC0-1.0 license](https://github.com/star-reader/eAIP-Pad-FrontEnd#CC0-1.0-1-ov-file). See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Swift and SwiftUI communities
- Apple documentation and frameworks
- Aviation data providers
- Our users and testers
