/**
 * Copyright 2020 Saleem Abdulrasool <compnerd@compnerd.org>
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 **/

import WinSDK
import SwiftCOM
import ArgumentParser

private func WIN32_FROM_HRESULT(_ hr: HRESULT) -> WORD? {
  // guard DWORD(hr) & DWORD(0x80000000) == DWORD(0x80000000) else { return nil }
  guard HRESULT_FACILITY(hr) == FACILITY_WIN32 else { return nil }
  return HRESULT_CODE(hr)
}

fileprivate var szWindowsKitsInstalledRootsKey: String {
  "SOFTWARE\\Microsoft\\Windows Kits\\Installed Roots"
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

private class DeployModuleMapProgressPrinter: SwiftCOM.IFileOperationProgressSink {
  override public func PostCopyItem(_ dwFlags: DWORD,
                                    _ psiItem: SwiftCOM.IShellItem,
                                    _ psiDestinationFolder: SwiftCOM.IShellItem,
                                    _ pszNewName: String, _ hrCopy: HRESULT,
                                    _ psiNewlyCreated: SwiftCOM.IShellItem)
      -> HRESULT {
    guard hrCopy == S_OK else { return S_OK }
    if let source = try? psiItem.GetDisplayName(SIGDN_FILESYSPATH),
        let destination = try? psiNewlyCreated.GetDisplayName(SIGDN_FILESYSPATH) {
      print("Deployed \(source) to \(destination)")
    }
    return S_OK
  }
}

/// Inject the module maps to the appropriate locations into the Windows SDK and
/// ucrt installations.
private func DeployModuleMaps() throws {
  let SDKROOT: String = try GetSDKROOT()

  let WindowsSDKDir: String = try GetWindowsSDKInstallRoot()
  guard let WindowsSDKVersion = try GetWindowsSDKVersions().first else {
    throw SDKNotFoundError()
  }

  let items: [(source: String, destination: String)] = [
    (source: Path.join(SDKROOT, "usr", "share", "ucrt.modulemap"),
     destination: Path.join(WindowsSDKDir, "Include", WindowsSDKVersion,
                            "ucrt", "module.modulemap")),
    (source: Path.join(SDKROOT, "usr", "share", "winsdk.modulemap"),
     destination: Path.join(WindowsSDKDir, "Include", WindowsSDKVersion,
                            "um", "module.modulemap"))
  ]

  // NOTE: we must use APARTMENTTHREADED as `IFileOperation` only supports the
  // apartment threading model.  Disable OLE DDE while at it.
  let dwCoInit: DWORD = DWORD(COINIT_APARTMENTTHREADED.rawValue)
                      | DWORD(COINIT_DISABLE_OLE1DDE.rawValue)

  let hr: HRESULT = CoInitializeEx(nil, dwCoInit)
  guard hr == S_OK else { throw COMError(hr: hr) }
  defer { CoUninitialize() }

  let pFOp: SwiftCOM.IFileOperation =
      try IFileOperation.CreateInstance(class: CLSID_FileOperation)
  defer { _ = try? pFOp.Release() }

  let dwOperationFlags: DWORD = DWORD(FOF_FILESONLY)
                              | DWORD(FOF_SILENT)
                              | DWORD(FOF_WANTNUKEWARNING)
                              | DWORD(FOFX_PREFERHARDLINK)
                              | DWORD(FOFX_SHOWELEVATIONPROMPT)
  try pFOp.SetOperationFlags(dwOperationFlags)

  let pFOpProgress: DeployModuleMapProgressPrinter =
      DeployModuleMapProgressPrinter()

  let dwCookie: DWORD = try pFOp.Advise(pFOpProgress)

  try items.forEach { item in
    let psiSource: SwiftCOM.IShellItem
    do {
      psiSource = try SHCreateItemFromParsingName(item.source, nil)
    } catch {
      guard let hr = (error as? SwiftCOM.COMError)?.hr,
            let dwError = WIN32_FROM_HRESULT(hr),
            dwError == ERROR_FILE_NOT_FOUND else {
        throw error
      }
      print("Unable to find \(item.source)")
      return
    }
    defer { _ = try? psiSource.Release() }

    let psiDestinationFolder: SwiftCOM.IShellItem =
        try SHCreateItemFromParsingName(Path.dirname(item.destination), nil)
    defer { _ = try? psiDestinationFolder.Release() }

    try pFOp.CopyItem(psiSource, psiDestinationFolder,
                      Path.basename(item.destination), nil)
  }

  do {
    try pFOp.PerformOperations()
  } catch {
    print(error)
  }

  try pFOp.Unadvise(dwCookie)
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
