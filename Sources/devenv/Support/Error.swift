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
    switch self.code {
    case .win32(let error):
      let buffer: UnsafeMutablePointer<WCHAR>? = nil
      let dwResult: DWORD =
          FormatMessageW(DWORD(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS),
                        nil, error,
                        MAKELANGID(WORD(LANG_NEUTRAL), WORD(SUBLANG_DEFAULT)),
                        buffer, 0, nil)
      guard dwResult == 0, let message = buffer else {
        return "Error \(error)"
      }
      defer { LocalFree(buffer) }
      return "Win32 Error \(error) - \(String(decodingCString: message, as: UTF16.self))"

    case .hresult(let hr):
      let buffer: UnsafeMutablePointer<WCHAR>? = nil
      let dwResult: DWORD =
          FormatMessageW(DWORD(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS),
                        nil, DWORD(bitPattern: hr),
                        MAKELANGID(WORD(LANG_NEUTRAL), WORD(SUBLANG_DEFAULT)),
                        buffer, 0, nil)
      guard dwResult == 0, let message = buffer else {
        return "HRESULT(0x\(String(DWORD(bitPattern: hr), radix: 16)))"
      }
      defer { LocalFree(buffer) }
      return "0x\(String(DWORD(bitPattern: hr), radix: 16)) - \(String(decodingCString: message, as: UTF16.self))"
    }
  }
}
