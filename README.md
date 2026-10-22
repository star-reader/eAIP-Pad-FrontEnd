# eAIP Pad

A native iPhone and iPad reader for China eAIP charts and aeronautical documents, built with SwiftUI.

Import an official EAIP Web package to browse offline, or connect to a static HTTPS server hosting an extracted package. Search airports, open terminal and enroute charts, read publications, and pin frequently used documents for quick access.

| Airport Charts and PDF Reading | Enroute and Area Charts |
| :---: | :---: |
| [![Airport chart list and approach chart displayed side by side on iPad](assets/ipad-airport-charts.png)](assets/ipad-airport-charts.png) | [![Guangzhou area chart displayed in the iPad PDF reader](assets/ipad-area-chart.png)](assets/ipad-area-chart.png) |

## Features

- **Airport charts and regulations** — Browse charts by airport and filter by SID, STAR, approach, airport, or other chart types. Open individual AD documents when an airport has multiple regulations.
- **Enroute and area charts** — Browse and filter enroute charts, including area charts identified by ARC or localized names.
- **Document library** — Read AIP, SUP, AIC, and NOTAM documents. AIP documents include GEN, ENR, and AD general sections.
- **PDF reading** — Read PDFs with continuous scrolling, zoom, rotate, jump to the first or last page, share, export, and print. Rotation preserves each page's original orientation.
- **Pinboard** — Pin frequently used charts and documents, then open them from the quick-access panel. Its display style stays synchronized with Settings.
- **Local and online data sources** — Import ZIP archives or extracted folders, copy a hosted package for offline use, or request documents on demand.
- **AIRAC cycle management** — Track package versions and effective dates, replace an imported cycle, and clean up older data while preserving the active source.
- **Adaptive navigation** — Use tab navigation on iPhone and a multicolumn layout on iPad. Visited pages retain their in-memory results and pending requests across navigation.
- **Appearance settings** — Follow the system appearance or choose light/dark mode manually.

The AMDT document tab is temporarily hidden. Imports accept both official tree-shaped AMDT indexes and flat document indexes.

## Technical Stack

| Area | Technology |
| --- | --- |
| Language and concurrency | Swift, async/await, actors, and bounded task groups |
| Interface | SwiftUI with adaptive iPhone/iPad navigation |
| Local persistence | SwiftData for document metadata, cycle configuration, preferences, pins, and annotations |
| PDF rendering | PDFKit |
| Online package access | URLSession fetching static files over HTTPS |
| ZIP extraction | [ZIPFoundation](https://github.com/weichsel/ZIPFoundation), managed with Swift Package Manager |
| Data core | `EAIPDataCore`, a shared Swift package for parsing, importing, storage, and online sources |
| Regression testing | Swift Testing with temporary data stores and injected network transports |
| Diagnostics | OSLog and application logs |

Package extraction, parsing, PDF initialization, and major file operations run off the main actor. Imports prepare and validate files before committing metadata, preserving the previous usable source if preparation or database submission fails.

## Requirements

- **App:** iOS 17 or iPadOS 17 or later.
- **Development:** macOS with Xcode 26 or later and a Swift 6.2+ toolchain.
- **Data-core tests:** macOS 14 or later with the same Swift toolchain.

Swift Package Manager resolves the project's dependencies automatically.

## Getting Started

### Build and run

```bash
git clone https://github.com/star-reader/eAIP-Pad-FrontEnd.git
cd eAIP-Pad-FrontEnd
open "eAIP Pad/eAIP Pad.xcodeproj"
```

1. Let Xcode resolve package dependencies.
2. Select the **eAIP Pad** scheme and an iPhone or iPad simulator.
3. Build and run with **Command-R**.
4. For a physical device, select your development team under **Signing & Capabilities**.

### Load your first package

Data packages are obtained separately from the [official China eAIP website](https://www.eaipchina.cn/). Choose the **Full Package (Web)** format.

In the app, open **Profile → Import AIRAC Package**, then choose a ZIP archive, an extracted folder, or the online server setup flow. Once local import or online copying completes, charts and documents are available offline.

## AIRAC Data Packages

### Package structure

The reader uses the official Web package's metadata, JSON indexes, and referenced PDF files. Keep their relative paths intact:

```text
package-root/
├── index.html
└── Data/
    ├── Customers.js
    ├── JsonPath/
    │   ├── AD.JSON
    │   ├── GEN.JSON
    │   ├── ENR.JSON
    │   ├── SUP.JSON       # Optional
    │   ├── AIC.JSON       # Optional
    │   ├── NOTAM.JSON     # Optional
    │   └── AMDT.JSON      # Optional; tree or flat document index
    └── ...               # PDF files at the paths specified by the indexes
```

`Customers.js` supplies the cycle identifier and effective date. AD, GEN, and ENR indexes are required; supported optional indexes may be absent. Every PDF referenced by the parsed catalog must be readable and valid before a local import or online copy is activated.

### Local import

- **ZIP archive:** Select the original package archive. The importer finds the package root, including when it is inside a wrapper folder, and ignores macOS metadata directories. Archives containing multiple packages are rejected.
- **Extracted folder:** Select the package root containing `Data`, rather than the `Data` directory itself.

Imports validate indexes, document identities, file paths, and PDFs. Invalid paths, symlinks, corrupt files, and missing referenced PDFs cause the import to fail without replacing the previous usable source. Reimporting the same cycle replaces its catalog and cached documents.

Packages imported with an older parser should be reimported to recover documents that were previously omitted.

Existing PDFs saved by older app versions remain readable, including unescaped cycle directories such as `2026-09.V1`. Reimporting is unnecessary when those cached files are intact.

### Online sources

Host the extracted Web package on a static HTTPS server and enter its **package root URL**, for example:

```text
https://example.com/eaip/current/
```

The app reads files such as `Data/Customers.js` and `Data/JsonPath/AD.JSON` directly beneath that root. Paths beginning with `/Data/` also resolve beneath the configured package root, rather than the domain root. Enter a plain HTTPS URL without embedded credentials, query parameters, or fragments; files must be directly accessible without an interactive sign-in.

| Mode | Stored on the device | Offline browsing |
| --- | --- | --- |
| **Copy** | Server configuration, cycle metadata, catalog, and validated PDFs | Available after initialization completes |
| **Request** | Server and cycle configuration; lists and PDFs are fetched when opened | Requires a connection to load content |

Copy mode downloads up to four PDFs concurrently. Transient network failures and selected HTTP errors retry up to two times with backoff. Request mode retains visited content in memory during navigation but does not persist that content to disk.

A missing optional index may return HTTP 404. Other unsuccessful responses or malformed indexes fail validation. If the server changes its cycle, configure the source again; the app rejects detected cycle changes instead of mixing catalogs and PDFs from different cycles. Pull to refresh supported lists to request fresh results.

### Data management

Open **Profile → Manage AIRAC Data**:

- **Clean old cycles** removes older imported data while preserving the active cycle's offline files and server configuration.
- **Delete all AIRAC data** requires a separate confirmation and removes all cycle data and server configuration. Import or configure a source again before browsing.

Both actions preserve pins and annotations. Preserving these records does not preserve the underlying PDFs: a pinned document still needs an available data source. The store retains the most recently imported/configured cycle and up to two other cycles, removing older entries automatically.

## Development

### Repository layout

```text
eAIP Pad/eAIP Pad/
├── Common/             # Shared helpers and document identities
├── Configs/            # Logging environment and Bundle version helpers
├── Models/             # Package formats, presentation models, and SwiftData models
├── Services/           # Import, storage, online access, PDF loading, and logging
└── Views/              # SwiftUI screens and shared interface components
Tests/EAIPDataCoreTests/ # Data-core regression tests
Package.swift           # EAIPDataCore package and test target
```

### Run regression tests

From the repository root:

```bash
swift test
```

Tests cover local and ZIP imports, document namespaces, rollback and cancellation, online modes, concurrent downloads, retries, cleanup, page loading, classification, PDF rotation, and preference migration. Network tests use injected transports and do not require a live package server.

### Build the application

```bash
xcodebuild \
  -project "eAIP Pad/eAIP Pad.xcodeproj" \
  -scheme "eAIP Pad" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The package tests verify the data core; the simulator build checks application integration. For interface changes, also run the app on iPhone and iPad layouts and check navigation, appearance, empty states, and loading/error feedback.

## Contributing

Bug reports, documentation improvements, and focused pull requests are welcome.

1. Fork the repository and create a branch from `main`.
2. Make a focused change using the existing Swift and SwiftUI conventions.
3. Add or update regression tests when changing parsing, storage, or network behavior.
4. Run the relevant tests and build the application. Include screenshots for interface changes.
5. Open a pull request against `main` describing the problem, resulting behavior, and validation performed.

Keep parsing and storage behavior shared between local and online sources. Preserve existing user data and rollback behavior when changing imports or cleanup. Update this README when changing setup, package requirements, or user-visible workflows.

For bug reports, include the app version/build, device and OS version, AIRAC cycle, data-source mode, reproduction steps, and the displayed error. For parser issues, include a minimal sanitized index sample when possible rather than an entire data package.

## Troubleshooting

### Xcode cannot build or resolve dependencies

- Check that the selected Xcode provides Swift 6.2 or later. Use `xcode-select -p` and `swift --version` to inspect the active tools.
- Open `eAIP Pad/eAIP Pad.xcodeproj` and select the **eAIP Pad** scheme.
- Use **File → Packages → Resolve Package Versions** if ZIPFoundation has not resolved.
- For persistent build artifacts, try **Product → Clean Build Folder** before rebuilding.
- For physical-device signing errors, select a valid development team and signing configuration.

### Local import fails

- Confirm that the download is a **Full Package (Web)**, not a PDF-only collection.
- For folder import, select the directory containing `Data/Customers.js` and `Data/JsonPath`.
- Keep the package's original filenames and folder structure. Download it again if a referenced PDF is missing or corrupt.
- For ZIP import, use an archive containing exactly one package and make sure cloud-stored files have finished downloading to the device.
- Read the specific import error. A failed import keeps the previous source available.

### Online setup or document loading fails

- Verify that the configured URL points to the extracted package root over HTTPS.
- Check that `Data/Customers.js`, the required indexes, and referenced PDFs are directly accessible. Sign-in pages and HTML error responses are not package files.
- Check filename casing on the server, especially `Data/JsonPath/*.JSON`.
- Reconfigure the source if its cycle or effective date changes.
- If offline, use a locally imported package or a completed **Copy** source. **Request** mode needs a connection to fetch content.

### A chart or document is missing

- Check the active AIRAC cycle and clear search/filter selections.
- Look under **Other** for unclassified airport charts, and **Documents → AIP → AD** for AD general documents.
- Reimport packages created before the catalog-completeness fixes.
- The **AMDT** tab is intentionally hidden; its index is still parsed during package validation and import.
- If an index reports missing fields, include a sanitized failing record in your bug report so the actual format can be checked.

### A pinned document no longer opens

Pins survive data cleanup, but the associated files or source may have been removed. Import the corresponding cycle again or restore its online source. Use **Clean old cycles** when you want to preserve the active offline data and server configuration.

### Reporting an unresolved issue

Use the in-app bug-report action to include diagnostic logs, or open a [GitHub issue](https://github.com/star-reader/eAIP-Pad-FrontEnd/issues) with the reproduction details listed above. Review logs and samples before sharing them.

## License

The source code is released under [CC0 1.0 Universal](LICENSE). EAIP data packages are obtained separately from their publisher and are not included in this repository.

## Acknowledgments

- China eAIP and the publishers of the underlying aeronautical information.
- The Swift, SwiftUI, PDFKit, and ZIPFoundation communities.
- Contributors and testers who help improve the reader.
