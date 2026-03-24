#ifndef __DREAM_PICO_PORT_LIBUSB_DEVICE_IMP_HPP__
#define __DREAM_PICO_PORT_LIBUSB_DEVICE_IMP_HPP__

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

#include <libusb.h>

#include "DreamPicoPortApi.hpp"
#include "DppDeviceImp.hpp"

#include <cstdint>
#include <cstdlib>
#include <vector>
#include <thread>
#include <mutex>
#include <functional>
#include <algorithm>

namespace dpp_api
{

//
// libusb deleters
//

//! Deleter for unique_pointer of a libusb_context
struct LibusbContextDeleter
{
    inline void operator()(libusb_context* p) const
    {
        if (p)
        {
            libusb_exit(p);
        }
    }
};

//! Deleter for unique_pointer of a libusb_device_handle
struct LibusbDeviceHandleDeleter
{
    inline void operator()(libusb_device_handle* handle) const
    {
        if (handle)
        {
            libusb_close(handle);
        }
    }
};

//! Deleter for unique_pointer of a libusb_device*
struct LibusbDeviceListDeleter
{
    inline void operator()(libusb_device** devs) const
    {
        if (devs)
        {
            libusb_free_device_list(devs, 1);
        }
    }
};

//! Deleter for unique_pointer of a libusb_config_descriptor
struct LibusbConfigDescriptorDeleter
{
    inline void operator()(libusb_config_descriptor* config) const
    {
        if (config)
        {
            libusb_free_config_descriptor(config);
        }
    }
};

//! Deleter for unique_pointer of a libusb_transfer
struct LibusbTransferDeleter
{
    inline void operator()(libusb_transfer* transfer) const
    {
        if (transfer)
        {
            libusb_free_transfer(transfer);
        }
    }
};

//
// C++ libusb wrappers
//

//! Holds libusb device list
class LibusbDeviceList
{
public:
    LibusbDeviceList();

    LibusbDeviceList(const std::unique_ptr<libusb_context, LibusbContextDeleter>& libusbContext);

    void generate(const std::unique_ptr<libusb_context, LibusbContextDeleter>& libusbContext);

    std::size_t size() const;

    bool empty() const;

    libusb_device* operator[](std::size_t index) const;

    // Iterator support
    class iterator
    {
    public:
        inline iterator(libusb_device** devices, std::size_t index) : mDevices(devices), mIndex(index) {}

        inline libusb_device* operator*() const { return mDevices ? mDevices[mIndex] : nullptr; }
        inline iterator& operator++() { ++mIndex; return *this; }
        inline iterator operator++(int) { iterator tmp = *this; ++mIndex; return tmp; }
        inline bool operator==(const iterator& other) const
        {
            return mDevices == other.mDevices && mIndex == other.mIndex;
        }
        inline bool operator!=(const iterator& other) const
        {
            return mDevices != other.mDevices || mIndex != other.mIndex;
        }

    private:
        libusb_device** mDevices;
        std::size_t mIndex;
    };

    iterator begin() const;

    iterator end() const;

private:
    std::size_t mCount;
    std::unique_ptr<libusb_device*, LibusbDeviceListDeleter> mLibusbDeviceList;
};

//! @return a new unique_pointer to a libusb_context
std::unique_ptr<libusb_context, LibusbContextDeleter> make_libusb_context();

//! @return a new unique_pointer to a libusb_device_handle
std::unique_ptr<libusb_device_handle, LibusbDeviceHandleDeleter> make_libusb_device_handle(libusb_device* dev);

//! Holds libusb error and where it occurred locally
class LibusbError
{
public:
    LibusbError() = default;
    virtual ~LibusbError() = default;

    //! Copy constructor
    //! @param[in] rhs The right-hand-side object to copy from
    inline LibusbError(const LibusbError& rhs) :
        mLastLibusbError(rhs.mLastLibusbError),
        mWhere(rhs.mWhere),
        mMutex()
    {}

    //! Save the error data
    //! @param[in] libusbError The libusb error number
    //! @param[in] where Where the error ocurred
    void saveError(int libusbError, const char* where);

    //! Save error only if no error is already set
    //! @param[in] libusbError The libusb error number
    //! @param[in] where Where the error ocurred
    void saveErrorIfNotSet(int libusbError, const char* where);

    //! Clear all error data
    void clearError();

    //! @return error description
    std::string getErrorDesc() const;

    //! @return description of the last experienced error
    static const char* getLibusbErrorStr(int libusbError);

private:
    //! libusb error number
    int mLastLibusbError = LIBUSB_SUCCESS;
    //! Holds a static string where the error ocurred
    const char* mWhere = nullptr;
    //! Mutex which serializes access to above data
    mutable std::mutex mMutex;
};

struct FindResult
{
    std::unique_ptr<libusb_device_descriptor> desc;
    // This is essentially unique, but also retained as a weak_ptr locally for comparison logic only
    std::shared_ptr<libusb_device_handle> devHandle;
    std::string serial;
    std::int32_t count;
};

FindResult find_dpp_device(
    const std::unique_ptr<libusb_context, LibusbContextDeleter>& libusbContext,
    const DppDevice::Filter& filter
);

//! libusb implementation of DppDevice
class DppLibusbDeviceImp : public DppDeviceImp
{
public:
    //! Contains transfer data
    struct TransferData
    {
        //! Pointer to the underlying transfer data
        std::unique_ptr<libusb_transfer, LibusbTransferDeleter> transfer;
        //! Buffer which the transfer points into
        std::vector<std::uint8_t> buffer;
    };

    //! Constructor
    //! @param[in] serial Serial number of this device
    //! @param[in] desc The device descriptor of this device
    //! @param[in] libusbContext The context of libusb
    //! @param[in] libusbDeviceHandle Handle to the device
    DppLibusbDeviceImp(
        const std::string& serial,
        std::unique_ptr<libusb_device_descriptor>&& desc,
        std::unique_ptr<libusb_context, LibusbContextDeleter>&& libusbContext,
        std::shared_ptr<libusb_device_handle>&& libusbDeviceHandle
    );

    //! Destructor
    ~DppLibusbDeviceImp();

    //! Opens the vendor interface of the DreamPicoPort
    //! @return true if interface was successfully claimed or was already claimed
    bool openInterface();

    //! Sends data on the vendor interface
    //! @param[in] data Buffer to send
    //! @param[in] length Number of bytes in \p data
    //! @param[in] timeoutMs Send timeout in milliseconds
    //! @return true if data was successfully sent
    bool send(std::uint8_t* data, int length, unsigned int timeoutMs = 1000) override;

    //! Initialize for subsequent run
    //! @return true if interface was open or opened and transfers ready for run
    ReadInitResult readInit() override;

    //! Starts the asynchronous interface and blocks until disconnect
    void readLoop() override;

    //! Request stop of the read thread
    void stopRead() override;

    //! Closes the interface
    //! @return true if interface was closed or was already closed
    bool closeInterface() override;

    //! @return description of the last experienced error
    std::string getLastErrorStr() const override;

    //! @return true iff the interface is currently claimed
    bool isConnected();

    //! @return the serial of this device
    const std::string& getSerial() const override;

    //! @return USB version number {major, minor, patch}
    std::array<std::uint8_t, 3> getVersion() const override;

    //! Set an error which occurs externally
    //! @param[in] where Explanation of where the error occurred
    void setExternalError(const char* where) override;

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
    static std::unique_ptr<DppLibusbDeviceImp> find(const DppDevice::Filter& filter);

    //! @param[in] filter The filter parameters (idx is ignored)
    //! @return the number of DreamPicoPort devices
    static std::uint32_t getCount(const DppDevice::Filter& filter);

private:
    //! Forward declaration of transfer complete callback
    //! @param[in] transfer The transfer which completed
    static void LIBUSB_CALL onLibusbTransferComplete(libusb_transfer *transfer);

    //! Called when a libusb read transfer completed
    //! @param[in] transfer The transfer that completed
    void transferComplete(libusb_transfer* transfer);

    //! Create all libusb transfers
    //! @return true iff all transfers were created
    bool createTransfers();

    //! Cancel all transfers
    void cancelTransfers();

    //! Cancel all transfers then do processing loop until all transfers have been deleted
    //! @return true if all transfers were successfully cleared
    //! @return false if an error occurred
    bool clearTransfers();

public:
    //! The serial number of this device
    const std::string mSerial;

private:
    //! The size in bytes of each libusb transfer
    static const std::size_t kRxSize = 1100;
    //! The number of libusb transfers to create
    static const std::uint32_t kNumTransfers = 5;
    //! The device descriptor of this device
    std::unique_ptr<libusb_device_descriptor> mDesc;
    //! Pointer to the libusb context
    std::unique_ptr<libusb_context, LibusbContextDeleter> mLibusbContext;
    //! Maps transfer pointers to TransferData
    std::unordered_map<libusb_transfer*, std::unique_ptr<TransferData>> mTransferDataMap;
    //! Serializes access to mTransferDataMap
    std::recursive_mutex mTransferDataMapMutex;
    //! Pointer to the libusb device handle
    std::shared_ptr<libusb_device_handle> mLibusbDeviceHandle;
    //! True when interface is claimed
    bool mInterfaceClaimed = false;
    //! Set to true when read thread starts, set to false to cause read thread to exit
    bool mExitRequested = false;
    //! Set when RX experienced a STALL and automatic recovery should be attempted
    bool mRxStalled = false;
    //! The interface number of the WinUSB (vendor) interface
    int mInterfaceNumber = 7;
    //! The IN endpoint of mInterfaceNumber where bulk data is read
    std::uint8_t mEpIn = 0;
    //! The IN endpoint of mInterfaceNumber where bulk data is written
    std::uint8_t mEpOut = 0;
    //! Contains last libusb error data
    LibusbError mLastLibusbError;
    //! Set to true on first connection in order to force reset on subsequent connection
    bool mPreviouslyConnected = false;

}; // class LibusbDevice

} // namespace dpp_api

#endif // DREAMPICOPORT_NO_LIBUSB

#endif // __DREAM_PICO_PORT_LIBUSB_DEVICE_IMP_HPP__
