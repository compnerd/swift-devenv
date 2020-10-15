/**
 * Copyright 2020 Saleem Abdulrasool <compnerd@compnerd.org>
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 **/

import WinSDK
import ArgumentParser

fileprivate var szWindowsKitsInstalledRootsKey: String {
  "SOFTWARE\\Microsoft\\WIndows Kits\\Installed Roots"
}

fileprivate var szKitsRoot10: String {
  "KitsRoot10"
}

/// An error raised if no SDK version can be enumerated.
struct SDKNotFoundError: Swift.Error {
}

/// Query the registry to identify the installed root for the Windows SDK. This
/// assumes that we are looking for the Windows 10 SDK.
private func GetWindowsSDKInstallRoot() throws -> String {
  var lStatus: LSTATUS = 0
  var cbData: DWORD = 0

  lStatus =
      RegGetValueW(HKEY_LOCAL_MACHINE, szWindowsKitsInstalledRootsKey.wide,
                   szKitsRoot10.wide, DWORD(RRF_RT_REG_SZ), nil, nil, &cbData)
  guard lStatus == ERROR_SUCCESS else {
    throw Error(win32: DWORD(lStatus))
  }

  let buffer: [WCHAR] =
      try Array<WCHAR>(unsafeUninitializedCapacity: Int(cbData)) {
    cbData = DWORD($0.count * MemoryLayout<WCHAR>.size)
    lStatus =
        RegGetValueW(HKEY_LOCAL_MACHINE, szWindowsKitsInstalledRootsKey.wide,
                     szKitsRoot10.wide, DWORD(RRF_RT_REG_SZ), nil,
                     $0.baseAddress, &cbData)
    guard lStatus == ERROR_SUCCESS else {
      throw Error(win32: DWORD(lStatus))
    }
    $1 = Int(cbData)
  }

  return String(from: buffer)
}

/// Query the registry to determine what SDK versions are available. This
/// function does not guarantee an order in which the versions are returned.
private func GetWindowsSDKVersions() throws -> [String] {
  var lStatus: LSTATUS = 0
  var hKey: HKEY?

  lStatus =
      RegOpenKeyExW(HKEY_LOCAL_MACHINE, szWindowsKitsInstalledRootsKey.wide, 0,
                    KEY_READ, &hKey)
  guard lStatus == ERROR_SUCCESS else {
    throw Error(win32: DWORD(lStatus))
  }

  defer {
    lStatus = RegCloseKey(hKey)
    if lStatus != ERROR_SUCCESS {
      print(Error(win32: DWORD(lStatus)))
    }
  }

  var cSubKeys: DWORD = 0
  var cbMaxSubKeyLen: DWORD = 0
  lStatus =
      RegQueryInfoKeyW(hKey, nil, nil, nil, &cSubKeys, &cbMaxSubKeyLen, nil,
                       nil, nil, nil, nil, nil)
  guard lStatus == ERROR_SUCCESS else {
    throw Error(win32: DWORD(lStatus))
  }

  var versions: [String] = []
  for index in 0 ..< cSubKeys {
    let buffer: [WCHAR] =
        Array<WCHAR>(unsafeUninitializedCapacity: Int(cbMaxSubKeyLen + 1)) {
      var cchName: DWORD = DWORD(cbMaxSubKeyLen + 1)
      lStatus = RegEnumKeyExW(hKey, index, $0.baseAddress, &cchName, nil, nil,
                              nil, nil)
      $1 = Int(cchName)
    }

    versions.append(String(from: buffer))
  }
  return versions
}

/// Setup the environment for Development. This sets the `INCLUDE` and `LIB`
/// environment variables which are used to find the SDK includes and import
/// libraries.
private func SetupEnvironment() throws {
  let WindowsSDKDir = try GetWindowsSDKInstallRoot()

  // TODO(compnerd) sort by version and choose the highest by default
  guard let WindowsSDKVersion = try GetWindowsSDKVersions().first else {
    throw SDKNotFoundError()
  }

  let INCLUDE: [String] = [
    Path.join(WindowsSDKDir, "Include", WindowsSDKVersion, "ucrt"),
    Path.join(WindowsSDKDir, "Include", WindowsSDKVersion, "shared"),
    Path.join(WindowsSDKDir, "Include", WindowsSDKVersion, "um"),
    Path.join(WindowsSDKDir, "Include", WindowsSDKVersion, "winrt"),
    Path.join(WindowsSDKDir, "Include", WindowsSDKVersion, "cppwinrt"),
  ]
  try INCLUDE.joined(separator: ";").withCString(encodedAs: UTF16.self) {
    if !SetEnvironmentVariableW("INCLUDE".wide, $0) {
      throw Error(win32: GetLastError())
    }
  }

  let LIB: [String] = [
    Path.join(WindowsSDKDir, "Lib", WindowsSDKVersion, "ucrt", "x64"),
    Path.join(WindowsSDKDir, "Lib", WindowsSDKVersion, "um", "x64"),
  ]
  try LIB.joined(separator: ";").withCString(encodedAs: UTF16.self) {
    if !SetEnvironmentVariableW("LIB".wide, $0) {
      throw Error(win32: GetLastError())
    }
  }
}

/// Get the current value of the `SDKROOT` environment variable.
private func GetSDKROOT() throws -> String {
  let dwLength: DWORD = GetEnvironmentVariableW("SDKROOT".wide, nil, 0)
  guard dwLength > 0 else { throw Error(win32: GetLastError()) }

  let buffer: [WCHAR] =
      try Array<WCHAR>(unsafeUninitializedCapacity: Int(dwLength)) {
    let dwResult: DWORD =
        GetEnvironmentVariableW("SDKROOT".wide, $0.baseAddress, DWORD($0.count))
    guard dwResult > 0 else { throw Error(win32: GetLastError()) }
    $1 = Int(dwResult)
  }

  return String(from: buffer)
}

/// Inject the module maps to the appropriate locations into the Windows SDK and
/// ucrt installations.
private func DeployModuleMaps() throws {
  let SDKROOT: String = try GetSDKROOT()

  let WindowsSDKDir: String = try GetWindowsSDKInstallRoot()
  guard let WindowsSDKVersion = try GetWindowsSDKVersions().first else {
    throw SDKNotFoundError()
  }

  let tasks: [(source: String, destination: String)] = [
    (source: Path.join(SDKROOT, "usr", "share", "ucrt.modulemap"),
     destination: Path.join(WindowsSDKDir, "Include", WindowsSDKVersion,
                            "ucrt", "module.modulemap.1")),
    (source: Path.join(SDKROOT, "usr", "share", "winsdk.modulemap"),
     destination: Path.join(WindowsSDKDir, "Include", WindowsSDKVersion,
                            "um", "module.modulemap.1"))
  ]

  for task in tasks {
    try (task.source + "\0\0").withCString(encodedAs: UTF16.self) { wszSource in
      try (task.destination + "\0\0").withCString(encodedAs: UTF16.self) { wszDestination in
        var shfopOperation: SHFILEOPSTRUCTW =
            SHFILEOPSTRUCTW(hwnd: nil,
                            wFunc: UINT(FO_COPY),
                            pFrom: wszSource,
                            pTo: wszDestination,
                            fFlags: FILEOP_FLAGS(FOF_WANTNUKEWARNING),
                            fAnyOperationsAborted: false,
                            hNameMappings: nil,
                            lpszProgressTitle: nil)
        let iResult: CInt =  SHFileOperationW(&shfopOperation)
        guard iResult == 0 else { throw Error(win32: GetLastError()) }
      }
    }
  }
}

@main
struct devenv: ParsableCommand {
  static var configuration =
      CommandConfiguration(abstract: "Configure the Development Environment for Swift on Windows")

  enum Operation: EnumerableFlag {
  case setenv
  case deploy
  case listSdks
  }

  @Flag(help: "The operation to perform")
  private var operation: Operation = .setenv

  mutating func run() throws {
    switch self.operation {
    case .listSdks:
      let WindowsSDKDir: String = try GetWindowsSDKInstallRoot()
      print("Detected Windows 10 SDK Dir: \(WindowsSDKDir)")
      print("Detected Windows 10 SDK Versions:")
      for version in try GetWindowsSDKVersions() {
        print("  - \(version)")
      }
    case .deploy:
      try DeployModuleMaps()
    case .setenv:
      try SetupEnvironment()
    }
  }
}
