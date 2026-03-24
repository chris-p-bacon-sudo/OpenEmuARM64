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

#if defined(_WIN32) && defined(DREAMPICOPORT_NO_LIBUSB)

#include "DppWinRtDeviceImp.hpp"

#include <future>
#include <chrono>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Usb.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Storage.Streams.h>

using namespace winrt;
using namespace winrt::Windows::Devices::Enumeration;
using namespace winrt::Windows::Foundation::Collections;
using namespace winrt::Windows::Devices::Usb;
using namespace winrt::Windows::Storage;

#define DPP_INTERFACE_CLASS_FILTER_STR L"System.Devices.InterfaceClassGuid:=\"{31C4F7D3-1AF2-4AD0-B461-3A760CBBD4FB}\""

namespace dpp_api {

static std::wstring make_vid_pid_str(std::uint16_t vid, std::uint16_t pid)
{
    std::wstring vidPidStr = L"VID_";

    // Convert idVendor to 4-digit hex string
    wchar_t vendorHex[5];
    swprintf_s(vendorHex, L"%04X", vid);
    vidPidStr += vendorHex;

    vidPidStr += L"&PID_";

    // Convert idProduct to 4-digit hex string
    wchar_t productHex[5];
    swprintf_s(productHex, L"%04X", pid);
    vidPidStr += productHex;

    return vidPidStr;
}

static winrt::hstring make_selector(const DppDevice::Filter& filter)
{
    // The interface GUID is set on the DreamPicoPort
    std::wstring deviceSelector =
        L"System.Devices.InterfaceEnabled:=System.StructuredQueryType.Boolean#True"
        L" AND " DPP_INTERFACE_CLASS_FILTER_STR
        L" AND System.Devices.DeviceInstanceId:~<\"USB\\" +
        make_vid_pid_str(filter.idVendor, filter.idProduct) +
        L"\"";

    return winrt::hstring(deviceSelector);
}

//! Safely retrieves the result of an winrt async get()
//! @tparam T The result type to be retrieved
//! @param[in] getFn A function which both creates an async operation and calls get()
//! @param[in] defaultVal The default value to return on exception
//! @return The retrieved value
template <typename T>
static T winrt_async_get(const std::function<T()>& getFn, const T& defaultVal)
{
    try
    {
        // Synopsis:
        // winrt uses the UI message pump when current thread is UI thread. This will usually mean that the asynchronous
        // operation will rely on messaging. Blocking while on this thread would then cause a deadlock because messages
        // won't be handled. To avoid that particular case, the async operation will be executed in its own thread so
        // winrt-internal operations don't rely on the message pump.
        if (winrt::impl::is_sta_thread())
        {
            std::future<T> task = std::async(std::launch::async, getFn);
            return task.get();
        }
        else
        {
            return getFn();
        }
    }
    catch(const winrt::hresult_error& e)
    {
        // Execution error occurred
        return defaultVal;
    }
}

//! Safely retrieves the result of an winrt async get(), returning nullptr on exception
//! @tparam T The result type to be retrieved
//! @param[in] getFn A function which both creates an async operation and calls get()
//! @return The retrieved value
template <typename T>
static T winrt_async_get(const std::function<T()>& getFn)
{
    return winrt_async_get<T>(getFn, nullptr);
}

template <typename T>
struct winrt_handle_async_data
{
    //! The function which generates a IAsyncOperation<T>
    std::function<winrt::Windows::Foundation::IAsyncOperation<T>()> asyncFn;
    //! Duration to wait before timeout (statusOut will be set to Canceled on timeout)
    winrt::Windows::Foundation::TimeSpan timeout = std::chrono::milliseconds(5000);
};

//! Safely handles a winrt async operation, blocking until complete and returning the result
//! @tparam T The result type to be retrieved
//! @param[out] statusOut The status of the operation
//! @param[in] data Async transfer data
//! @param[in] defaultVal The default value to return on exception
//! @return the resulting value of the operation or nullptr if operation fails
template <typename T>
static T winrt_handle_async(
    winrt::Windows::Foundation::AsyncStatus& statusOut,
    const winrt_handle_async_data<T>& data,
    const T& defaultVal
)
{
    statusOut = winrt::Windows::Foundation::AsyncStatus::Started;
    return winrt_async_get<T>(
        [&]() -> T
        {
            winrt::Windows::Foundation::IAsyncOperation<T> asyncOp;
            try
            {
                asyncOp = data.asyncFn();
                statusOut = asyncOp.wait_for(data.timeout);
                if (statusOut != winrt::Windows::Foundation::AsyncStatus::Completed)
                {
                    statusOut = winrt::Windows::Foundation::AsyncStatus::Canceled;
                    asyncOp.Cancel();
                    asyncOp.get();
                    return defaultVal;
                }
                return asyncOp.get();

            }
            catch(const winrt::hresult_error& e)
            {
                // Execution error occurred
                statusOut = winrt::Windows::Foundation::AsyncStatus::Error;
                if (asyncOp)
                {
                    asyncOp.Cancel();
                    asyncOp.get();
                }
                return defaultVal;
            }
        },
        defaultVal
    );
}

//! Safely handles a winrt async operation, blocking until complete and returning the result
//! @tparam T The result type to be retrieved
//! @param[out] statusOut The status of the operation
//! @param[in] data Async transfer data
//! @return the resulting value of the operation or nullptr if operation fails
template <typename T>
static T winrt_handle_async(
    winrt::Windows::Foundation::AsyncStatus& statusOut,
    const winrt_handle_async_data<T>& data
)
{
    return winrt_handle_async<T>(statusOut, data, nullptr);
}

//! Executes a control transfer OUT, blocking until complete, timeout, or error
//! @param[in] dev winrt UsbDevice to execute the control transfer on
//! @param[in] setupPacket Control transfer header data
//! @param[in] dat The data to send
//! @return a libusb error code
static bool winrt_send_control_transfer_out(
    winrt::Windows::Devices::Usb::UsbDevice& dev,
    const UsbSetupPacket& setupPacket,
    winrt::array_view<uint8_t> dat = {}
)
{
    if (!dev)
    {
        return false;
    }

    if (setupPacket.RequestType().Direction() != UsbTransferDirection::Out)
    {
        return false;
    }

    winrt::Windows::Foundation::AsyncStatus status;
    auto dataWriter = Streams::DataWriter();
    dataWriter.WriteBytes(dat);
    auto inputBuffer = dataWriter.DetachBuffer();
    winrt_handle_async_data<uint32_t> outData{
        [&]() { return dev.SendControlOutTransferAsync(setupPacket, inputBuffer); }
    };

    uint32_t result = winrt_handle_async<uint32_t>(
        status,
        outData,
        0
    );

    if (status == winrt::Windows::Foundation::AsyncStatus::Canceled)
    {
        return false;
    }
    else if (status != winrt::Windows::Foundation::AsyncStatus::Completed || result < dat.size())
    {
        return false;
    }

    return true;
}

DppWinRtDeviceImp::DppWinRtDeviceImp(
    const std::string& serial,
    std::uint32_t bcdVer,
    const std::string& containerId
) :
    mSerial(serial)
{
    // Save version number
    mVersion[0] = (bcdVer >> 8) & 0xFF;
    mVersion[1] = (bcdVer >> 4) & 0x0F;
    mVersion[2] = (bcdVer) & 0x0F;

    std::wstring wContainerId(containerId.begin(), containerId.end());
    std::wstring deviceSelector = L"System.Devices.ContainerId:=\"";
    deviceSelector += wContainerId;
    deviceSelector +=
        L"\" AND System.Devices.InterfaceEnabled:=System.StructuredQueryType.Boolean#True"
        L" AND " DPP_INTERFACE_CLASS_FILTER_STR;
    IVector<winrt::hstring> additionalProperties = winrt::single_threaded_vector<winrt::hstring>();
    additionalProperties.Append(L"System.Devices.DeviceInstanceId");
    auto deviceInfos = winrt_async_get<DeviceInformationCollection>(
        [&]()
        {
            return DeviceInformation::FindAllAsync(
                deviceSelector,
                additionalProperties,
                DeviceInformationKind::DeviceInterface
            ).get();
        }
    );

    // Extract the interface ID
    if (deviceInfos.Size() > 0)
    {
        const DeviceInformation& devInfo = deviceInfos.GetAt(0);
        mDeviceInterfacePath = devInfo.Id();
    }
}

DppWinRtDeviceImp::~DppWinRtDeviceImp()
{
    // Ensure disconnection
    disconnect();
}

bool DppWinRtDeviceImp::openInterface()
{
    if (mDeviceInterfacePath.empty())
    {
        setError("openInterface() failed - no device interface path found");
        return false;
    }

    mDevice = winrt_async_get<UsbDevice>(
        [&]()
        {
            return UsbDevice::FromIdAsync(mDeviceInterfacePath).get();
        }
    );

    if (!mDevice)
    {
        setError("openInterface() failed - failed to open interface (already in use?)");
        return false;
    }

    // Get the first configuration
    auto configuration = mDevice.Configuration();
    if (!configuration)
    {
        setError("openInterface() failed - failed to get device configuration");
        return false;
    }

    // Get the first interface on this device
    UsbInterface targetInterface = nullptr;
    if (configuration.UsbInterfaces().Size() <= 0)
    {
        setError("No interfaces available");
        mDevice = nullptr;
        setError("openInterface() failed - no interfaces found on device");
        return false;
    }
    targetInterface = configuration.UsbInterfaces().GetAt(0);

    // Save the interface number
    mInterfaceNumber = targetInterface.InterfaceNumber();

    // Find the bulk endpoints
    mEpIn = 0;
    for (auto pipe : targetInterface.BulkInPipes())
    {
        if (mEpIn == 0)
        {
            mEpIn = pipe.EndpointDescriptor().EndpointNumber();
            pipe.ReadOptions(pipe.ReadOptions() | UsbReadOptions::AutoClearStall);
            mEpInPipe = pipe;
            break;
        }
    }

    mEpOut = 0;
    for (auto pipe : targetInterface.BulkOutPipes())
    {
        if (mEpOut == 0)
        {
            mEpOut = pipe.EndpointDescriptor().EndpointNumber();
            pipe.WriteOptions(pipe.WriteOptions() | UsbWriteOptions::AutoClearStall);
            mEpOutPipe = pipe;
            break;
        }
    }

    // Ensure we found both endpoints
    if (mEpIn == 0)
    {
        setError("openInterface() failed - could not find IN endpoint");
        return false;
    }
    else if (mEpOut == 0)
    {
        setError("openInterface() failed - could not find OUT endpoint");
        return false;
    }

    // Set up control transfer for connect message (clears buffers)
    UsbSetupPacket setupPacket;
    setupPacket.RequestType().Direction(UsbTransferDirection::Out);
    setupPacket.RequestType().ControlTransferType(UsbControlTransferType::Class);
    setupPacket.RequestType().Recipient(UsbControlRecipient::SpecifiedInterface);
    setupPacket.Request(0x22);
    setupPacket.Value(0x01);
    setupPacket.Index(mInterfaceNumber);
    setupPacket.Length(0);

    if (!winrt_send_control_transfer_out(mDevice, setupPacket))
    {
        setError("openInterface() failed - failed to send initial control transfer for connection");
        return false;
    }

    return true;
}

const std::string& DppWinRtDeviceImp::getSerial() const
{
    return mSerial;
}

std::array<std::uint8_t, 3> DppWinRtDeviceImp::getVersion() const
{
    return mVersion;
}

std::string DppWinRtDeviceImp::getLastErrorStr() const
{
    std::lock_guard<std::mutex> lock(mLastErrorMutex);
    return mLastError;
}

void DppWinRtDeviceImp::setExternalError(const char* where)
{
    std::lock_guard<std::mutex> lock(mLastErrorMutex);
    mLastError = (where ? where : "");
}

void DppWinRtDeviceImp::setError(const char* where)
{
    setExternalError(where);
}

int DppWinRtDeviceImp::getInterfaceNumber() const
{
    return mInterfaceNumber;
}

std::uint8_t DppWinRtDeviceImp::getEpIn() const
{
    return mEpIn;
}

std::uint8_t DppWinRtDeviceImp::getEpOut() const
{
    return mEpOut;
}

struct FindResult
{
    std::uint32_t bcdVer;
    std::string serial;
    std::string containerId;
    std::uint32_t count;
};

FindResult find_dpp_device(const DppDevice::Filter& filter)
{
    hstring deviceSelector = make_selector(filter);
    // Find all matching devices
    auto additionalProperties = winrt::single_threaded_vector<winrt::hstring>();
    additionalProperties.Append(L"System.Devices.ContainerId");
    auto deviceInfos = winrt_async_get<DeviceInformationCollection>(
        [&]()
        {
            return DeviceInformation::FindAllAsync(
                deviceSelector,
                additionalProperties,
                DeviceInformationKind::DeviceInterface
            ).get();
        }
    );

    std::uint32_t count = 0;
    for (const auto& devInfo : deviceInfos)
    {
        UsbDevice dev = winrt_async_get<UsbDevice>(
            [&]()
            {
                return UsbDevice::FromIdAsync(devInfo.Id()).get();
            }
        );

        if (!dev)
        {
            // Likely already in use
            continue;
        }

        UsbDeviceDescriptor desc = dev.DeviceDescriptor();
        guid containerGuid;
        devInfo.Properties().Lookup(L"System.Devices.ContainerId").as(containerGuid);
        hstring containerId;
        containerId = winrt::to_hstring(containerGuid);
        std::wstring containerIdWStr(containerId);

        if (desc.BcdDeviceRevision() >= filter.minBcdDevice && desc.BcdDeviceRevision() <= filter.maxBcdDevice)
        {
            std::wstring rootSelector =
                L"System.Devices.InterfaceEnabled:=System.StructuredQueryType.Boolean#True"
                L" AND System.Devices.DeviceInstanceId:~<\"USB\\" +
                make_vid_pid_str(filter.idVendor, filter.idProduct) +
                L"\\\" AND System.Devices.ContainerId:=\"" + containerIdWStr +
                L"\"";

            auto additionalRootProperties = winrt::single_threaded_vector<winrt::hstring>();
            additionalRootProperties.Append(L"System.Devices.DeviceInstanceId");
            auto rootDevInfos = winrt_async_get<DeviceInformationCollection>(
                [&]()
                {
                    return DeviceInformation::FindAllAsync(rootSelector, additionalRootProperties).get();
                }
            );

            bool match = false;
            std::string serial;

            if (rootDevInfos.Size() > 0)
            {
                winrt::hstring instId;
                rootDevInfos.GetAt(0).Properties().Lookup(L"System.Devices.DeviceInstanceId").as(instId);
                std::wstring instIdWStr(instId);

                // Extract serial number from device instance ID
                size_t backslashPos = instIdWStr.find_last_of(L'\\');
                if (backslashPos != std::wstring::npos && backslashPos + 1 < instIdWStr.length())
                {
                    std::wstring serialWide = instIdWStr.substr(backslashPos + 1);
                    serial = winrt::to_string(serialWide);
                    if (filter.serial.empty() || serial == filter.serial)
                    {
                        match = true;
                    }
                }
            }

            if (match)
            {
                if (filter.idx == count++)
                {
                    std::string containerIdStr = winrt::to_string(containerIdWStr);
                    return FindResult{desc.BcdDeviceRevision(), serial, containerIdStr, count};
                }
            }
        }
    }

    return FindResult{0, std::string(), std::string(), count};
}

std::unique_ptr<DppWinRtDeviceImp> DppWinRtDeviceImp::find(const DppDevice::Filter& filter)
{
    FindResult findResult = find_dpp_device(filter);
    if (!findResult.containerId.empty())
    {
        return std::make_unique<DppWinRtDeviceImp>(
            findResult.serial,
            findResult.bcdVer,
            findResult.containerId
        );
    }

    return nullptr;
}

std::uint32_t DppWinRtDeviceImp::getCount(const DppDevice::Filter& filter)
{
    DppDevice::Filter filterCpy = filter;
    filterCpy.idx = (std::numeric_limits<std::int32_t>::max)();
    FindResult findResult = find_dpp_device(filterCpy);

    return findResult.count;
}

DppDeviceImp::ReadInitResult DppWinRtDeviceImp::readInit()
{
    if (!openInterface())
    {
        return ReadInitResult::kFailure;
    }

    std::lock_guard<std::mutex> lock(mReadMutex);
    mReading = true;

    nextTransferIn();

    return ReadInitResult::kSuccessAsync;
}

void DppWinRtDeviceImp::stopRead()
{
    std::lock_guard<std::mutex> lock(mReadMutex);
    if (mReadOperation)
    {
        mReadOperation.Cancel();
    }
    mReading = false;
}

bool DppWinRtDeviceImp::closeInterface()
{
    stopRead();
    if (mDevice)
    {
        // Set up control transfer for disconnect message (clears buffers)
        UsbSetupPacket setupPacket;
        setupPacket.RequestType().Direction(UsbTransferDirection::Out);
        setupPacket.RequestType().ControlTransferType(UsbControlTransferType::Class);
        setupPacket.RequestType().Recipient(UsbControlRecipient::SpecifiedInterface);
        setupPacket.Request(0x22);
        setupPacket.Value(0x00);
        setupPacket.Index(mInterfaceNumber);
        setupPacket.Length(0);

        if (!winrt_send_control_transfer_out(mDevice, setupPacket))
        {
            setError("closeInterface() failed - failed to send control transfer for disconnection");
        }
    }
    mEpInPipe = nullptr;
    mEpOutPipe = nullptr;
    mDevice = nullptr;
    return true;
}

bool DppWinRtDeviceImp::send(std::uint8_t* data, int length, unsigned int timeoutMs)
{
    winrt::Windows::Storage::Streams::Buffer writeBuf(length);
    writeBuf.Length(length);
    memcpy(writeBuf.data(), data, length);
    Windows::Foundation::IAsyncOperationWithProgress<uint32_t, uint32_t> writeOp = nullptr;
    try
    {
        writeOp = mEpOutPipe.OutputStream().WriteAsync(writeBuf);
    }
    catch (const winrt::hresult_error&)
    {
        return false;
    }

    return winrt_async_get<bool>(
        [&]()
        {
            auto status = writeOp.wait_for(std::chrono::milliseconds(timeoutMs));
            if (status != Windows::Foundation::AsyncStatus::Completed)
            {
                writeOp.Cancel();
                writeOp.get();
                setError("Write failed");
                return false;
            }
            return true;
        }
    );
}

void DppWinRtDeviceImp::nextTransferIn()
{
    mReadBuffer.Length(0);
    mReadOperation = mEpInPipe.InputStream().ReadAsync(
        mReadBuffer,
        kRxSize,
        Streams::InputStreamOptions::Partial | Streams::InputStreamOptions::ReadAhead
    );
    mReadOperation.Completed(
        [this]
        (
            const winrt::Windows::Foundation::IAsyncOperationWithProgress<winrt::Windows::Storage::Streams::IBuffer,uint32_t>& sender,
            winrt::Windows::Foundation::AsyncStatus status
        )
        {
            transferInComplete(sender, status);
        }
    );
}

void DppWinRtDeviceImp::transferInComplete(
    const winrt::Windows::Foundation::IAsyncOperationWithProgress<winrt::Windows::Storage::Streams::IBuffer,uint32_t>& sender,
    winrt::Windows::Foundation::AsyncStatus status
)
{
    if (status == winrt::Windows::Foundation::AsyncStatus::Completed)
    {
        auto result = sender.get();
        handleReceive(result.data(), static_cast<int>(result.Length()));

        std::lock_guard<std::mutex> lock(mReadMutex);
        nextTransferIn();
    }
    else
    {
        {
            std::lock_guard<std::mutex> lock(mLastErrorMutex);
            if (mLastError.empty())
            {
                mLastError = "Read ";
                switch (status)
                {
                    case Windows::Foundation::AsyncStatus::Canceled: mLastError += "canceled"; break;
                    case Windows::Foundation::AsyncStatus::Error: mLastError += "error"; break;
                    default: mLastError += "failed"; break;
                }
            }
        }

        stopRead();
        stopProcessing();
    }
}

} // namespace dpp_api

#endif
