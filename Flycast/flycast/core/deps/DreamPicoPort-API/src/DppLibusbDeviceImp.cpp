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

#ifndef DREAMPICOPORT_NO_LIBUSB

#include "DppLibusbDeviceImp.hpp"

#include <libusb.h>

#include <cstdint>
#include <cstdlib>
#include <vector>
#include <thread>
#include <mutex>
#include <functional>
#include <algorithm>

namespace dpp_api
{

LibusbDeviceList::LibusbDeviceList() : mCount(0), mLibusbDeviceList() {}

LibusbDeviceList::LibusbDeviceList(const std::unique_ptr<libusb_context, LibusbContextDeleter>& libusbContext) : LibusbDeviceList()
{
    generate(libusbContext);
}

void LibusbDeviceList::generate(const std::unique_ptr<libusb_context, LibusbContextDeleter>& libusbContext)
{
    libusb_device **devs;
    ssize_t cnt = libusb_get_device_list(libusbContext.get(), &devs);
    if (cnt >= 0)
    {
        mLibusbDeviceList.reset(devs);
        mCount = static_cast<std::size_t>(cnt);
    }
    else
    {
        mCount = 0;
        mLibusbDeviceList.reset();
    }
}

std::size_t LibusbDeviceList::size() const
{
    return mCount;
}

bool LibusbDeviceList::empty() const
{
    return (mCount == 0);
}

libusb_device* LibusbDeviceList::operator[](std::size_t index) const
{
    if (index >= mCount)
    {
        return nullptr;
    }
    return mLibusbDeviceList.get()[index];
}

LibusbDeviceList::iterator LibusbDeviceList::begin() const
{
    return iterator(mLibusbDeviceList.get(), 0);
}

LibusbDeviceList::iterator LibusbDeviceList::end() const
{
    return iterator(mLibusbDeviceList.get(), mCount);
}

std::unique_ptr<libusb_context, LibusbContextDeleter> make_libusb_context()
{
    std::unique_ptr<libusb_context, LibusbContextDeleter> libusbContext;

    {
        libusb_context *ctx = nullptr;
        int r = libusb_init(&ctx);
        if (r < 0)
        {
            return nullptr;
        }
        libusbContext.reset(ctx);
    }
    return libusbContext;
}

//! @return a new unique_pointer to a libusb_device_handle
std::unique_ptr<libusb_device_handle, LibusbDeviceHandleDeleter> make_libusb_device_handle(libusb_device* dev)
{
    std::unique_ptr<libusb_device_handle, LibusbDeviceHandleDeleter> deviceHandle;

    {
        libusb_device_handle *handle;
        int r = libusb_open(dev, &handle);
        if (r >= 0)
        {
            deviceHandle.reset(handle);
        }
    }

    return deviceHandle;
}

void LibusbError::saveError(int libusbError, const char* where)
{
    std::lock_guard<std::mutex> lock(mMutex);
    mLastLibusbError = libusbError;
    mWhere = where;
}

void LibusbError::saveErrorIfNotSet(int libusbError, const char* where)
{
    std::lock_guard<std::mutex> lock(mMutex);
    if (mLastLibusbError == LIBUSB_SUCCESS)
    {
        mLastLibusbError = libusbError;
        mWhere = where;
    }
}

void LibusbError::clearError()
{
    std::lock_guard<std::mutex> lock(mMutex);
    mLastLibusbError = LIBUSB_SUCCESS;
    mWhere = nullptr;
}

std::string LibusbError::getErrorDesc() const
{
    int libusbError = 0;
    const char* where = nullptr;

    {
        std::lock_guard<std::mutex> lock(mMutex);
        libusbError = mLastLibusbError;
        where = mWhere;
    }

    const char* libusbErrorStr = getLibusbErrorStr(libusbError);

    if (where && *where != '\0')
    {
        std::string errStr(libusbErrorStr);
        if (!errStr.empty())
        {
            errStr += " @ ";
        }
        return errStr + where;
    }

    return std::string(libusbErrorStr);
}

const char* LibusbError::getLibusbErrorStr(int libusbError)
{
    switch (libusbError)
    {
        case LIBUSB_SUCCESS: return "";
        case LIBUSB_ERROR_IO: return "Input/Output error";
        case LIBUSB_ERROR_INVALID_PARAM: return "Invalid parameter (internal fault)";
#ifdef __linux__
        case LIBUSB_ERROR_ACCESS: return "Access denied (check permissions or udev rules)";
#else
        case LIBUSB_ERROR_ACCESS: return "Access denied";
#endif
        case LIBUSB_ERROR_NO_DEVICE: return "Device not found or disconnected";
        case LIBUSB_ERROR_NOT_FOUND: return "Device, interface, or endpoint not found";
        case LIBUSB_ERROR_BUSY: return "Device is busy";
        case LIBUSB_ERROR_TIMEOUT: return "Timeout occurred";
        case LIBUSB_ERROR_OVERFLOW: return "Overflow occurred";
        case LIBUSB_ERROR_PIPE: return "Pipe error";
        case LIBUSB_ERROR_INTERRUPTED: return "Operation was interrupted";
        case LIBUSB_ERROR_NO_MEM: return "Insufficient memory";
        case LIBUSB_ERROR_NOT_SUPPORTED: return "Operation not supported or unimplemented on this platform";
        case LIBUSB_ERROR_OTHER: return "Undefined error";
        case LIBUSB_ERROR_OTHER - 1: return ""; // Error external to this component
        default:
            return libusb_error_name(libusbError);
    }
}

//! Holds a previously found entry
struct KnownEntry
{
    //! The previously returned device handle
    std::weak_ptr<libusb_device_handle> devHandle;
    //! Matching filter data (idx should be ignored)
    DppDevice::Filter matchingFilter;
};

//! List of previously returned items on find_dpp_device
static std::list<KnownEntry> gPrevReturnedItems;

FindResult find_dpp_device(
    const std::unique_ptr<libusb_context, LibusbContextDeleter>& libusbContext,
    const DppDevice::Filter& filter
)
{
    LibusbDeviceList deviceList(libusbContext);
    std::unique_ptr<libusb_device_descriptor> desc = std::make_unique<libusb_device_descriptor>();
    std::int32_t currentIndex = 0;

    for (libusb_device* dev : deviceList)
    {
        int r = libusb_get_device_descriptor(dev, desc.get());
        if (r < 0)
        {
            continue;
        }

        if (desc->idVendor != filter.idVendor || desc->idProduct != filter.idProduct)
        {
            continue;
        }

        if (desc->bcdDevice < filter.minBcdDevice || desc->bcdDevice > filter.maxBcdDevice)
        {
            continue;
        }

        std::unique_ptr<libusb_device_handle, LibusbDeviceHandleDeleter> deviceHandle = make_libusb_device_handle(dev);
        if (!deviceHandle)
        {
            continue;
        }

        std::string deviceSerial;
        unsigned char serialString[256] = {};
        if (desc->iSerialNumber > 0)
        {
            r = libusb_get_string_descriptor_ascii(
                deviceHandle.get(),
                desc->iSerialNumber,
                serialString,
                sizeof(serialString)
            );

            if (r >= 0)
            {
                deviceSerial.assign(reinterpret_cast<char*>(serialString));
                if (filter.serial.empty() || deviceSerial == filter.serial)
                {
                    if (filter.idx < 0 || filter.idx == currentIndex)
                    {
                        return FindResult{
                            std::move(desc),
                            std::shared_ptr<libusb_device_handle>(deviceHandle.release(), LibusbDeviceHandleDeleter{}),
                            std::move(deviceSerial),
                            currentIndex + 1
                        };
                    }
                    else
                    {
                        ++currentIndex;
                    }
                }
            }
        }
    }

    return FindResult{
        nullptr,
        nullptr,
        std::string(),
        currentIndex
    };
}

DppLibusbDeviceImp::DppLibusbDeviceImp(
    const std::string& serial,
    std::unique_ptr<libusb_device_descriptor>&& desc,
    std::unique_ptr<libusb_context, LibusbContextDeleter>&& libusbContext,
    std::shared_ptr<libusb_device_handle>&& libusbDeviceHandle
) :
    mSerial(serial),
    mDesc(std::move(desc)),
    mLibusbContext(std::move(libusbContext)),
    mLibusbDeviceHandle(std::move(libusbDeviceHandle))
{
}

DppLibusbDeviceImp::~DppLibusbDeviceImp()
{
    // Ensure disconnection
    disconnect();

    // Reset libusb pointers in the correct order
    if (!clearTransfers())
    {
        // This will likely cause an exception, but there is nothing else that can be done
        mTransferDataMap.clear();
    }
    mLibusbDeviceHandle.reset();
    mLibusbContext.reset();
}

const std::string& DppLibusbDeviceImp::getSerial() const
{
    return mSerial;
}

bool DppLibusbDeviceImp::openInterface()
{
    if (mInterfaceClaimed)
    {
        return true;
    }

    mLastLibusbError.clearError();

    if (mPreviouslyConnected || !mLibusbDeviceHandle)
    {
        // Reset and attempt to reconnect
        mLibusbDeviceHandle.reset();

        DppDevice::Filter filter;
        filter.idVendor = mDesc->idVendor;
        filter.idProduct = mDesc->idProduct;
        filter.minBcdDevice = mDesc->bcdDevice;
        filter.maxBcdDevice = mDesc->bcdDevice;
        filter.serial = mSerial;
        FindResult foundDevice = find_dpp_device(mLibusbContext, filter);
        if (!foundDevice.desc || !foundDevice.devHandle)
        {
            mLastLibusbError.saveError(LIBUSB_ERROR_NO_DEVICE, "find_dpp_device");
            return false;
        }

        mDesc = std::move(foundDevice.desc);
        mLibusbDeviceHandle = std::move(foundDevice.devHandle);
    }

    mPreviouslyConnected = true;

    // Dynamically retrieve endpoint addresses for the interface
    std::unique_ptr<libusb_config_descriptor, LibusbConfigDescriptorDeleter> configDescriptor;

    {
        libusb_config_descriptor *config;
        int r = libusb_get_active_config_descriptor(libusb_get_device(mLibusbDeviceHandle.get()), &config);
        if (r < 0)
        {
            mLastLibusbError.saveError(r, "libusb_get_active_config_descriptor");
            return false;
        }
        configDescriptor.reset(config);
    }

    const libusb_interface *selectedInterface = nullptr;
    for (std::uint8_t i = 0; i < configDescriptor->bNumInterfaces; ++i)
    {
        // Select the vendor spec interface with the minimum interface number
        const libusb_interface *itf = &configDescriptor->interface[i];
        if (itf->num_altsetting > 0 && itf->altsetting[0].bInterfaceClass == LIBUSB_CLASS_VENDOR_SPEC)
        {
            if (
                !selectedInterface ||
                itf->altsetting->bInterfaceNumber < selectedInterface->altsetting->bInterfaceNumber
            )
            {
                selectedInterface = itf;
            }
        }
    }

    if (!selectedInterface || selectedInterface->num_altsetting <= 0)
    {
        mLastLibusbError.saveError(LIBUSB_ERROR_NOT_FOUND, "find vendor interface");
        return false;
    }

    std::int16_t outEndpoint = -1;
    std::int16_t inEndpoint = -1;

    const libusb_interface_descriptor *altsetting = &selectedInterface->altsetting[0];
    for (int i = 0; i < altsetting->bNumEndpoints; i++)
    {
        const libusb_endpoint_descriptor *endpoint = &altsetting->endpoint[i];
        if ((endpoint->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK)
        {
            if (endpoint->bEndpointAddress & LIBUSB_ENDPOINT_IN)
            {
                inEndpoint = endpoint->bEndpointAddress;
            }
            else
            {
                outEndpoint = endpoint->bEndpointAddress;
            }
        }
    }

    if (outEndpoint < 0 || inEndpoint < 0)
    {
        mLastLibusbError.saveError(LIBUSB_ERROR_NOT_FOUND, "find endpoints");
        return false;
    }

    mInterfaceNumber = selectedInterface->altsetting->bInterfaceNumber;
    mEpOut = static_cast<std::uint8_t>(outEndpoint);
    mEpIn = static_cast<std::uint8_t>(inEndpoint);
    configDescriptor.reset();

    int r = libusb_claim_interface(mLibusbDeviceHandle.get(), mInterfaceNumber);
    if (r < 0)
    {
        // Handle error - interface claim failed
        mLastLibusbError.saveError(r, "libusb_claim_interface");
        return false;
    }

    // Set up control transfer for connect message (clears buffers)
    r = libusb_control_transfer(
        mLibusbDeviceHandle.get(),
        LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE | LIBUSB_ENDPOINT_OUT,
        0x22, // bRequest
        0x01, // wValue (connection)
        mInterfaceNumber, // wIndex
        nullptr, // data buffer
        0,    // wLength
        1000  // timeout in milliseconds
    );

    if (r < 0)
    {
        // Handle control transfer error
        libusb_release_interface(mLibusbDeviceHandle.get(), mInterfaceNumber);
        mLastLibusbError.saveError(r, "libusb_control_transfer on connect");
        return false;
    }

    mInterfaceClaimed = true;
    return true;
}

bool DppLibusbDeviceImp::send(std::uint8_t* data, int length, unsigned int timeoutMs)
{
    if (!mLibusbDeviceHandle)
    {
        return false;
    }

    // Transfer the package
    int transferred;
    int r = libusb_bulk_transfer(
        mLibusbDeviceHandle.get(),
        mEpOut,
        data,
        length,
        &transferred,
        timeoutMs
    );

    if (r < 0)
    {
        mLastLibusbError.saveError(r, "libusb_bulk_transfer on send");
        return false;
    }
    else if (transferred != length)
    {
        mLastLibusbError.saveError(LIBUSB_ERROR_IO, "libusb_bulk_transfer - all data not sent");
        return false;
    }

    return true;
}

void LIBUSB_CALL DppLibusbDeviceImp::onLibusbTransferComplete(libusb_transfer *transfer)
{
    DppLibusbDeviceImp* dev = static_cast<DppLibusbDeviceImp*>(transfer->user_data);
    dev->transferComplete(transfer);
}

void DppLibusbDeviceImp::transferComplete(libusb_transfer* transfer)
{
    if (transfer->status == LIBUSB_TRANSFER_COMPLETED && transfer->actual_length > 0)
    {
        handleReceive(transfer->buffer, transfer->actual_length);
        transfer->actual_length = 0;
    }

    bool stallDetected = mRxStalled;
    bool allowNewTransfer = false;
    bool noDevice = false;

    if (mInterfaceClaimed && !mExitRequested)
    {
        switch (transfer->status)
        {
            case LIBUSB_TRANSFER_COMPLETED:
            {
                allowNewTransfer = true;
            }
            break;

            case LIBUSB_TRANSFER_TIMED_OUT:
            {
                // retry
                allowNewTransfer = true;
            }
            break;

            case LIBUSB_TRANSFER_STALL:
            {
                mLastLibusbError.saveErrorIfNotSet(LIBUSB_ERROR_IO, "transfer in - stall or disconnected");
                allowNewTransfer = false;
                // Set stallDetected which will prevent device from closing unless other errors occur
                stallDetected = true;
            }
            break;

            case LIBUSB_TRANSFER_ERROR:
            {
                mLastLibusbError.saveErrorIfNotSet(LIBUSB_ERROR_IO, "transfer in - error");
                allowNewTransfer = false;
            }
            break;

            case LIBUSB_TRANSFER_CANCELLED:
            {
                mLastLibusbError.saveErrorIfNotSet(LIBUSB_ERROR_IO, "transfer in - cancelled");
                allowNewTransfer = false;
            }
            break;

            case LIBUSB_TRANSFER_NO_DEVICE:
            {
                mLastLibusbError.saveErrorIfNotSet(LIBUSB_ERROR_IO, "transfer in - disconnected");
                allowNewTransfer = false;
                noDevice = true;
            }
            break;

            case LIBUSB_TRANSFER_OVERFLOW:
            {
                mLastLibusbError.saveErrorIfNotSet(LIBUSB_ERROR_IO, "transfer in - overflow");
                allowNewTransfer = false;
            }
            break;

            default:
            {
                mLastLibusbError.saveErrorIfNotSet(LIBUSB_ERROR_IO, "transfer in - unknown error");
                allowNewTransfer = false;
            }
            break;
        }
    }
    else
    {
        allowNewTransfer = false;
    }

    bool transferSubmitted = false;

    if (allowNewTransfer)
    {
        // Submit new transfer
        int r = libusb_submit_transfer(transfer);
        if (r < 0)
        {
            // Failure
            mLastLibusbError.saveError(r, "libusb_submit_transfer on transfer");
        }
        else
        {
            transferSubmitted = true;
        }
    }

    if (!transferSubmitted)
    {
        std::lock_guard<std::recursive_mutex> lock(mTransferDataMapMutex);

        // Erase the transfer from the map which should automatically free the transfer data
        std::size_t n = mTransferDataMap.erase(transfer);

        if (noDevice)
        {
            // Don't try to recover from stall if there is no device
            mRxStalled = false;
            stallDetected = false;
        }

        if (stallDetected)
        {
            if (!mRxStalled)
            {
                // Only cancel all other transfers without completely stopping read
                mRxStalled = true;
                cancelTransfers();
            }
        }
        else
        {
            // Cancel all other transfers
            stopRead();
        }
    }
}

bool DppLibusbDeviceImp::createTransfers()
{
    bool success = true;

    for (std::uint32_t i = 0; i < kNumTransfers; ++i)
    {
        std::unique_ptr<TransferData> transferData;

        {
            libusb_transfer *transfer = libusb_alloc_transfer(0);
            if (!transfer)
            {
                mLastLibusbError.saveError(LIBUSB_ERROR_NO_MEM, "libusb_alloc_transfer");
                success = false;
                break;
            }
            transferData = std::make_unique<TransferData>();
            transferData->transfer.reset(transfer);
        }

        transferData->buffer.resize(kRxSize);

        libusb_fill_bulk_transfer(
            transferData->transfer.get(),
            mLibusbDeviceHandle.get(),
            mEpIn,
            &transferData->buffer[0],
            transferData->buffer.size(),
            DppLibusbDeviceImp::onLibusbTransferComplete,
            this,
            0
        );

        {
            std::lock_guard<std::recursive_mutex> lock(mTransferDataMapMutex);

            int r = libusb_submit_transfer(transferData->transfer.get());
            if (r < 0)
            {
                mLastLibusbError.saveError(r, "libusb_submit_transfer");
                success = false;
                break;
            }

            mTransferDataMap.insert(std::make_pair(transferData->transfer.get(), std::move(transferData)));
        }
    }

    if (!success)
    {
        // This will block until all transfers are cleared by the libusb state machine
        clearTransfers();
    }

    return success;
}

DppDeviceImp::ReadInitResult DppLibusbDeviceImp::readInit()
{
    if (!openInterface())
    {
        return ReadInitResult::kFailure;
    }

    // Ensure there are no hanging transfers left in the libusb state machine
    if (!clearTransfers())
    {
        return ReadInitResult::kFailure;
    }

    // Create all new transfers
    if (!createTransfers())
    {
        return ReadInitResult::kFailure;
    }

    mExitRequested = false;
    mRxStalled = false;

    // Ready!
    return ReadInitResult::kSuccessRunLoop;
}

void DppLibusbDeviceImp::readLoop()
{
    while (mInterfaceClaimed && !mExitRequested)
    {
        if (mRxStalled && mTransferDataMap.empty())
        {
            if (!mLibusbDeviceHandle)
            {
                mLastLibusbError.saveErrorIfNotSet(LIBUSB_ERROR_IO, "Device handle freed");
                mExitRequested = true;
                break;
            }

            int r = libusb_clear_halt(mLibusbDeviceHandle.get(), mEpIn);
            if (r < 0)
            {
                mLastLibusbError.saveError(r, "libusb_clear_halt");
                mExitRequested = true;
                break;
            }

            if (!createTransfers())
            {
                mExitRequested = true;
                break;
            }
        }

        int r = libusb_handle_events(mLibusbContext.get());
        if (r < 0)
        {
            mLastLibusbError.saveError(r, "libusb_handle_events");
            mExitRequested = true;
            break;
        }
    }

    // This will block until all transfers are cleared by the libusb state machine
    clearTransfers();
}

void DppLibusbDeviceImp::stopRead()
{
    std::lock_guard<std::recursive_mutex> lock(mTransferDataMapMutex);

    // Flag the thread to exit
    mExitRequested = true;

    // Cancel any transfers in progress in order to wake read thread
    cancelTransfers();
}

void DppLibusbDeviceImp::cancelTransfers()
{
    std::lock_guard<std::recursive_mutex> lock(mTransferDataMapMutex);

    for (auto& pair : mTransferDataMap)
    {
        libusb_cancel_transfer(pair.second->transfer.get());
    }
}

bool DppLibusbDeviceImp::clearTransfers()
{
    cancelTransfers();

    // Need to process until transfers are fully canceled
    while (!mTransferDataMap.empty())
    {
        int r = libusb_handle_events(mLibusbContext.get());
        if (r < 0)
        {
            mLastLibusbError.saveErrorIfNotSet(r, "libusb_handle_events while trying to clear transfers");
            return false;
        }
    }
    return true;
}

bool DppLibusbDeviceImp::closeInterface()
{
    stopRead();
    bool result = true;

    if (mInterfaceClaimed)
    {
        mInterfaceClaimed = false;

        if (mLibusbDeviceHandle)
        {
            // Set up control transfer for disconnect message (clears buffers)
            libusb_control_transfer(
                mLibusbDeviceHandle.get(),
                LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE | LIBUSB_ENDPOINT_OUT,
                0x22, // bRequest
                0x00, // wValue (disconnection)
                mInterfaceNumber, // wIndex
                nullptr, // data buffer
                0,    // wLength
                1000  // timeout in milliseconds
            );

            int r = libusb_release_interface(mLibusbDeviceHandle.get(), mInterfaceNumber);
            if (r < 0)
            {
                mLastLibusbError.saveError(r, "libusb_release_interface");
                result = false;
            }
        }
    }

    return result;
}

std::string DppLibusbDeviceImp::getLastErrorStr() const
{
    return mLastLibusbError.getErrorDesc();
}

bool DppLibusbDeviceImp::isConnected()
{
    return mInterfaceClaimed;
}

std::array<std::uint8_t, 3> DppLibusbDeviceImp::getVersion() const
{
    std::array<std::uint8_t, 3> version;
    std::uint16_t bcdVer = mDesc->bcdDevice;
    version[0] = (bcdVer >> 8) & 0xFF;
    version[1] = (bcdVer >> 4) & 0x0F;
    version[2] = (bcdVer) & 0x0F;
    return version;
}

void DppLibusbDeviceImp::setExternalError(const char* where)
{
    mLastLibusbError.saveErrorIfNotSet(LIBUSB_ERROR_OTHER - 1, where);
}

int DppLibusbDeviceImp::getInterfaceNumber() const
{
    return mInterfaceNumber;
}

std::uint8_t DppLibusbDeviceImp::getEpIn() const
{
    return mEpIn;
}

std::uint8_t DppLibusbDeviceImp::getEpOut() const
{
    return mEpOut;
}

std::unique_ptr<DppLibusbDeviceImp> DppLibusbDeviceImp::find(const DppDevice::Filter& filter)
{
    std::unique_ptr<libusb_context, LibusbContextDeleter> libusbContext = make_libusb_context();

    FindResult foundDevice = find_dpp_device(libusbContext, filter);
    if (!foundDevice.desc || !foundDevice.devHandle)
    {
        return nullptr;
    }

    return std::make_unique<DppLibusbDeviceImp>(
        foundDevice.serial,
        std::move(foundDevice.desc),
        std::move(libusbContext),
        std::move(foundDevice.devHandle)
    );
}

std::uint32_t DppLibusbDeviceImp::getCount(const DppDevice::Filter& filter)
{
    std::unique_ptr<libusb_context, LibusbContextDeleter> libusbContext = make_libusb_context();

    DppDevice::Filter filterCpy = filter;
    filterCpy.idx = (std::numeric_limits<std::int32_t>::max)();
    FindResult foundDevice = find_dpp_device(libusbContext, filterCpy);

    return foundDevice.count;
}

} // namespace dpp_api

#endif // DREAMPICOPORT_NO_LIBUSB
