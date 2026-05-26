// Copyright (c) 2026, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import SwiftUI

struct OEScreenshotGalleryView: View {

    let items: [URL]
    @Binding var isPresented: Bool
    @State var selectedIndex: Int
    @State private var loadedImages: [String: NSImage] = [:]

    private var currentURL: URL? { items.isEmpty ? nil : items[selectedIndex] }

    private func thumbURL(for url: URL) -> URL {
        let s = url.absoluteString.replacingOccurrences(of: "t_screenshot_big", with: "t_thumb")
        return URL(string: s) ?? url
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                imageStage
                Spacer(minLength: 0)
                thumbnailStrip
                    .padding(.bottom, 32)
            }
        }
        .galleryKeyboardNav(left: prevItem, right: nextItem)
        .onAppear {
            preloadThumbs()
            preloadFull(at: selectedIndex)
        }
        .onChange(of: selectedIndex) { _ in preloadFull(at: selectedIndex) }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("GAMEPLAY · \(selectedIndex + 1) OF \(items.count)")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Image Stage

    private var imageStage: some View {
        HStack(spacing: 0) {
            navArrow(icon: "chevron.left", action: prevItem)
            GeometryReader { geo in
                imageContainer(width: geo.size.width * 0.86)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            navArrow(icon: "chevron.right", action: nextItem)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navArrow(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func imageContainer(width: CGFloat) -> some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: width)
            .overlay(
                GeometryReader { geo in
                    imageContent(in: geo.size)
                }
            )
    }

    @ViewBuilder
    private func imageContent(in size: CGSize) -> some View {
        if let url = currentURL {
            let key = url.absoluteString
            ZStack {
                if let img = loadedImages[key] {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    OEColors.surface.frame(width: size.width, height: size.height)
                    ProgressView().frame(width: size.width, height: size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.prefix(6).enumerated()), id: \.offset) { idx, url in
                thumbCell(url: url, index: idx)
            }
            if items.count > 6 {
                Text("+\(items.count - 6) more")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.leading, 4)
            }
        }
        .padding(.top, 16)
    }

    private func thumbCell(url: URL, index: Int) -> some View {
        let thumb = thumbURL(for: url)
        let key = thumb.absoluteString
        let isActive = index == selectedIndex
        return Button { selectedIndex = index } label: {
            ZStack {
                if let img = loadedImages[key] {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 40)
                        .clipped()
                } else {
                    OEColors.surface.frame(width: 56, height: 40)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.white : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .frame(width: 56, height: 40)
        .onAppear { loadThumb(url) }
    }

    // MARK: - Navigation

    private func prevItem() {
        guard !items.isEmpty else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : items.count - 1
    }

    private func nextItem() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    // MARK: - Image Loading

    private func preloadThumbs() {
        for url in items.prefix(6) { loadThumb(url) }
    }

    private func preloadFull(at index: Int) {
        guard !items.isEmpty else { return }
        let url = items[index]
        let key = url.absoluteString
        guard loadedImages[key] == nil else { return }
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let img = NSImage(data: data) else { return }
            await MainActor.run { loadedImages[key] = img }
        }
    }

    private func loadThumb(_ url: URL) {
        let thumb = thumbURL(for: url)
        let key = thumb.absoluteString
        guard loadedImages[key] == nil else { return }
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: thumb),
                  let img = NSImage(data: data) else { return }
            await MainActor.run { loadedImages[key] = img }
        }
    }
}
