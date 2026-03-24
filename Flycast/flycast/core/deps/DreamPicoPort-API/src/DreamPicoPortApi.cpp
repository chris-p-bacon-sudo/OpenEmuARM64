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

#include "DreamPicoPortApi.hpp"
#include "DppDeviceImp.hpp"
#ifndef DREAMPICOPORT_NO_LIBUSB
    #include "DppLibusbDeviceImp.hpp"
#else
#ifdef _WIN32
    #include "DppWinRtDeviceImp.hpp"
#else
    #error "This OS not supported without libusb"
#endif
#endif

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
// Message tx and rx definitions
//

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::Maple32::get() const
{
    std::vector<std::uint8_t> packet8;
    packet8.reserve((emu ? 1 : 0) + packet.size() * 4);

    if (emu)
    {
        packet8.push_back(0x05);
    }

    for (std::uint32_t word : packet)
    {
        std::uint8_t buffer[4];
        DppDeviceImp::uint32ToBytes(buffer, word);
        packet8.insert(packet8.end(), buffer, buffer + 4);
    }

    return std::make_pair(emu ? 'X' : '0', std::move(packet8));
}

void msg::rx::Maple32::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;

    packet.clear();
    packet.reserve(payload.size() / 4);
    for (std::size_t i = 0; (i + 4) <= payload.size(); i+=4)
    {
        packet.push_back(DppDeviceImp::bytesToUint32(&payload[i]));
    }
}

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::Maple::get() const
{
    std::vector<std::uint8_t> packetCpy;
    packetCpy.reserve((emu ? 1 : 0) + packet.size());

    if (emu)
    {
        packetCpy.push_back(0x05);
    }

    packetCpy.insert(packetCpy.end(), packet.begin(), packet.end());
    return std::make_pair(emu ? 'X' : '0', std::move(packetCpy));
}

void msg::rx::Maple::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;
    packet = std::move(payload);
}

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::PlayerReset::get() const
{
    std::vector<std::uint8_t> payload;
    payload.reserve(2);
    payload.push_back('-');
    if (idx >= 0)
    {
        payload.push_back(idx);
    }

    return std::make_pair('X', std::move(payload));
}

void msg::rx::PlayerReset::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;

    if (cmd == kCmdSuccess && !payload.empty())
    {
        numReset = payload[0];
    }
}

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::ChangePlayerDisplay::get() const
{
    std::vector<std::uint8_t> payload;
    payload.reserve(3);
    payload.push_back('P');
    payload.push_back(idx);
    payload.push_back(toIdx);

    return std::make_pair('X', std::move(payload));
}

void msg::rx::ChangePlayerDisplay::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;
}

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::GetDcSummary::get() const
{
    std::vector<std::uint8_t> payload;
    payload.reserve(2);
    payload.push_back('?');
    payload.push_back(idx);

    return std::make_pair('X', std::move(payload));
}

void msg::rx::GetDcSummary::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;

    std::size_t pidx = 0;
    while (pidx < payload.size())
    {
        std::vector<std::array<uint32_t, 2>> currentPeriph;
        std::array<std::uint32_t, 2> arr;
        std::size_t aidx = 0;
        // Pipe means that 4-byte function data should follow (should be in pairs)
        while (pidx < payload.size() && payload[pidx] == '|')
        {
            ++pidx; // skip past pipe
            if (pidx + 4 <= payload.size())
            {
                arr[aidx++] = DppDeviceImp::bytesToUint32(&payload[pidx]);
                if (aidx >= arr.size())
                {
                    currentPeriph.push_back(std::move(arr));
                    aidx = 0;
                }
                pidx += 4;
            }
            else
            {
                // Not enough data - skip to the end
                pidx = payload.size();
            }
        }

        // Add the accumulated peripheral data
        currentPeriph.shrink_to_fit();
        summary.push_back(std::move(currentPeriph));

        if (pidx < payload.size())
        {
            // This is assumed to be a semicolon which terminates the current peripheral
            ++pidx;
        }
    }

    summary.shrink_to_fit();
}

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::GetInterfaceVersion::get() const
{
    std::vector<std::uint8_t> payload(1, 'V');
    return std::make_pair('X', std::move(payload));
}

void msg::rx::GetInterfaceVersion::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;

    if (cmd == kCmdSuccess && payload.size() >= 2)
    {
        verMajor = payload[0];
        verMinor = payload[1];
    }
}

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::GetControllerState::get() const
{
    std::vector<std::uint8_t> payload;
    payload.reserve(2);
    payload.push_back('R');
    payload.push_back(idx);
    return std::make_pair('X', std::move(payload));
}

void msg::rx::GetControllerState::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;

    if (cmd == kCmdSuccess)
    {
        if (payload.size() > 0)
        {
            controllerState.x = payload[0];
        }

        if (payload.size() > 1)
        {
            controllerState.y = payload[1];
        }

        if (payload.size() > 2)
        {
            controllerState.z = payload[2];
        }

        if (payload.size() > 3)
        {
            controllerState.rz = payload[3];
        }

        if (payload.size() > 4)
        {
            controllerState.rx = payload[4];
        }

        if (payload.size() > 5)
        {
            controllerState.ry = payload[5];
        }

        if (payload.size() > 6)
        {
            controllerState.hat = static_cast<ControllerState::DpadButtons>(payload[6]);
        }

        if (payload.size() > 10)
        {
            // Button state in little-endian order
            controllerState.buttons = (
                (static_cast<std::uint32_t>(payload[7])) |
                (static_cast<std::uint32_t>(payload[8]) << 8) |
                (static_cast<std::uint32_t>(payload[9]) << 16) |
                (static_cast<std::uint32_t>(payload[10]) << 24)
            );
        }

        if (payload.size() > 11)
        {
            controllerState.pad = payload[11];
        }
    }
}

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::RefreshGamepad::get() const
{
    std::vector<std::uint8_t> payload;
    payload.reserve(2);
    payload.push_back('G');
    payload.push_back(idx);
    return std::make_pair('X', std::move(payload));
}

void msg::rx::RefreshGamepad::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;
}

std::pair<std::uint8_t, std::vector<std::uint8_t>> msg::tx::GetConnectedGamepads::get() const
{
    std::vector<std::uint8_t> payload(1, 'O');
    return std::make_pair('X', std::move(payload));
}

void msg::rx::GetConnectedGamepads::set(std::int16_t cmd, std::vector<std::uint8_t>& payload)
{
    this->cmd = cmd;

    std::size_t idx = 0;
    while (idx < gamepadConnectionStates.size() && idx < payload.size())
    {
        gamepadConnectionStates[idx] = static_cast<GamepadConnectionState>(payload[idx]);
        ++idx;
    }
}

//
// DppDevice definitions
//

DppDevice::DppDevice(std::unique_ptr<DppDeviceImp>&& dev) : mImp(std::move(dev))
{}

DppDevice::~DppDevice()
{}

std::unique_ptr<DppDevice> DppDevice::find(const Filter& filter)
{
    std::unique_ptr<DppDeviceImp> dppDeviceImp;

#ifndef DREAMPICOPORT_NO_LIBUSB
    dppDeviceImp = DppLibusbDeviceImp::find(filter);
#elif defined(_WIN32)
    dppDeviceImp = DppWinRtDeviceImp::find(filter);
#else
    return nullptr;
#endif

    if (!dppDeviceImp)
    {
        return nullptr;
    }

    struct DppDeviceFactory : public DppDevice
    {
        DppDeviceFactory(std::unique_ptr<class DppDeviceImp>&& dev) : DppDevice(std::move(dev)) {}
    };

    return std::make_unique<DppDeviceFactory>(std::move(dppDeviceImp));
}

std::uint32_t DppDevice::getCount(const Filter& filter)
{
#ifndef DREAMPICOPORT_NO_LIBUSB
    return DppLibusbDeviceImp::getCount(filter);
#elif defined(_WIN32)
    return DppWinRtDeviceImp::getCount(filter);
#else
    return 0;
#endif
}

void DppDevice::setMaxAddr(std::uint64_t maxAddr)
{
    DppDeviceImp::setMaxAddr(maxAddr);
}

const std::string& DppDevice::getSerial() const
{
    return mImp->getSerial();
}

std::array<std::uint8_t, 3> DppDevice::getVersion() const
{
    return mImp->getVersion();
}

std::string DppDevice::getLastErrorStr()
{
    return mImp->getLastErrorStr();
}

bool DppDevice::connect(const std::function<void(std::string& errStr)>& fn)
{
    return mImp->connect(fn);
}

bool DppDevice::disconnect()
{
    return mImp->disconnect();
}

std::uint64_t DppDevice::send(
    std::uint8_t cmd,
    const std::vector<std::uint8_t>& payload,
    const std::function<void(std::int16_t cmd, std::vector<std::uint8_t>& payload)>& respFn,
    std::uint32_t timeoutMs
)
{
    return mImp->send(cmd, payload, respFn, timeoutMs);
}

bool DppDevice::isConnected()
{
    return mImp->isConnected();
}

std::size_t DppDevice::getNumWaiting()
{
    return mImp->getNumWaiting();
}

int DppDevice::getInterfaceNumber()
{
    return mImp->getInterfaceNumber();
}

std::uint8_t DppDevice::getEpIn()
{
    return mImp->getEpIn();
}

std::uint8_t DppDevice::getEpOut()
{
    return mImp->getEpOut();
}

} // namespace dpp_api
