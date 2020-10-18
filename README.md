# swift-devenv

A helper utility to manage the development environment on Windows.

Using Swift on Windows requires some additional environment variables and files to be deployed.  This tool helps automate those tasks to make it easier to develop using Swift on Windows.  With this tool, you no longer need worry about getting the correct shell or environment variable

Using this tool to deploy the module maps is far more convenience since it uses the Windows Shell infrastructure to copy the files into the correct location.  It uses the standard Windows security mechanisms for requesting elevated privileges via UAC and ensuring that file replacement is done correctly.

### Table of Contents

- [swift-devenv](#swift-devenv)
    - [Table of Contents](#table-of-contents)
    - [Using swift-devenv](#using-swift-devenv)
    - [Deploying Module Maps](#deploying-module-maps)
    - [Setting Environment Variables](#setting-environment-variables)
        - [INCLUDE](#include)
        - [LIB](#lib)
    - [Identifying the Detected Windows SDK](#identifying-the-detected-windows-sdk)
    - [Development](#development)
        - [Build Dependencies](#build-dependencies)
        - [Building](#building)
        - [Installation](#installation)

### Using swift-devenv

One time setup:
```cmd
:: Copy the module maps for using the Windows SDK and UCRT, in case they haven't been deployed yet.
> swift devenv --deploy
```

Normal usage:
```cmd
:: Setup the environment variables
> swift devenv
:: Build the project
> swift build
```

### Deploying Module Maps

The Windows SDK and the Microsoft C library (UCRT) require modulemaps to be able to use the libraries from Swift.  These files indicate how the headers map to Swift.  The operation needs to be done each time the toolchain is updated.  This requires copying a few files into the Windows SDK installation.  swift-devenv can identify the Windows SDK installation and copy the files into the correct location in an automated fashion.

```cmd
:: Identify the Windows SDK location that the files will be copied to
> swift devenv --list-sdks
Detected Windows 10 SDK: C:\Program Files (x86)\Windows Kits\10\
Detected Windows 10 SDK Versions:
  - 10.0.19041.0
```

The `--deploy` option to `devenv` will deploy the necessary files from the toolchain installation.  It uses the `SDKROOT` environment variable to determine the location of the module maps and copies the `winsdk.modulemap` and `ucrt.modulemap` to their respective locations.

```cmd
> swift devenv --deploy
```

### Setting Environment Variables

The Swift compiler uses the `INCLUDE` and `LIB` environment variables to identify the default header (include) search path and the linker library search paths for interoperability with the system.  These environment variables are `;`-delimited lists of paths where the headers are.  The tool will identify the Windows SDK installation and construct the approriate values for these variables.

```cmd
:: Setup the development environment
> swift devenv
```

The default action of `devenv` is to set the environment variables as that is the most common operation.  You can explicitly specify `--setenv` if you like.

##### INCLUDE

The default include path contains, in order, the following components:

1. `ucrt` - the C library headers
2. `shared` - the shared user mode and kernel mode headers from the Windows SDK
3. `um` - the user mode only headers from the Windows SDK
4. `winrt` - the Windows Runtime headers
5. `cppwinrt` - the Windows Runtime C++ Projection headers

##### LIB

The default library search path contains, in order, the following components:

1. `ucrt` - the C library
2. `um` - the user mode libraries

### Identifying the Detected Windows SDK

Multiple versions of the SDK can be installed in parallel.  However, only a single version of the SDK can be used at a time.  You can inspect the detected versions of the SDKs and the install root that swift-devenv sees.

```cmd
> swift devenv --list-sdks
Detected Windows 10 SDK: C:\Program Files (x86)\Windows Kits\10\
Detected Windows 10 SDK Versions:
  - 10.0.19041.0
```

### Development

`swift-devenv` is written in Swift and uses the Swift package manager to build.

##### Build Dependencies

- The latest Swift Snapshot build (for swift-package-manager)
- Windows SDK 10.0.107763 or newer

##### Building

```cmd
:: build using swift package manager
> swift build
```

##### Installation

Installation of `swift-devenv` simply involves copying the generated binary to your toolchain root.

```cmd
> copy swift-devenv.exe %DEVELOPER_DIR%\Toolchains\unknown-Asserts-development.xctoolchain\usr\bin
```




