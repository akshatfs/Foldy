//
//  ContentView.swift
//  Foldy
//
//  Created by Akshat Shukla on 15/02/26.
//

import SwiftUI

// MARK: - Content View

struct ContentView: View {
    var body: some View {
        VStack(spacing: 24) {
            // App Icon + Title side by side
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)

                Text("Foldy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            Divider()

            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("How to Use")
                    .font(.title3)
                    .fontWeight(.semibold)

                InstructionRow(step: "1", text: "Select any folder or archive file in Finder")
                InstructionRow(step: "2", text: "Press Space to open Quick Look")
                InstructionRow(step: "3", text: "View the contents in a list view")
            }

            Divider()

            // Supported File Types
            VStack(alignment: .leading, spacing: 8) {
                Text("Supported File Types")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Folder (dir), ZIP (.zip), TAR (.tar), GZip (.gz, .tgz, .tar.gz), RAR (.rar)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .fixedSize()
    }
}

// MARK: - Supporting Views

struct InstructionRow: View {
    let step: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    ContentView()
}
