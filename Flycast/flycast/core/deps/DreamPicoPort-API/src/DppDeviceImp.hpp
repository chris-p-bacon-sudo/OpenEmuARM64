#ifndef __DREAM_PICO_PORT_DEVICE_IMP_HPP__
#define __DREAM_PICO_PORT_DEVICE_IMP_HPP__

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

#include <string>
#include <list>
#include <vector>
#include <cstdint>
#include <functional>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <map>
#include <thread>

namespace dpp_api
{

//! Base class for specific DPP implementation
class DppDeviceImp
{
public:
    //! Constructor
    DppDeviceImp() = default;

    //! Virtual destructor
    //! @note the child should call disconnect() within its destructor
    virtual ~DppDeviceImp() = default;

    //! Connect to the device and start operation threads. If already connected, disconnect before reconnecting.
    //! @param[in] fn When true is returned, this is the function that will execute when the device is disconnected
    //!               errStr: the reason for disconnection or empty string if disconnect() was called
    //!               NOTICE: Any attempt to call connect() within any callback function will always fail
    //! @return false on failure and getLastErrorStr() will return error description
    //! @return true if connection succeeded
    bool connect(const std::function<void(std::string& errStr)>& fn);

    //! Disconnect from the previously connected device and stop all threads
    //! @return false on failure and getLastErrorStr() will return error description
    //! @return true if disconnection succeeded or was already disconnected
    bool disconnect();

    //! @return true iff currently connected
    bool isConnected();

    //! Send a raw command to DreamPicoPort
    //! @param[in] cmd Raw DreamPicoPort command
    //! @param[in] payload The payload for the command
    //! @param[in] respFn The function to call on received response, timeout, or disconnect with the following arguments
    //!                   cmd: one of the kCmd* values
    //!                   payload: the returned payload
    //!                   NOTICE: Any attempt to call connect() within any callback function will always fail
    //! @param[in] timeoutMs Duration to wait before timeout
    //! @return 0 if send failed and getLastErrorStr() will return error description
    //! @return the ID of the sent data
    std::uint64_t send(
        std::uint8_t cmd,
        const std::vector<std::uint8_t>& payload,
        const std::function<void(std::int16_t cmd, std::vector<std::uint8_t>& payload)>& respFn,
        std::uint32_t timeoutMs
    );

    //! Sets the maximum return address value used to tag each command
    //! @note the minimum maximum is 0x0FFFFFFF to ensure proper execution
    //! @param[in] maxAddr The maximum address value to set
    static inline void setMaxAddr(std::uint64_t maxAddr)
    {
        mMaxAddr = (std::max)(maxAddr, static_cast<std::uint64_t>(0x0FFFFFFF));
    }

    //! @return the serial of this device
    virtual const std::string& getSerial() const = 0;

    //! @return USB version number {major, minor, patch}
    virtual std::array<std::uint8_t, 3> getVersion() const = 0;

    //! @return string representation of last error
    virtual std::string getLastErrorStr() const = 0;

    //! @return number of waiting responses
    std::size_t getNumWaiting();

    //! Set an error which occurs externally
    //! @param[in] where Explanation of where the error occurred
    virtual void setExternalError(const char* where) = 0;

    //! Retrieve the currently connected interface number (first VENDOR interface)
    //! @return the connected interface number
    virtual int getInterfaceNumber() const = 0;

    //! @return the currently used IN endpoint
    virtual std::uint8_t getEpIn() const = 0;

    //! @return the currently used OUT endpoint
    virtual std::uint8_t getEpOut() const = 0;

    //! Converts 2 bytes in network order to a uint16 value in host order
    //! @param[in] payload Pointer to the beginning of the 2-byte sequence
    //! @return the converted uint16 value
    static inline std::uint16_t bytesToUint16(const void* payload)
    {
        const std::uint8_t* p8 = reinterpret_cast<const std::uint8_t*>(payload);
        return (static_cast<std::uint16_t>(p8[0]) << 8 | p8[1]);
    }

    //! Converts a uint16 value from host order int a byte buffer in network order
    //! @param[out] out The buffer to write the next 2 bytes to
    //! @param[in] data The uint16 value to convert
    static inline void uint16ToBytes(void* out, std::uint16_t data)
    {
        std::uint8_t* p8 = reinterpret_cast<std::uint8_t*>(out);
        *p8++ = data >> 8;
        *p8 = data & 0xFF;
    }

    //! Converts 4 bytes in network order to a uint16 value in host order
    //! @param[in] payload Pointer to the beginning of the 4-byte sequence
    //! @return the converted uint32 value
    static inline std::uint32_t bytesToUint32(const void* payload)
    {
        const std::uint8_t* p8 = reinterpret_cast<const std::uint8_t*>(payload);
        return (
            static_cast<std::uint32_t>(p8[0]) << 24 |
            static_cast<std::uint32_t>(p8[1]) << 16 |
            static_cast<std::uint32_t>(p8[2]) << 8 |
            p8[3]
        );
    }

    //! Converts a uint32 value from host order int a byte buffer in network order
    //! @param[out] out The buffer to write the next 4 bytes to
    //! @param[in] data The uint32 value to convert
    static inline void uint32ToBytes(void* out, std::uint32_t data)
    {
        std::uint8_t* p8 = reinterpret_cast<std::uint8_t*>(out);
        *p8++ = (data >> 24) & 0xFF;
        *p8++ = (data >> 16) & 0xFF;
        *p8++ = (data >> 8) & 0xFF;
        *p8 = data & 0xFF;
    }

    //! Compute CRC16 over a buffer using a seed value
    //! @param[in] seed The seed value to start with
    //! @param[in] buffer Pointer to byte array
    //! @param[in] bufLen Number of bytes to read from buffer
    //! @return CRC16 value
    static inline std::uint16_t computeCrc16(std::uint16_t seed, const void* buffer, std::uint16_t bufLen)
    {
        std::uint16_t crc = seed;
        const std::uint8_t* b8 = reinterpret_cast<const std::uint8_t*>(buffer);

        for (std::uint16_t i = 0; i < bufLen; ++i)
        {
            crc ^= static_cast<uint8_t>(*b8++) << 8;
            for (int j = 0; j < 8; ++j)
            {
                if (crc & 0x8000)
                {
                    crc = (crc << 1) ^ 0x1021;
                }
                else
                {
                    crc <<= 1;
                }
            }
        }

        return crc;
    }

    //! Compute CRC16 over a buffer
    //! @param[in] buffer Pointer to byte array
    //! @param[in] bufLen Number of bytes to read from buffer
    //! @return CRC16 value
    static inline std::uint16_t computeCrc16(const void* buffer, std::uint16_t bufLen)
    {
        return computeCrc16(0xFFFFU, buffer, bufLen);
    }

protected:
    //! Return result for readInit()
    enum class ReadInitResult
    {
        //! Failed to initialize, cannot continue
        kFailure = 0,
        //! Read initialization was successful, readLoop() should be called
        kSuccessRunLoop,
        //! Read initialization was successful and currently running asynchronously
        kSuccessAsync,
    };

    //! Initialize for subsequent read
    //! @return true if interface was open or opened and transfers ready for read loop
    virtual ReadInitResult readInit() = 0;

    //! Executes the read loop, blocking until disconnect
    virtual void readLoop();

    //! Signal the read loop to stop (non-blocking)
    virtual void stopRead() = 0;

    //! Signal the processing thread to stop
    void stopProcessing();

    //! Close the USB interface
    //! @return true iff interface was closed
    virtual bool closeInterface() = 0;

    //! Sends data on the vendor interface
    //! @param[in] data Buffer to send
    //! @param[in] length Number of bytes in \p data
    //! @param[in] timeoutMs Send timeout in milliseconds
    //! @return true if data was successfully sent
    virtual bool send(std::uint8_t* data, int length, unsigned int timeoutMs = 1000) = 0;

    //! Packs a packet structure into a vector
    //! @param[in] addr The return address
    //! @param[in] cmd The command to set
    //! @param[in] payload The payload for the command
    //! @return the packed data
    static std::vector<std::uint8_t> pack(
        std::uint64_t addr,
        std::uint8_t cmd,
        const std::vector<std::uint8_t>& payload
    );

    //! Handle received data
    //! @param[in] buffer Buffer received from libusb
    //! @param[in] len Number of bytes in buffer received
    void handleReceive(const std::uint8_t* buffer, int len);

    //! The entrypoint for mProcessThread
    //! All callbacks are executed from this context
    void processEntrypoint();

private:
    //! The magic sequence which starts each packet
    static constexpr const std::uint8_t kMagicSequence[] = {0xDB, 0x8B, 0xAF, 0xD5};
    //! The number of bytes in the magic sequence
    static constexpr const std::int8_t kSizeMagic = sizeof(kMagicSequence);
    //! The number of packet size bytes (2 for size and 2 for inverse size)
    static constexpr const std::int8_t kSizeSize = 4;
    //! Minimum number of bytes used for return address in packet
    static constexpr const std::int8_t kMinSizeAddress = 1;
    //! Maximum number of bytes used for return address in packet
    static constexpr const std::int8_t kMaxSizeAddress = 9;
    //! The number of bytes used for command in packet
    static constexpr const std::int8_t kSizeCommand = 1;
    //! The number of bytes used for CRC at the end of the packet
    static constexpr const std::int8_t kSizeCrc = 2;
    //! Minimum number of bytes of a packet
    static constexpr const std::int8_t kMinPacketSize =
        kSizeMagic + kSizeSize + kMinSizeAddress + kSizeCommand + kSizeCrc;

    //! The minimum value for mNextAddr
    static const std::uint64_t kMinAddr = 1;
    //! The maximum value for mNextAddr
    static std::uint64_t mMaxAddr;

    //! Holds received bytes not yet parsed into a packet
    std::vector<std::uint8_t> mReceiveBuffer;

    //! The map entry for callback lookup
    struct FunctionLookupMapEntry
    {
        //! The callback to use when this message is received
        std::function<void(std::int16_t cmd, std::vector<std::uint8_t>& payload)> callback;
        //! Iterator into the timeout map which should be removed once the message is received
        std::multimap<std::chrono::system_clock::time_point, std::uint64_t>::iterator timeoutMapIter;
    };

    //! The map type which links return address to FunctionLookupMapEntry
    using FunctionLookupMap = std::unordered_map<std::uint64_t, FunctionLookupMapEntry>;

    //! True when connected, false when disconnected
    bool mConnected = false;
    //! The callback to execute when processing thread is exiting
    std::function<void(std::string& errStr)> mDisconnectCallback;
    //! The error reason for disconnection
    std::string mDisconnectReason;
    //! Serializes access to mDisconnectCallback and mDisconnectReason
    std::mutex mDisconnectMutex;
    //! True while processing thread should execute
    bool mProcessing = false;
    //! Maps return address to FunctionLookupMapEntry
    FunctionLookupMap mFnLookup;
    //! This is used to organize chronologically the timeout values for each key in the above mFnLookup
    std::multimap<std::chrono::system_clock::time_point, std::uint64_t> mTimeoutLookup;
    //! Condition variable signaled when data is added to one of the lookups, waited on within mProcessThread
    std::condition_variable mProcessCv;
    //! Mutex used to serialize access to mFnLookup, mTimeoutLookup, and mProcessCv
    std::mutex mProcessMutex;
    //! Next available return address
    std::uint64_t mNextAddr = kMinAddr;
    //! Mutex serializing access to mNextAddr
    std::mutex mNextAddrMutex;
    //! The read thread created on connect()
    std::unique_ptr<std::thread> mReadThread;
    //! Thread which executes send, receive callback execution, and response timeout callback execution
    std::unique_ptr<std::thread> mProcessThread;
    //! Mutex used to serialize connect() and disconnect() calls
    std::recursive_mutex mConnectionMutex;

    //! Outgoing data structure
    struct OutgoingData
    {
        //! Address embedded in the packet
        std::uint64_t addr = 0;
        //! Packet to send
        std::vector<std::uint8_t> packet;
    };

    //! Holds data not yet sent
    std::list<OutgoingData> mOutgoingData;

    //! Holds incoming parsed packet data
    struct IncomingData
    {
        std::uint64_t addr = 0;
        std::uint8_t cmd = 0;
        std::vector<std::uint8_t> payload;
    };

    //! Holds data to be passed to processing callbacks
    std::list<IncomingData> mIncomingPackets;
};

}

#endif // __DREAM_PICO_PORT_DEVICE_IMP_HPP__
