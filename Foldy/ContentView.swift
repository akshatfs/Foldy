//
//  ContentView.swift
//  Foldy
//
//  Created by Akshat Shukla on 15/02/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 24) {
            // App Icon Area
            Image(systemName: "folder.badge.questionmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(.blue)

            // Title
            Text("Foldy")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Status
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Quick Look Extension Installed")
                    .foregroundStyle(.secondary)
            }
            .font(.headline)

            // Divider
            Divider()
                .frame(maxWidth: 300)

            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("How to Use")
                    .font(.title3)
                    .fontWeight(.semibold)

                InstructionRow(step: "1", text: "Select any folder in Finder")
                InstructionRow(step: "2", text: "Press Space to open Quick Look")
                InstructionRow(step: "3", text: "View the folder's contents in a list view")
            }
            .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(40)
        .frame(minWidth: 440, minHeight: 400)
    }
}

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
