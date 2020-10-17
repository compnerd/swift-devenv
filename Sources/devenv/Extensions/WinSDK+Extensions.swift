/**
 * Copyright 2020 Saleem Abdulrasool <compnerd@compnerd.org>
 * All Rights Reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 **/

import WinSDK

// winnt.h
@_transparent
internal var KEY_READ: DWORD {
  DWORD((STANDARD_RIGHTS_READ | KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY) & ~SYNCHRONIZE)
}

@_transparent
internal func MAKELANGID(_ p: WORD, _ s: WORD) -> DWORD {
  return DWORD((s << 10) | p)
}

@_transparent
internal func HRESULT_FACILITY(_ hr: HRESULT) -> WORD {
  return WORD((Int32(hr) >> 16) & 0x1fff)
}

@_transparent
internal func HRESULT_CODE(_ hr: HRESULT) -> WORD {
  return WORD(Int32(hr) & 0xffff)
}
