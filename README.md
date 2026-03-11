<h1 align="center">
  <img src="Prvw/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="64" style="vertical-align: middle;">
  <span style="vertical-align: middle;">Prvw</span>
</h1>

**Prvw** is a powerful and lightweight macOS Quick Look extension that lets you preview the contents of folders and archive files without extracting or opening them. Simply select an archive, press `Space`, and explore its structure instantly.

**Warning**: Prvw is 100% vibe coded and bzip support is experimental.

## features

- **Instant Previews**: View archive contents immediately using Quick Look.
- **Finder-like Interface**: Navigate file hierarchies with a familiar list view.
- **Wide Format Support**: Handles all common archive formats including Zip, Tar, Gzip and Rar.
- **Memory Efficient**: Streams data to preview large archives without loading them entirely into memory.
- **Detailed Info**: Displays file names, sizes, and modification dates.
- **Dark Mode Ready**: Fully supports macOS appearance modes.

## Supported Formats

Prvw currently supports the following archive types:

- **ZIP** (`.zip`)
- **TAR** (`.tar`)
- **GZip** (`.gz`)
- **Tar + GZip** (`.tgz`, `.tar.gz`)
- **RAR** (`.rar`) - Supports both v4 and v5
- **Tar + BZip** (`.bz2`, `.tar.bz2`)

## Installation

### From Release

1. Download the DMG file from Github Releases
2. Open the DMG File and Drag and Drop the Prvw App to Applications Folder

   ### macOS Gatekeeper Warning

      Prvw is signed but **not notarized** by Apple. When you first launch the app, macOS Gatekeeper may display a security warning. This is normal and expected.

   ### How to Run the App

      When you first try to launch Prvw, Gatekeeper will display a security warning with options to "Close" or "Move to Bin".

   ### To run the app

      1. Go to **System Settings** → **Privacy & Security**
      2. Scroll down to find the Prvw security warning
      3. Click the **"Open Anyway"** button next to the warning
      4. Launch Prvw again, and you won't see the warning

### From Source

1. Clone the repository:

   ```bash
   git clone https://github.com/akshatfs/prvw.git
   ```

2. Open `Prvw.xcodeproj` in Xcode.
3. Build and run the `Prvw` scheme.

## Usage

1. Locate any supported archive file in **Finder**.
2. Select the file.
3. Press the **Spacebar**.
4. A Quick Look window will appear showing the contents of the archive.

## Troubleshooting

If the preview doesn't appear:

1. Open **System Settings** -> **Privacy & Security** -> **Extensions** -> **Quick Look**.
2. Ensure **Prvw** is enabled.
3. Run `qlmanage -r` in Terminal to reset the Quick Look cache.
4. Relaunch Finder (`Option` + `Right Click` Finder icon -> Relaunch).

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## Credits

This project uses bzip2.swift package from awxkee. [Link](https://github.com/awxkee/bzip2.swift.git)

---

Built with ❤️ for macOS.
