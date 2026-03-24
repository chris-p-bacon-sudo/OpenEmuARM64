from conan import ConanFile
from conan.tools.cmake import CMake, CMakeToolchain, CMakeDeps
from conan.tools.files import copy as conan_copy
import os
import sys
import time

class DreamPicoPortConan(ConanFile):
    name = "dream_pico_port_api"
    version = "1.0.3"
    package_type = "library"
    license = "MIT"
    author = "James M Smith"
    url = "https://github.com/OrangeFox86/DreamPicoPort-API"
    description = "USB-host-side API for host-mode DreamPicoPort"
    topics = ["Maple Bus", "Sega", "Dreamcast", "retro", "gaming"]
    settings = ["os", "compiler", "build_type", "arch"]
    options = {
        "shared": [True, False],
        "fPIC": [True, False],
        "tests": [True, False],
        "with_libusb": [True, False]
    }
    default_options = {
        "shared": False,
        "libusb/*:shared": False,
        "fPIC": True,
        "tests": False,
        "with_libusb": False
    }
    exports_sources = [
        "CMakeLists.txt",
        "src/*",
        "test/*"
    ]

    def requirements(self):
        if self.options.get_safe("with_libusb", True):
            self.requires("libusb/[>=1.0.26 <2.0.0]")

    def config_options(self):
        if self.settings.os == "Windows":
            self.options.rm_safe("fPIC")
        else:
            # libusb is required for all other OSes
            self.options.rm_safe("with_libusb")

    def configure(self):
        if self.options.get_safe("shared"):
            self.options.rm_safe("fPIC")

    def generate(self):
        # This generates "conan_toolchain.cmake" in self.generators_folder
        tc = CMakeToolchain(self)

        tc.variables["DREAMPICOPORT_API_BUILD_SHARED_LIBS"] = bool(self.options.get_safe("shared", False))
        tc.variables["DREAMPICOPORT_TESTS"] = bool(self.options.get_safe("tests", False))

        if self.options.get_safe("with_libusb", True):
            tc.variables["DREAMPICOPORT_WITH_LIBUSB"] = True
            tc.variables["DREAMPICOPORT_USE_EXTERNAL_LIBUSB"] = True
            tc.variables["DREAMPICOPORT_EXTERNAL_LIBUSB_PROJECT_NAME"] = "libusb"
            tc.variables["DREAMPICOPORT_LIBUSB_LIBRARIES"] = "libusb::libusb"
        else:
            tc.variables["DREAMPICOPORT_WITH_LIBUSB"] = False

        tc.generate()

        # This generates "foo-config.cmake" and "bar-config.cmake" in self.generators_folder
        deps = CMakeDeps(self)
        deps.generate()

    def build(self):
        if self.options.get_safe("with_libusb", True) and self.settings.os == "Windows":
            print("***\n*** WARNING: using libusb from conancenter is currently problematic for Windows builds\n***", file=sys.stderr)
            time.sleep(3)
        cmake = CMake(self)
        cmake.configure(cli_args=["--no-warn-unused-cli"])
        cmake.build()

    def package(self):
        cmake = CMake(self)
        cmake.configure(cli_args=["--no-warn-unused-cli"])
        cmake.install()

    def package_info(self):
        self.cpp_info.set_property("cmake_find_mode", "none")
        self.cpp_info.builddirs.append("cmake")

    def deploy(self):
        conan_copy(self, "*", src=os.path.join(self.package_folder, "bin"), dst=os.path.join(self.deploy_folder, "bin"))
        conan_copy(self, "*.so*", src=os.path.join(self.package_folder, "lib"), dst=os.path.join(self.deploy_folder, "lib"))
        conan_copy(self, "*.dll", src=os.path.join(self.package_folder, "bin"), dst=os.path.join(self.deploy_folder, "bin"))
        # .a and .lib files not are not needed for deployment
        #conan_copy(self, "*.a*", src=os.path.join(self.package_folder, "lib"), dst=os.path.join(self.deploy_folder, "lib"))
        #conan_copy(self, "*.lib*", src=os.path.join(self.package_folder, "lib"), dst=os.path.join(self.deploy_folder, "lib"))
