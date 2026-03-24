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

//! @file this file is a hodge-podge of different tests (not meant to be thorough or give any PASS/FAIL result)

// TODO: these things need to be properly tested
// - Test send of all message types
// - Test attempt to send when not connected
// - dissconnect() and send() may be called from any callback
// - Physically removing the device will automatically disconnect()
// - Connect, disconnect, reconnect and all of the above still works

#include "DreamPicoPortApi.hpp"

#include <cstdio>
#include <thread>
#include <mutex>
#include <condition_variable>

std::condition_variable mainCv;
std::mutex mainMutex;
std::uint32_t respCount = 0;

void update_response_count()
{
    std::lock_guard<std::mutex> lock(mainMutex);
    ++respCount;
    mainCv.notify_all();
}

void response(dpp_api::msg::rx::Maple& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx\n", static_cast<std::uint8_t>(msg.cmd));
        for (std::uint8_t b : msg.packet)
        {
            printf("%02hhx ", b);
        }
        printf("\n");
    }

    update_response_count();
}

void response32(dpp_api::msg::rx::Maple32& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx\n", static_cast<std::uint8_t>(msg.cmd));
        for (std::uint32_t b : msg.packet)
        {
            printf("%04x ", b);
        }
        printf("\n");
    }

    update_response_count();
}

void player_reset_response(dpp_api::msg::rx::PlayerReset& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx, numReset: %hhu\n", static_cast<std::uint8_t>(msg.cmd), msg.numReset);
    }

    update_response_count();
}

void change_player_display_response(dpp_api::msg::rx::ChangePlayerDisplay& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx\n", static_cast<std::uint8_t>(msg.cmd));
    }

    update_response_count();
}

void refresh_gamepad_response(dpp_api::msg::rx::RefreshGamepad& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx\n", static_cast<std::uint8_t>(msg.cmd));
    }

    update_response_count();
}

void summary_response(dpp_api::msg::rx::GetDcSummary& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx\n", static_cast<std::uint8_t>(msg.cmd));
        printf("{");
        bool outerFirst = true;
        for (const std::vector<std::array<uint32_t, 2>>& periph : msg.summary)
        {
            if (!outerFirst)
            {
                printf(",");
            }

            printf("\n  {");
            bool innerFirst = true;
            for (const std::array<uint32_t, 2>& fns : periph)
            {
                if (!innerFirst)
                {
                    printf(",");
                }
                printf("{%08X, %08X}", fns[0], fns[1]);
                innerFirst = false;
            }
            printf("}");
            outerFirst = false;
        }
        if (!outerFirst)
        {
            printf("\n");
        }
        printf("}\n");
    }

    update_response_count();
}

void ver_response(dpp_api::msg::rx::GetInterfaceVersion& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx, ver:%hhu.%hhu\n", static_cast<std::uint8_t>(msg.cmd), msg.verMajor, msg.verMinor);
    }

    update_response_count();
}

void controller_state_response(dpp_api::msg::rx::GetControllerState& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx\n", static_cast<std::uint8_t>(msg.cmd));
        printf("Left analog: %hhi,%hhi\n", msg.controllerState.x, msg.controllerState.y);
        printf("Right analog: %hhi,%hhi\n", msg.controllerState.rx, msg.controllerState.ry);
        printf("Hat: ");
        switch(msg.controllerState.hat)
        {
            case dpp_api::ControllerState::GAMEPAD_HAT_UP:
                printf("UP\n");
                break;
            case dpp_api::ControllerState::GAMEPAD_HAT_UP_RIGHT:
                printf("UP-RIGHT\n");
                break;
            case dpp_api::ControllerState::GAMEPAD_HAT_RIGHT:
                printf("RIGHT\n");
                break;
            case dpp_api::ControllerState::GAMEPAD_HAT_DOWN_RIGHT:
                printf("DOWN-RIGHT\n");
                break;
            case dpp_api::ControllerState::GAMEPAD_HAT_DOWN:
                printf("DOWN\n");
                break;
            case dpp_api::ControllerState::GAMEPAD_HAT_DOWN_LEFT:
                printf("DOWN-LEFT\n");
                break;
            case dpp_api::ControllerState::GAMEPAD_HAT_LEFT:
                printf("LEFT\n");
                break;
            case dpp_api::ControllerState::GAMEPAD_HAT_UP_LEFT:
                printf("UP-LEFT\n");
                break;
            case dpp_api::ControllerState::GAMEPAD_HAT_CENTERED: // fall through
            default:
                printf("CENTERED\n");
                break;
        }
        printf(
            "Buttons: %s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n",
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_A) ? "A" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_B) ? "B" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_C) ? "C" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_X) ? "X" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_Y) ? "Y" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_Z) ? "Z" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_DPAD_B_R) ? "R" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_DPAD_B_L) ? "L" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_DPAD_B_D) ? "D" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_DPAD_B_U) ? "U" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_D) ? "D" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_BUTTON_START) ? "S" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_VMU1_A) ? "[A]" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_VMU1_B) ? "[B]" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_VMU1_U) ? "[U]" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_VMU1_D) ? "[D]" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_VMU1_L) ? "[L]" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_VMU1_R) ? "[R]" : ""),
            (msg.controllerState.isPressed(dpp_api::ControllerState::GAMEPAD_CHANGE_DETECT) ? "*" : "")
        );
        printf("Pad: %hhu\n", msg.controllerState.pad);
    }

    update_response_count();
}

void controller_connection_response(dpp_api::msg::rx::GetConnectedGamepads& msg)
{
    if (msg.cmd < 0)
    {
        printf("Response timeout\n");
    }
    else
    {
        printf("Response received; cmd: %02hhx\n", static_cast<std::uint8_t>(msg.cmd));
        int idx = 0;
        for (const dpp_api::GamepadConnectionState& state : msg.gamepadConnectionStates)
        {
            printf("%c: ", 'A' + idx++);
            switch (state)
            {
                case dpp_api::GamepadConnectionState::NOT_CONNECTED:
                    printf("NOT CONNECTED\n");
                    break;
                case dpp_api::GamepadConnectionState::CONNECTED:
                    printf("CONNECTED\n");
                    break;
                case dpp_api::GamepadConnectionState::UNAVAILABLE: // fall through
                default:
                    printf("UNAVAILABLE\n");
                    break;
            }
        }
    }

    update_response_count();
}

void read_complete(const std::string& errStr)
{
    printf("Disconnected%s%s\n", (errStr.empty() ? "" : ": "), errStr.c_str());
    fflush(stdout);
}

void list_all_devices()
{
    dpp_api::DppDevice::Filter filter;
    filter.minBcdDevice = 0x0120;
    std::uint32_t count = dpp_api::DppDevice::getCount(filter);
    printf("%u device(s) found\n", count);
    for (std::uint32_t i = 0; i < count; ++i)
    {
        filter.idx = i;
        std::unique_ptr<dpp_api::DppDevice> currentDppDevice = dpp_api::DppDevice::find(filter);
        if (currentDppDevice)
        {
            printf("   %s\n", currentDppDevice->getSerial().c_str());
        }
    }
}

bool parse_send_id(std::uint64_t id, std::uint32_t& numExpected)
{
    if (id == 0)
    {
        printf("Failed to send\n");
        return false;
    }

    ++numExpected;
    printf("Sent address: %llu\n", static_cast<long long unsigned>(id));

    return true;
}



void read_response(std::shared_ptr<dpp_api::DppDevice> dppDevice, dpp_api::msg::rx::Maple& msg)
{
    // printf("RESPONSE\n");
    static uint8_t currentAddr[4] = {};
    static uint32_t errCnt[4] = {};
    bool send = false;
    uint8_t playerIdx = 0;

    if (!dppDevice->isConnected())
    {
        printf("Read failed due to disconnect\n");
        update_response_count();
    }
    else if (msg.cmd == 0x0a && msg.packet.size() >= 4)
    {
        playerIdx = msg.packet[2] >> 6;

        if (msg.packet.size() >= 524 && msg.packet[0] == 0x08 && msg.packet[11] == currentAddr[playerIdx])
        {
            // for (std::uint8_t b : msg.packet)
            // {
            //     printf("%02hhx ", b);
            // }
            // printf("\n");

            if (currentAddr[playerIdx] == 0xFF)
            {
                printf("Player %i read complete\n", playerIdx + 1);
                update_response_count();
            }
            else
            {
                ++currentAddr[playerIdx];
                errCnt[playerIdx] = 0;
                send = true;
            }
        }
        else if (++errCnt[playerIdx] >= 4)
        {
            printf("Player %i read failed at addr %02hhx\n", playerIdx + 1, currentAddr[playerIdx]);
            update_response_count();
        }
        else
        {
            send = true;
        }
    }
    else
    {
        printf("Read failed due to invalid response\n");
        update_response_count();
    }

    if (send)
    {
        dpp_api::DppDevice* dppDevicePtr = dppDevice.get();
        uint64_t sent = dppDevicePtr->send(
            dpp_api::msg::tx::Maple{
                {0x0B, msg.packet[2], msg.packet[1], 2, 0, 0, 0, 2, 0, 0, 0, currentAddr[playerIdx]}
            },
            [dppDevice = std::move(dppDevice)](dpp_api::msg::rx::Maple& msg){read_response(dppDevice, msg);},
            500
        );
        if (sent == 0)
        {
            printf("Send failure: %s\n", dppDevicePtr->getLastErrorStr().c_str());
        }
        // else
        // {
        //     printf("Sent address: %llu\n", static_cast<long long unsigned>(sent));
        // }
    }
}

bool wait_async_complete(std::uint32_t numExpected)
{
    std::unique_lock<std::mutex> lock(mainMutex);
    std::uint32_t* c = &respCount;
    mainCv.wait_for(lock, std::chrono::milliseconds(5000), [c, numExpected](){return *c >= numExpected;});
    return (respCount >= numExpected);
}

int main(int argc, char **argv)
{
    list_all_devices();
    dpp_api::DppDevice::Filter filter;
    filter.minBcdDevice = 0x0120;
    std::shared_ptr<dpp_api::DppDevice> dppDevice = dpp_api::DppDevice::find(filter);

    if (dppDevice)
    {
        std::uint64_t sent = 0;
        std::uint32_t numExpected = 0;

        std::array<std::uint8_t, 3> ver = dppDevice->getVersion();
        printf("FOUND! %s v%hhu.%hhu.%hhu\n", dppDevice->getSerial().c_str(), ver[0], ver[1], ver[2]);
        if (!dppDevice->connect(read_complete))
        {
            printf("Failed to connect: %s\n", dppDevice->getLastErrorStr().c_str());
            return 1;
        }

        if (!dppDevice->isConnected())
        {
            printf("Not actually connected\n");
            return 1;
        }

        // Test disconnect and reconnect
        if (!dppDevice->connect(read_complete))
        {
            printf("Failed to reconnect: %s\n", dppDevice->getLastErrorStr().c_str());
            return 1;
        }

        sent = dppDevice->send(
            dpp_api::msg::tx::Maple32{
                {
                    0x0C010032, 0x00000004, 0x00000000,
                    0x68003FC0, 0x0201FC01, 0xC03C0C03, 0xFE060007, 0x98076F08, 0x0071F00E, 0xFF10000C, 0x601FFF60,
                    0x0002303F, 0x6DC00001, 0x1836FF83, 0x01F0147F, 0xFFBD060E, 0x107F6DCE, 0x3807A0F6, 0xFF8BC807,
                    0xC0FFC30F, 0x0C05407F, 0x1F1F0E05, 0x607E67FD, 0x0B873FC7, 0x8FEB0DFF, 0xF8F13355, 0x0ABFFF3D,
                    0x46AB0D55, 0x63E10F55, 0x0AAAA07B, 0x3AAA0555, 0x6021E356, 0x06AAA03C, 0x82AA0555, 0x60270756,
                    0x02AAA021, 0x06AA0355, 0x40200754, 0x01AAC020, 0x0DAC00D5, 0x40601CF8, 0x006A8070, 0x1410003F,
                    0x00502200, 0x00180048, 0x2200000E, 0x00884100, 0x00000084, 0x41000000, 0x01048080, 0x00000102
                }
            },
            response32,
            500
        );

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        sent = dppDevice->send(dpp_api::msg::tx::PlayerReset{0}, player_reset_response, 500);

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        sent = dppDevice->send(dpp_api::msg::tx::ChangePlayerDisplay{0, 1}, change_player_display_response, 500);

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        sent = dppDevice->send(dpp_api::msg::tx::GetDcSummary{0}, summary_response, 500);

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        sent = dppDevice->send(dpp_api::msg::tx::GetInterfaceVersion{}, ver_response, 500);

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        sent = dppDevice->send(dpp_api::msg::tx::GetControllerState{0}, controller_state_response, 500);

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        sent = dppDevice->send(dpp_api::msg::tx::RefreshGamepad{0}, refresh_gamepad_response, 500);

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        sent = dppDevice->send(dpp_api::msg::tx::GetConnectedGamepads{}, controller_connection_response, 500);

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        // Test result: can read 1 VMU in 2.2 seconds and 4 VMUs in parallel in 2.6 seconds \o/
        auto start = std::chrono::high_resolution_clock::now();

        sent = dppDevice->send(
            dpp_api::msg::tx::Maple{{0x0B, 0x01, 0x00, 2, 0, 0, 0, 2, 0, 0, 0, 0}},
            [dppDevice](dpp_api::msg::rx::Maple& msg){read_response(dppDevice, msg);},
            500
        );

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        std::this_thread::sleep_for(std::chrono::microseconds(2500));

        sent = dppDevice->send(
            dpp_api::msg::tx::Maple{{0x0B, 0x41, 0x40, 2, 0, 0, 0, 2, 0, 0, 0, 0}},
            [dppDevice](dpp_api::msg::rx::Maple& msg){read_response(dppDevice, msg);},
            500
        );

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        std::this_thread::sleep_for(std::chrono::microseconds(2500));

        sent = dppDevice->send(
            dpp_api::msg::tx::Maple{{0x0B, 0x81, 0x80, 2, 0, 0, 0, 2, 0, 0, 0, 0}},
            [dppDevice](dpp_api::msg::rx::Maple& msg){read_response(dppDevice, msg);},
            500
        );

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        std::this_thread::sleep_for(std::chrono::microseconds(2500));

        sent = dppDevice->send(
            dpp_api::msg::tx::Maple{{0x0B, 0xC1, 0xC0, 2, 0, 0, 0, 2, 0, 0, 0, 0}},
            [dppDevice](dpp_api::msg::rx::Maple& msg){read_response(dppDevice, msg);},
            500
        );

        if (!parse_send_id(sent, numExpected))
        {
            return 2;
        }

        // Wait until all asynchronous commands fully process
        wait_async_complete(numExpected);

        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
        printf("Time elapsed: %lld ms\n", static_cast<long long>(duration.count()));

        // Test a synchronous command
        dpp_api::msg::rx::GetControllerState st = dppDevice->sendSync(dpp_api::msg::tx::GetControllerState{0}, 500);
        controller_state_response(st);

        // Sleep to test for physical disconnect detection
        // std::this_thread::sleep_for(std::chrono::milliseconds(5000));

        // For confirmation that no asynchronous messages are still waiting
        printf("Num waiting: %i\n", static_cast<int>(dppDevice->getNumWaiting()));
    }
    else
    {
        printf("not found :(\n");
        return 3;
    }
    return 0;
}
