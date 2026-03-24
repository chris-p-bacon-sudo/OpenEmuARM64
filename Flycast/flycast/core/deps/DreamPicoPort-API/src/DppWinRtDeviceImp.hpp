#ifndef __DREAM_PICO_PORT_WIN_RT_DEVICE_IMP_HPP__
#define __DREAM_PICO_PORT_WIN_RT_DEVICE_IMP_HPP__

// MIT License
//
// Copyright (c) 2025 James Smith of OrangeFox86
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include "DppDeviceImp.hpp"
#include "DreamPicoPortApi.hpp"

#include <atomic>
#include <mutex>
#include <condition_variable>

#include <winrt/base.h>
#include <winrt/Windows.Devices.Usb.h>

namespace dpp_api
{

//! Base class for specific DPP implementation
class DppWinRtDeviceImp : public DppDeviceImp
{
public:
    //! Constructor
    DppWinRtDeviceImp(
        const std::string& serial,
        std::uint32_t bcdVer,
        const std::string& containerId
    );

    //! Virtual destructor
    ~DppWinRtDeviceImp();

    //! Opens the vendor interface of the DreamPicoPort
    //! @return true if interface was successfully claimed or was already claimed
    bool openInterface();

    //! @return the serial of this device
    const std::string& getSerial() const override;

    //! @return USB version number {major, minor, patch}
    std::array<std::uint8_t, 3> getVersion() const override;

    //! @return string representation of last error
    std::string getLastErrorStr() const override;

    //! Set an error which occurs externally
    //! @param[in] where Explanation of where the error occurred
    void setExternalError(const char* where) override;

    //! Set an internal error message
    //! @param[in] where Explanation of where the error occurred
    void setError(const char* where);

    //! Retrieve the currently connected interface number (first VENDOR interface)
    //! @return the connected interface number
    int getInterfaceNumber() const override;

    //! @return the currently used IN endpoint
    std::uint8_t getEpIn() const override;

    //! @return the currently used OUT endpoint
    std::uint8_t getEpOut() const override;

    //! Find a device
    //! @param[in] filter The filter parameters
    //! @return pointer to the located device if found
    //! @return nullptr otherwise
    static std::unique_ptr<DppWinRtDeviceImp> find(const DppDevice::Filter& filter);

    //! @param[in] filter The filter parameters (idx is ignored)
    //! @return the number of DreamPicoPort devices
    static std::uint32_t getCount(const DppDevice::Filter& filter);

private:
    //! Initialize for subsequent read
    //! @return true if interface was open or opened and transfers ready for read loop
    ReadInitResult readInit() override;

    //! Signal the read loop to stop (non-blocking)
    void stopRead() override;

    //! Close the USB interface
    //! @return true iff interface was closed
    bool closeInterface() override;

    //! Sends data on the vendor interface
    //! @param[in] data Buffer to send
    //! @param[in] length Number of bytes in \p data
    //! @param[in] timeoutMs Send timeout in milliseconds
    //! @return true if data was successfully sent
    bool send(std::uint8_t* data, int length, unsigned int timeoutMs = 1000) override;

    void nextTransferIn();

    //! Called when a transfer in has completed
    //! @param[in] sender Transfered data
    //! @param[in] status Status of the transfer
    void transferInComplete(
        const winrt::Windows::Foundation::IAsyncOperationWithProgress<winrt::Windows::Storage::Streams::IBuffer,uint32_t>& sender,
        winrt::Windows::Foundation::AsyncStatus status
    );

private:
    //! The size in bytes of each libusb transfer
    static const std::size_t kRxSize = 1100;

    const std::string mSerial;
    std::array<std::uint8_t, 3> mVersion{0,0,0};
    std::string mLastError;
    mutable std::mutex mLastErrorMutex;
    int mInterfaceNumber = -1;
    winrt::hstring mDeviceInterfacePath;
    std::uint8_t mEpIn = 0xFF;
    winrt::Windows::Devices::Usb::UsbBulkInPipe mEpInPipe = nullptr;
    std::uint8_t mEpOut = 0xFF;
    winrt::Windows::Devices::Usb::UsbBulkOutPipe mEpOutPipe = nullptr;

    winrt::Windows::Storage::Streams::Buffer mReadBuffer = winrt::Windows::Storage::Streams::Buffer(kRxSize);

    winrt::Windows::Devices::Usb::UsbDevice mDevice = nullptr;

    winrt::Windows::Foundation::IAsyncOperationWithProgress<
        winrt::Windows::Storage::Streams::IBuffer,
        uint32_t
    > mReadOperation = nullptr;

    std::mutex mReadMutex;
    bool mReading = false;
};

}

#endif // __DREAM_PICO_PORT_WIN_RT_DEVICE_IMP_HPP__
