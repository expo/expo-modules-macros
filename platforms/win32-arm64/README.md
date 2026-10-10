# @expo/modules-macros-win32-arm64

The Windows arm64 build of the `expo-modules-macros` compiler plugin and scanner (`ExpoModulesMacros.exe`).

Don't install this package directly. `expo-modules-macros` lists it as an optional dependency, and package managers install it only on Windows arm64, because of its `os` and `cpu` fields. `getScannerBinaryPath()` in `expo-modules-macros` returns the path of the executable in it.

The Swift runtime is linked in statically, so the executable runs without a Swift toolchain. It needs only Windows system libraries and the Microsoft Visual C++ runtime.
