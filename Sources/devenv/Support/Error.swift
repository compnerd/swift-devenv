/**
 * Copyright 2020 Saleem Abdulrasool <compnerd@compnerd.org>
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 **/

import WinSDK

internal struct Error: Swift.Error {
  private enum ErrorCode {
  case win32(DWORD)
  case hresult(HRESULT)
  }

  private let code: ErrorCode

  public init(hr: HRESULT) {
    self.code = .hresult(hr)
  }

  public init(win32 error: DWORD) {
    self.code = .win32(error)
  }
}

extension Error: CustomStringConvertible {
  public var description: String {
    let dwFlags: DWORD = DWORD(FORMAT_MESSAGE_ALLOCATE_BUFFER)
                       | DWORD(FORMAT_MESSAGE_FROM_SYSTEM)
                       | DWORD(FORMAT_MESSAGE_IGNORE_INSERTS)

    let short: String
    let dwResult: DWORD
    var buffer: UnsafeMutablePointer<WCHAR>?

    switch self.code {
    case .win32(let error):
      short = "Win32 Error \(error)"

      dwResult = withUnsafeMutablePointer(to: &buffer) {
        $0.withMemoryRebound(to: WCHAR.self, capacity: 2) {
          FormatMessageW(dwFlags, nil, error,
                         MAKELANGID(WORD(LANG_NEUTRAL), WORD(SUBLANG_DEFAULT)),
                         $0, 0, nil)
        }
      }

    case .hresult(let hr):
      short = "HRESULT 0x\(String(DWORD(bitPattern: hr), radix: 16))"

      dwResult = withUnsafeMutablePointer(to: &buffer) {
        $0.withMemoryRebound(to: WCHAR.self, capacity: 2) {
          FormatMessageW(dwFlags, nil, DWORD(bitPattern: hr),
                         MAKELANGID(WORD(LANG_NEUTRAL), WORD(SUBLANG_DEFAULT)),
                         $0, 0, nil)
        }
      }
    }

    guard dwResult > 0, let message = buffer else { return short }
    defer { LocalFree(buffer) }
    return "\(short) - \(String(decodingCString: message, as: UTF16.self))"
  }
}
