import SwiftUI
import Combine
import AltSourceKit
import NimbleViews

struct DownloadButtonView: View {
	let app: ASRepository.App
	@ObservedObject private var downloadManager = DownloadManager.shared
	@ObservedObject private var installer = RepositoryInstallCoordinator.shared
	@State private var downloadProgress: Double = 0
	@State private var cancellable: AnyCancellable?

	private var source: URL? {
		app.currentDownloadUrl.map { RepositoryFileIdentity.sourceURL(downloadURL: $0, version: app.currentVersion) }
	}
	private var download: Download? {
		guard let source else { return nil }
		return downloadManager.getDownload(by: source.absoluteString)
	}
	private var localApp: AppInfoPresentable? {
		guard let source else { return nil }
		return installer.libraryApp(for: source)
	}

	var body: some View {
		Group {
			if let download {
				Button {
					if download.progress < 1 { downloadManager.cancelDownload(download) }
				} label: {
					ZStack {
						Circle().trim(from: 0, to: downloadProgress)
							.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
							.rotationEffect(.degrees(-90)).frame(width: 31, height: 31)
						Image(systemName: download.progress >= 1 ? "archivebox" : "square.fill")
							.font(.footnote.bold())
					}
				}
				.buttonStyle(.borderless)
				.disabled(download.progress >= 1)
				.accessibilityLabel(.localized(download.progress >= 1 ? "Unpacking" : "Cancel download"))
				.accessibilityValue("\(Int(downloadProgress * 100))%")
			} else {
				let downloaded = localApp
				Button {
					if let downloaded {
						installer.install(downloaded)
					} else if let url = app.currentDownloadUrl, let source {
						_ = downloadManager.startDownload(from: url, id: source.absoluteString, source: source)
					}
				} label: {
					Text(.localized(downloaded == nil ? "Download" : "Install"))
						.font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.8)
						.padding(.horizontal, 12).padding(.vertical, 8)
						.background(Color(uiColor: .quaternarySystemFill)).clipShape(Capsule())
				}
				.buttonStyle(.borderless)
				.disabled(source == nil || installer.isBusy)
			}
		}
		.onAppear(perform: setupObserver)
		.onDisappear { cancellable?.cancel() }
		.onChange(of: downloadManager.downloads.description) { _ in setupObserver() }
		.animation(.easeInOut(duration: 0.3), value: download != nil)
	}

	private func setupObserver() {
		cancellable?.cancel()
		guard let download else { downloadProgress = 0; return }
		downloadProgress = download.overallProgress
		cancellable = Publishers.CombineLatest(download.$progress, download.$unpackageProgress)
			.receive(on: DispatchQueue.main)
			.sink { _, _ in downloadProgress = download.overallProgress }
	}
}
