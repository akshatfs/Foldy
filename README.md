<h1 align="center">
  <img src="Foldy/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="64" style="vertical-align: middle;">
  <span style="vertical-align: middle;">Foldy</span>
</h1>

**Foldy** is a powerful and lightweight macOS Quick Look extension that lets you preview the contents of folders and archive files without extracting or opening them. Simply select an archive, press `Space`, and explore its structure instantly.

**Warning**: Foldy is 100% vibe coded and bzip support is experimental.

## features

- **Instant Previews**: View archive contents immediately using Quick Look.
- **Finder-like Interface**: Navigate file hierarchies with a familiar list view.
- **Wide Format Support**: Handles all common archive formats including Zip, Tar, Gzip and Rar.
- **Memory Efficient**: Streams data to preview large archives without loading them entirely into memory.
- **Detailed Info**: Displays file names, sizes, and modification dates.
- **Dark Mode Ready**: Fully supports macOS appearance modes.

## Supported Formats

Foldy currently supports the following archive types:

- **ZIP** (`.zip`)
- **TAR** (`.tar`)
- **GZip** (`.gz`)
- **Tar + GZip** (`.tgz`, `.tar.gz`)
- **RAR** (`.rar`) - Supports both v4 and v5
- **Tar + BZip** (`.bz2`, `.tar.bz2`)

## Installation From Source

1. Clone the repository:

   ```bash
   git clone https://github.com/akshatfs/foldy.git
   ```

2. Open `Foldy.xcodeproj` in Xcode.
3. Build and run the `Foldy` scheme.

## Usage

1. Locate any supported archive file in **Finder**.
2. Select the file.
3. Press the **Spacebar**.
4. A Quick Look window will appear showing the contents of the archive.

## Troubleshooting

If the preview doesn't appear:

1. Open **System Settings** -> **Privacy & Security** -> **Extensions** -> **Quick Look**.
2. Ensure **Foldy** is enabled.
3. Run `qlmanage -r` in Terminal to reset the Quick Look cache.
4. Relaunch Finder (`Option` + `Right Click` Finder icon -> Relaunch).

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## Credits

This project uses bzip2.swift package from awxkee. [Link](https://github.com/awxkee/bzip2.swift.git)

---

Built with ❤️ for macOS.