//
//  Server+Compute.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import UIKit.UIGraphicsImageRenderer

extension ServerInstaller {
	var plistEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = self.getServerMethod() == 1 ? "http" : "https"
		comps.host = sni()
		comps.path = "/\(id).plist"
		comps.port = port
		return comps.url!
	}

	var payloadEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = self.getServerMethod() == 1 ? "http" : "https"
		comps.host = sni()
		comps.path = "/\(id).ipa"
		comps.port = port
		return comps.url!
	}
	
	var pageEndpoint: URL {
        if InstallRelayClient.semiLocalLabEnabled,
           let decoded = externalServerLink.removingPercentEncoding,
           var remote = URLComponents(string: decoded) {
            remote.path = remote.path.replacingOccurrences(of: "/manifest.plist", with: "/install")
            if let url = remote.url { return url }
        }
		var comps = URLComponents()
		comps.scheme = self.getServerMethod() == 1 ? "http" : "https"
		comps.host = sni()
		comps.path = "/install"
		comps.port = port
		return comps.url!
	}
	
	var externalServerLink: String {
        if InstallRelayClient.semiLocalLabEnabled {
            // The private endpoint is injected only into the owner's test IPA.
            // Failure must not silently switch this experiment to Palera or TLS.
            guard let value = Bundle.main.object(forInfoDictionaryKey: "DRStoreSemiLocalLabEndpoint") as? String,
                  let endpoint = URL(string: value),
                  let url = try? InstallRelayClient.semiLocalManifestURL(endpoint: endpoint, id: id, port: port,
                      bundleID: app.identifier ?? "", version: app.version ?? "1", title: app.name ?? "Приложение"),
                  let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
                return ""
            }
            return encoded
        }
		let baseUrl = "https://api.palera.in/genPlist?bundleid=\(app.identifier!)&name=\(app.name!)&version=\(app.version!)&fetchurl=\(self.payloadEndpoint.absoluteString)"
		let encodedBaseUrl = baseUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
		let finalEncodedUrl = encodedBaseUrl.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
		
		return finalEncodedUrl
	}

	var iTunesLink: String {
		_iTunesLink(with: plistEndpoint.absoluteString)
	}
	
	var iTunesLinkExternal: String {
		_iTunesLink(with: externalServerLink)
	}
	
	private func _iTunesLink(with url: String) -> String {
		return "itms-services://?action=download-manifest&url=\(url)"
	}

	var displayImageSmallEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = InstallRelayClient.semiLocalLabEnabled ? "http" : "https"
		comps.host = sni()
		comps.path = "/app57x57.png"
		comps.port = port
		return comps.url!
	}

	var displayImageLargeEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = InstallRelayClient.semiLocalLabEnabled ? "http" : "https"
		comps.host = sni()
		comps.path = "/app512x512.png"
		comps.port = port
		return comps.url!
	}
	
	var displayImageSmallData: Data {
		_createIcon(57)
	}
	
	var displayImageLargeData: Data {
		_createIcon(512)
	}
	
	private func _createIcon(_ r: CGFloat) -> Data {
		let renderer = UIGraphicsImageRenderer(size: .init(width: r, height: r))
		let image = renderer.image { ctx in
			UIColor.tintColor.setFill()
			ctx.fill(.init(x: 0, y: 0, width: r, height: r))
		}
		return image.pngData()!
	}

	var html: String {
		"""
		<html style="background-color: black;">
		<script type="text/javascript">window.location="\(iTunesLinkExternal)"</script>
		</html>
		"""
	}

	var installManifest: [String: Any] {[
		"items": [[
			"assets": [
				[
					"kind": "software-package",
					"url": payloadEndpoint.absoluteString,
				],
				[
					"kind": "display-image",
					"url": displayImageSmallEndpoint.absoluteString,
				],
				[
					"kind": "full-size-image",
					"url": displayImageLargeEndpoint.absoluteString,
				],
			],
			"metadata": [
				"bundle-identifier": app.identifier,
				"bundle-version": app.version,
				"kind": "software",
				"title": app.name,
			],
		],],
	]}

	var installManifestData: Data {
		(try? PropertyListSerialization.data(
			fromPropertyList: installManifest,
			format: .xml,
			options: .zero
		)) ?? .init()
	}
}
