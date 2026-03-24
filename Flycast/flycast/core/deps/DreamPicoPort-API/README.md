# DreamPicoPort-API
USB-host-side API for host-mode DreamPicoPort

## Compiling Using Conan

If [conan](https://conan.io) is installed, it may be used to compile this API. Simply execute the following within this repository's root directory.

```bash
conan create .
```

## Compiling Using CMake

### Dependencies

After checking out this repository, execute the following to pull down the libusb dependency.
```bash
git submodule update --recursive --init
```

### Linux Prerequisites

`libudev-dev` is required to compile libusb.
```bash
sudo apt install libudev-dev
```

`cmake` is required to build the project.
```bash
sudo apt install cmake
```

### Windows Prerequisites

Install MSVC C++ compiler. This can be done by simply installing Visual Studio with C++.

### Compile

Execute the following to compile using cmake.
```bash
cmake --no-warn-unused-cli -S. -B./build
cmake --build ./build --config Release -j 10
```
