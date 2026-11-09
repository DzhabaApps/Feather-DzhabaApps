"""Exercise the production ZIP installer against local fixtures on macOS."""
import pathlib
import shutil
import struct
import subprocess
import tempfile
import zipfile


root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="dr-game-archive-") as work:
    work = pathlib.Path(work)
    sources = work / "Sources/ArchiveCheck"
    sources.mkdir(parents=True)
    shutil.copy2(root / "Feather/Backend/Storage/GameArchive.swift", sources)
    (work / "Package.swift").write_text("""// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ArchiveCheck", platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation", exact: "0.9.20")],
    targets: [.executableTarget(name: "ArchiveCheck",
        dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")])])
""")
    fixtures = work / "fixtures"
    fixtures.mkdir()
    for name, path in [("valid", "GTAV/sub/data"), ("escape", "GTAV/../../escaped"), ("corrupt", "GTAV/data")]:
        with zipfile.ZipFile(fixtures / f"{name}.zip", "w") as archive:
            archive.writestr(path, "game-bytes")
            if name == "valid":
                archive.writestr("__MACOSX/GTAV/sub/._data", "metadata")
    corrupt = fixtures / "corrupt.zip"
    corrupt.write_bytes(corrupt.read_bytes().replace(b"game-bytes", b"fake-bytes", 1))
    regular = (fixtures / "valid.zip").read_bytes()
    end = len(regular) - 22
    directory_size, directory_offset = struct.unpack_from("<II", regular, end + 12)
    extended = struct.pack("<IQHHIIQQQQ", 0x06064B50, 44, 45, 45, 0, 0, 2, 2, directory_size, directory_offset)
    locator = struct.pack("<IIQI", 0x07064B50, 0, end, 1)
    footer = struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0)
    (fixtures / "zip64.zip").write_bytes(regular[:end] + extended + locator + footer)
    (sources / "main.swift").write_text("""
import Foundation
let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let target = fixtures.appendingPathComponent("out", isDirectory: true)
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
let game = target.appendingPathComponent("GTAV")
let id = UUID()
func install(_ name: String, replacing: Bool = false) throws {
    try GameArchive.install(fixtures.appendingPathComponent(name + ".zip"), in: target,
                            replacing: replacing, transferID: id)
}
try install("zip64")
let data = try String(contentsOf: game.appendingPathComponent("sub/data"), encoding: .utf8)
precondition(data == "game-bytes")
precondition(!FileManager.default.fileExists(atPath: target.appendingPathComponent("__MACOSX").path))
do {
    try install("valid")
    fatalError("Overwrote an existing folder without permission")
} catch GameArchive.Failure.destinationExists {}
for rejected in ["corrupt", "escape"] {
    do {
        try install(rejected, replacing: true)
        fatalError("Accepted an invalid ZIP")
    } catch {}
    let preserved = try String(contentsOf: game.appendingPathComponent("sub/data"), encoding: .utf8)
    precondition(preserved == "game-bytes")
    precondition(FileManager.default.fileExists(atPath: fixtures.appendingPathComponent(rejected + ".zip").path))
}
try install("valid", replacing: true)
precondition(!FileManager.default.fileExists(atPath: target.appendingPathComponent(".DRStore-" + id.uuidString).path))
precondition(!FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("escaped").path))
print("Game archive: ZIP64, CRC, traversal rejection, overwrite consent and staged replacement passed.")
""")
    subprocess.run(["swift", "run", "--package-path", str(work), "ArchiveCheck", str(fixtures)], check=True)
