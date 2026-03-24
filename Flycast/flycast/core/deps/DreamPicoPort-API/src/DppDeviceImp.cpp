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

namespace dpp_api
{
// (essentially, 4 byte max for address length at 7 bits of data per byte)
std::uint64_t DppDeviceImp::mMaxAddr = 0x0FFFFFFF;

bool DppDeviceImp::connect(const std::function<void(std::string& errStr)>& fn)
{
    // This function may not be called from any thread context (would cause deadlock)
    {
        // (never lock mConnectionMutex while mProcessThreadMutex is locked)
        std::lock_guard<std::mutex> lock(mProcessMutex);
        if (
            (mProcessThread && mProcessThread->get_id() == std::this_thread::get_id()) ||
            (mReadThread && mReadThread->get_id() == std::this_thread::get_id())
        )
        {
            setExternalError("connect attempted within thread context");
            return false;
        }
    }

    std::lock_guard<std::recursive_mutex> lock(mConnectionMutex);

    // Because of the above checks, calling disconnect() here will ensure all threads are stopped and joined
    if (!disconnect())
    {
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(mDisconnectMutex);
        mDisconnectCallback = fn;
        mDisconnectReason.clear();
        mDisconnectReason.shrink_to_fit();
    }

    ReadInitResult readInitResult = readInit();
    if (readInitResult == ReadInitResult::kFailure)
    {
        return false;
    }

    std::lock_guard<std::mutex> threadLock(mProcessMutex);

    mProcessing = true;

    if (readInitResult == ReadInitResult::kSuccessRunLoop)
    {
        mReadThread = std::make_unique<std::thread>(
            [this]()
            {
                readLoop();

                // Save the error description at this point
                {
                    std::lock_guard<std::mutex> lock(mDisconnectMutex);
                    mDisconnectReason = getLastErrorStr();
                }

                // Ensure disconnection
                disconnect();
            }
        );
    }

    mProcessThread = std::make_unique<std::thread>(
        [this]()
        {
            processEntrypoint();
        }
    );

    mConnected = true;

    return true;
}

bool DppDeviceImp::disconnect()
{
    // Do not take mConnectionMutex while in thread context. Instead, simply stop processing without joining.
    {
        // (never lock mConnectionMutex while mProcessThreadMutex is locked)
        std::lock_guard<std::mutex> lock(mProcessMutex);
        bool isReadThread = (mReadThread && mReadThread->get_id() == std::this_thread::get_id());
        bool isProcessThread = (mProcessThread && mProcessThread->get_id() == std::this_thread::get_id());
        if (isReadThread || isProcessThread)
        {
            // Stop processing without joining
            stopRead();
            if (isReadThread)
            {
                mProcessing = false;
                mProcessCv.notify_all();
            }
            return true;
        }
    }

    std::lock_guard<std::recursive_mutex> lock(mConnectionMutex);

    if (!mConnected)
    {
        return true;
    }

    mConnected = false;

    // Calling this may cause a call to disconnect() from the read thread
    bool closed = closeInterface();

    if (mReadThread)
    {
        mReadThread->join();
    }

    if (mProcessThread)
    {
        mProcessThread->join();
    }

    // Delete the threads
    {
        std::lock_guard<std::mutex> lock(mProcessMutex);
        mReadThread.reset();
        mProcessThread.reset();
    }

    return closed;
}

bool DppDeviceImp::isConnected()
{
    return mConnected;
}

std::uint64_t DppDeviceImp::send(
    std::uint8_t cmd,
    const std::vector<std::uint8_t>& payload,
    const std::function<void(std::int16_t cmd, std::vector<std::uint8_t>& payload)>& respFn,
    std::uint32_t timeoutMs
)
{
    std::uint64_t addr = 0;

    {
        std::lock_guard<std::mutex> lock(mNextAddrMutex);

        if (mNextAddr < kMinAddr)
        {
            mNextAddr = kMinAddr;
        }

        addr = mNextAddr++;

        if (mNextAddr > mMaxAddr)
        {
            mNextAddr = kMinAddr;
        }
    }

    std::vector<std::uint8_t> packedData = pack(addr, cmd, payload);

    {
        std::lock_guard<std::mutex> lock(mProcessMutex);

        if (!mProcessing)
        {
            setExternalError("send called while disconnected");
            return 0;
        }

        if (respFn)
        {
            std::chrono::system_clock::time_point expiration =
                std::chrono::system_clock::now() + std::chrono::milliseconds(timeoutMs);

            FunctionLookupMapEntry entry;
            entry.callback = respFn;
            entry.timeoutMapIter = mTimeoutLookup.insert(std::make_pair(expiration, addr));

            mFnLookup[addr] = std::move(entry);
        }

        mOutgoingData.push_back({addr, std::move(packedData)});

        mProcessCv.notify_all();
    }

    return addr;
}

std::size_t DppDeviceImp::getNumWaiting()
{
    std::lock_guard<std::mutex> lock(mProcessMutex);
    // Size of both of these maps should be equal
    return (std::max)(mFnLookup.size(), mTimeoutLookup.size());
}

std::vector<std::uint8_t> DppDeviceImp::pack(
    std::uint64_t addr,
    std::uint8_t cmd,
    const std::vector<std::uint8_t>& payload
)
{
    // Create address bytes
    std::vector<std::uint8_t> addrBytes;
    addrBytes.reserve(kMaxSizeAddress);
    std::int8_t idx = 0;
    while (addr > 0 || idx == 0)
    {
        const uint8_t orMask = (idx < (kMaxSizeAddress - 1)) ? ((addr > 0x7F) ? 0x80 : 0x00) : 0x00;
        const uint8_t shift = (idx < (kMaxSizeAddress - 1)) ? 7 : 8;
        addrBytes.push_back(static_cast<std::uint8_t>(addr & 0xFF) | orMask);
        addr >>= shift;
        ++idx;
    }

    // Create size bytes
    const std::uint16_t size =
        static_cast<std::uint16_t>(addrBytes.size() + kSizeCommand + payload.size() + kSizeCrc);
    const std::uint16_t invSize = 0xFFFF ^ size;
    std::uint8_t sizeBytes[kSizeSize];
    uint16ToBytes(&sizeBytes[0], size);
    uint16ToBytes(&sizeBytes[2], invSize);

    // Pack the data
    std::vector<std::uint8_t> data;
    data.reserve(kSizeMagic + kSizeSize + addrBytes.size() + kSizeCommand + payload.size() + kSizeCrc);
    data.insert(data.end(), kMagicSequence, kMagicSequence + kSizeMagic);
    data.insert(data.end(), sizeBytes, sizeBytes + kSizeSize);
    data.insert(data.end(), addrBytes.begin(), addrBytes.end());
    data.push_back(cmd);
    data.insert(data.end(), payload.begin(), payload.end());
    const std::uint16_t crc = computeCrc16(&data[kSizeMagic + kSizeSize], data.size() - kSizeMagic - kSizeSize);
    std::uint8_t crcBytes[kSizeCrc];
    uint16ToBytes(crcBytes, crc);
    data.insert(data.end(), crcBytes, crcBytes + kSizeCrc);

    return data;
}

void DppDeviceImp::handleReceive(const std::uint8_t* buffer, int len)
{
    mReceiveBuffer.insert(mReceiveBuffer.end(), buffer, buffer + len);
    while (mReceiveBuffer.size() >= kMinPacketSize)
    {
        std::size_t magicStart = 0;
        std::size_t magicSize = 0;
        std::size_t idx = 0;
        std::size_t magicIdx = 0;
        while (idx < mReceiveBuffer.size() && magicSize < kSizeMagic)
        {
            if (kMagicSequence[magicIdx] == mReceiveBuffer[idx])
            {
                ++magicSize;
                ++magicIdx;
            }
            else
            {
                magicStart = idx + 1;
                magicSize = 0;
                magicIdx = 0;
            }

            ++idx;
        }

        if (magicStart > 0)
        {
            // Remove non-magic bytes
            mReceiveBuffer.erase(mReceiveBuffer.begin(), mReceiveBuffer.begin() + magicStart);
            if (mReceiveBuffer.size() < kMinPacketSize)
            {
                // Not large enough for a full packet
                return;
            }
        }

        std::uint16_t size = bytesToUint16(&mReceiveBuffer[kSizeMagic]);
        std::uint16_t sizeInv = bytesToUint16(&mReceiveBuffer[kSizeMagic + 2]);
        if ((size ^ sizeInv) != 0xFFFF || size < (kMinSizeAddress + kSizeCrc))
        {
            // Invalid size inverse, discard first byte and retry
            mReceiveBuffer.erase(mReceiveBuffer.begin(), mReceiveBuffer.begin() + 1);
            continue;
        }

        // Check if full payload is available
        if (mReceiveBuffer.size() < (kSizeMagic + kSizeSize + size))
        {
            // Wait for more data
            return;
        }

        // Check CRC
        std::size_t pktSize = kSizeMagic + kSizeSize + size;
        const std::uint16_t receivedCrc = bytesToUint16(&mReceiveBuffer[pktSize - kSizeCrc]);
        const std::uint16_t computedCrc =
            computeCrc16(&mReceiveBuffer[kSizeMagic + kSizeSize], size - kSizeCrc);

        if (receivedCrc != computedCrc)
        {
            // Invalid CRC, discard first byte and retry
            mReceiveBuffer.erase(mReceiveBuffer.begin(), mReceiveBuffer.begin() + 1);
            continue;
        }

        // Ready to fill the packet
        IncomingData packet;

        // Extract address (variable-length, 7 bits per byte, MSb=1 if more bytes follow)
        std::int8_t addrLen = 0;
        bool lastByteBreak = false;
        std::size_t maxAddrSize = mReceiveBuffer.size() - kSizeMagic - kSizeSize - kSizeCrc;
        if (maxAddrSize > static_cast<std::size_t>(kMaxSizeAddress))
        {
            maxAddrSize = static_cast<std::size_t>(kMaxSizeAddress);
        }
        for (
            std::int8_t i = 0;
            static_cast<std::size_t>(i) < maxAddrSize;
            ++i
        ) {
            const std::uint8_t mask = (i < (kMaxSizeAddress - 1)) ? 0x7f : 0xff;
            const std::uint8_t thisByte = mReceiveBuffer[kSizeMagic + kSizeSize + i];
            packet.addr |= (thisByte & mask) << (7 * i);
            ++addrLen;
            if ((thisByte & 0x80) == 0)
            {
                lastByteBreak = true;
                break;
            }
        }
        if (mReceiveBuffer.size() <= (kSizeMagic + kSizeSize + addrLen + kSizeCrc))
        {
            // Missing command byte, discard first byte and retry
            mReceiveBuffer.erase(mReceiveBuffer.begin(), mReceiveBuffer.begin() + 1);
            continue;
        }

        // Extract command
        packet.cmd = mReceiveBuffer[kSizeMagic + kSizeSize + addrLen];

        // Extract payload
        const std::size_t beginIdx = kSizeMagic + kSizeSize + addrLen + kSizeCommand;
        const std::size_t endIdx = kSizeMagic + kSizeSize + size - kSizeCrc;
        packet.payload.assign(
            mReceiveBuffer.begin() + beginIdx,
            mReceiveBuffer.begin() + endIdx
        );

        // Erase this packet from data
        mReceiveBuffer.erase(
            mReceiveBuffer.begin(),
            mReceiveBuffer.begin() + kSizeMagic + kSizeSize + size
        );

        // Process the data
        {
            std::unique_lock<std::mutex> lock(mProcessMutex);
            mIncomingPackets.push_back(std::move(packet));
            mProcessCv.notify_all();
        }
    }
}

void DppDeviceImp::processEntrypoint()
{
    while (true)
    {
        std::list<OutgoingData> dataToSend;
        std::list<std::function<void(std::int16_t cmd, std::vector<std::uint8_t>&)>> timeoutFns;
        std::list<std::function<void(std::uint8_t cmd, std::vector<std::uint8_t>& payload)>> respFns;
        std::list<IncomingData> receivedPackets;

        {
            std::unique_lock<std::mutex> lock(mProcessMutex);

            bool waitResult = true;

            if (mTimeoutLookup.empty())
            {
                mProcessCv.wait(
                    lock,
                    [this]()
                    {
                        return !mProcessing || !mOutgoingData.empty() || !mIncomingPackets.empty();
                    }
                );
            }
            else
            {
                std::chrono::system_clock::time_point nextTimePoint = mTimeoutLookup.begin()->first;
                waitResult = mProcessCv.wait_until(
                    lock,
                    nextTimePoint,
                    [this]()
                    {
                        return !mProcessing || !mOutgoingData.empty() || !mIncomingPackets.empty();
                    }
                );
            }

            if (!mProcessing)
            {
                break;
            }
            else if (waitResult)
            {
                if (!mOutgoingData.empty())
                {
                    dataToSend = std::move(mOutgoingData);
                    mOutgoingData.clear();
                }

                if (!mIncomingPackets.empty())
                {
                    // Accumulate received packets and response functions
                    receivedPackets = std::move(mIncomingPackets);
                    mIncomingPackets.clear();
                    for (auto iter = receivedPackets.begin(); iter != receivedPackets.end();)
                    {
                        FunctionLookupMap::iterator fnIter = mFnLookup.find(iter->addr);
                        if (fnIter != mFnLookup.end())
                        {
                            respFns.push_back(std::move(fnIter->second.callback));
                            mTimeoutLookup.erase(fnIter->second.timeoutMapIter);
                            mFnLookup.erase(fnIter);
                            ++iter;
                        }
                        else
                        {
                            // Nothing around to process this packet (must have timed out)
                            iter = receivedPackets.erase(iter);
                        }
                    }
                }
            }
            else
            {
                // Accumulate timeout functions
                std::chrono::system_clock::time_point now = std::chrono::system_clock::now();

                for (auto iter = mTimeoutLookup.begin(); iter != mTimeoutLookup.end();)
                {
                    if (now < iter->first)
                    {
                        break;
                    }

                    FunctionLookupMap::iterator fnLookupIter = mFnLookup.find(iter->second);
                    if (fnLookupIter != mFnLookup.end())
                    {
                        timeoutFns.push_back(std::move(fnLookupIter->second.callback));
                        mFnLookup.erase(fnLookupIter);
                    }

                    iter = mTimeoutLookup.erase(iter);
                }
            }
        }

        // Execute send
        std::list<std::uint64_t> sendFailureAddresses;
        for (OutgoingData& data : dataToSend)
        {
            if (!send(&data.packet[0], static_cast<int>(data.packet.size())))
            {
                sendFailureAddresses.push_back(data.addr);
            }
        }

        if (!sendFailureAddresses.empty())
        {
            std::list<std::function<void(std::int16_t cmd, std::vector<std::uint8_t>&)>> sendFailureFns;

            {
                std::unique_lock<std::mutex> lock(mProcessMutex);

                for (const std::uint64_t& addr: sendFailureAddresses)
                {
                    FunctionLookupMap::iterator fnIter = mFnLookup.find(addr);
                    if (fnIter != mFnLookup.end())
                    {
                        sendFailureFns.push_back(std::move(fnIter->second.callback));
                        mTimeoutLookup.erase(fnIter->second.timeoutMapIter);
                        mFnLookup.erase(fnIter);
                    }
                }
            }

            // Execute send failure functions
            for (const std::function<void(std::int16_t cmd, std::vector<std::uint8_t>&)>& fn : sendFailureFns)
            {
                std::vector<std::uint8_t> tmpEmpty;
                fn(::dpp_api::msg::rx::Msg::kCmdSendFailure, tmpEmpty);
            }
        }

        // Execute for response
        auto respFnIter = respFns.begin();
        auto pktIter = receivedPackets.begin();
        for (; respFnIter != respFns.end() && pktIter != receivedPackets.end(); ++respFnIter, ++pktIter)
        {
            if (*respFnIter)
            {
                (*respFnIter)(pktIter->cmd, pktIter->payload);
            }
        }

        // Execute for timeout
        for (const std::function<void(std::int16_t cmd, std::vector<std::uint8_t>&)>& fn : timeoutFns)
        {
            std::vector<std::uint8_t> tmpEmpty;
            fn(::dpp_api::msg::rx::Msg::kCmdTimeout, tmpEmpty);
        }
    }

    // Accumulate all hanging functions
    std::list<std::function<void(std::int16_t cmd, std::vector<std::uint8_t>&)>> disconnectFns;

    {
        std::unique_lock<std::mutex> lock(mProcessMutex);

        for (FunctionLookupMap::reference entry : mFnLookup)
        {
            disconnectFns.push_back(std::move(entry.second.callback));
        }

        mFnLookup.clear();
        mTimeoutLookup.clear();
    }

    // Execute for disconnect
    for (const std::function<void(std::int16_t cmd, std::vector<std::uint8_t>&)>& fn : disconnectFns)
    {
        std::vector<std::uint8_t> tmpEmpty;
        fn(::dpp_api::msg::rx::Msg::kCmdDisconnect, tmpEmpty);
    }

    // Execute disconnection callback
    std::function<void(std::string& errStr)> disconnectCallback;
    std::string disconnectReason;

    {
        std::lock_guard<std::mutex> lock(mDisconnectMutex);
        disconnectCallback = mDisconnectCallback;
        disconnectReason = std::move(mDisconnectReason);
        mDisconnectReason.clear();
    }

    if (disconnectCallback)
    {
        disconnectCallback(disconnectReason);
    }
}

void DppDeviceImp::readLoop()
{}

void DppDeviceImp::stopProcessing()
{
    std::lock_guard<std::mutex> lock(mProcessMutex);
    mProcessing = false;
    mProcessCv.notify_all();
}


}
