//
//  ServerView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import NimbleJSON
import NimbleViews

// MARK: - Extension: Model
extension ServerView {
	struct ServerPackModel: Decodable {
		var cert: String
		var ca: String
		var key: String
		var info: ServerPackInfo
		
		private enum CodingKeys: String, CodingKey {
			case cert, ca, key1, key2, info
		}
		
		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			cert = try container.decode(String.self, forKey: .cert)
			ca = try container.decode(String.self, forKey: .ca)
			let key1 = try container.decode(String.self, forKey: .key1)
			let key2 = try container.decode(String.self, forKey: .key2)
			key = key1 + key2
			info = try container.decode(ServerPackInfo.self, forKey: .info)
		}
		
		struct ServerPackInfo: Decodable {
			var issuer: Domains
			var domains: Domains
		}
		
		struct Domains: Decodable {
			var commonName: String
			
			private enum CodingKeys: String, CodingKey {
				case commonName = "commonName"
			}
		}
	}
}

// MARK: - View
struct ServerView: View {
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	private let _serverMethods: [String] = [.localized("Fully Local"), .localized("Semi Local")]
	
	
	// MARK: Body
	var body: some View {
		Group {
			Section {
				Picker(.localized("Server Type"), systemImage: "server.rack", selection: $_serverMethod) {
					ForEach(_serverMethods.indices, id: \.description) { index in
						Text(_serverMethods[index]).tag(index)
					}
				}
				Toggle(.localized("Only use localhost address"), systemImage: "lifepreserver", isOn: $_ipFix)
					.disabled(_serverMethod != 1)
			}
			
			SSLUpdateSection()
		}
	}
}

struct SSLUpdateSection: View {
	@State private var isUpdating = false
	@State private var result: Bool?
	@State private var showResult = false
	var body: some View {
		Section {
			Button {
				guard !isUpdating else { return }
				isUpdating = true
				FR.downloadSSLCertificates(from: "https://backloop.dev/pack.json") { success in
					DispatchQueue.main.async {
						isUpdating = false
						result = success
						showResult = true
					}
				}
			} label: {
				HStack {
					Label(.localized("Update SSL Certificates"), systemImage: "arrow.down.doc")
					Spacer()
					if isUpdating { ProgressView() }
				}
			}
			.disabled(isUpdating)
		} footer: { Text(.localized("SSL update explanation")) }
		.alert(.localized("SSL Certificates"), isPresented: $showResult) {
			Button(.localized("OK"), role: .cancel) {}
		} message: {
			Text(result == true ? .localized("Certificates updated successfully.") : .localized("Failed to download, check your internet connection and try again."))
		}
	}
}
