import Foundation
import Vapor

extension ServerInstaller {
    func setupApp(port: Int) throws -> Application {
        let app = Application(.production)
        app.threadPool = .init(numberOfThreads: 1)
        app.http.server.configuration.address = .hostname("127.0.0.1", port: port)
        app.http.server.configuration.tcpNoDelay = true
        return app
    }
}
