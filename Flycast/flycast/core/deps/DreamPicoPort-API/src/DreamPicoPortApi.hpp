#ifndef __DREAM_PICO_PORT_API_HPP__
#define __DREAM_PICO_PORT_API_HPP__

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

#include <memory>
#include <string>
#include <cstdint>
#include <vector>
#include <list>
#include <array>
#include <unordered_map>
#include <map>
#include <mutex>
#include <functional>
#include <chrono>
#include <condition_variable>
#include <thread>
#include <limits>

#if defined(_WIN32)
    #ifdef WIN32_DREAM_PICO_PORT_EXPORTS
        #define DREAM_PICO_PORT_API __declspec(dllexport)
        #define DREAM_PICO_PORT_EXPORT_API __declspec(dllexport)
    #elif defined(WIN32_DREAM_PICO_PORT_IMPORTS)
        #define DREAM_PICO_PORT_API __declspec(dllimport)
        #define DREAM_PICO_PORT_EXPORT_API __declspec(dllexport)
    #else
        #define DREAM_PICO_PORT_API
        #define DREAM_PICO_PORT_EXPORT_API
    #endif
#else
    #define DREAM_PICO_PORT_API
    #define DREAM_PICO_PORT_EXPORT_API
#endif

namespace dpp_api
{

//! Contains controller state data
struct DREAM_PICO_PORT_EXPORT_API ControllerState
{
    //! Enumerates hat state
    enum DpadButtons : std::uint8_t
    {
        GAMEPAD_HAT_CENTERED   = 0,  //!< DPAD_CENTERED
        GAMEPAD_HAT_UP         = 1,  //!< DPAD_UP
        GAMEPAD_HAT_UP_RIGHT   = 2,  //!< DPAD_UP_RIGHT
        GAMEPAD_HAT_RIGHT      = 3,  //!< DPAD_RIGHT
        GAMEPAD_HAT_DOWN_RIGHT = 4,  //!< DPAD_DOWN_RIGHT
        GAMEPAD_HAT_DOWN       = 5,  //!< DPAD_DOWN
        GAMEPAD_HAT_DOWN_LEFT  = 6,  //!< DPAD_DOWN_LEFT
        GAMEPAD_HAT_LEFT       = 7,  //!< DPAD_LEFT
        GAMEPAD_HAT_UP_LEFT    = 8,  //!< DPAD_UP_LEFT
    };

    //! Enumerates buttons
    enum GamepadButton : uint8_t
    {
        GAMEPAD_BUTTON_A = 0,
        GAMEPAD_BUTTON_B = 1,
        GAMEPAD_BUTTON_C = 2,
        GAMEPAD_BUTTON_X = 3,
        GAMEPAD_BUTTON_Y = 4,
        GAMEPAD_BUTTON_Z = 5,
        GAMEPAD_BUTTON_DPAD_B_R = 6,
        GAMEPAD_BUTTON_DPAD_B_L = 7,
        GAMEPAD_BUTTON_DPAD_B_D = 8,
        GAMEPAD_BUTTON_DPAD_B_U = 9,
        GAMEPAD_BUTTON_D = 10,
        GAMEPAD_BUTTON_START = 11,
        GAMEPAD_VMU1_A = 12,
        GAMEPAD_VMU1_B = 15,
        GAMEPAD_VMU1_U = 16,
        GAMEPAD_VMU1_D = 17,
        GAMEPAD_VMU1_L = 18,
        GAMEPAD_VMU1_R = 19,
        GAMEPAD_CHANGE_DETECT = 20
    };

    std::int8_t  x = 0; //!< Delta x  movement of left analog-stick
    std::int8_t  y = 0; //!< Delta y  movement of left analog-stick
    std::int8_t  z = 0; //!< Delta z  movement of left trigger
    std::int8_t  rz = 0; //!< Delta Rz movement of right tirgger
    std::int8_t  rx = 0; //!< Delta Rx movement of analog right analog-stick
    std::int8_t  ry = 0; //!< Delta Ry movement of analog right analog-stick
    DpadButtons hat = GAMEPAD_HAT_CENTERED; //!< Buttons mask for currently pressed buttons in the DPad/hat
    std::uint32_t buttons = 0; //!< Buttons mask for currently pressed buttons @see isPressed
    std::uint8_t pad = 0; //!< Vendor data (padding, set to player index)

    //! Checks if a button is pressed in this state
    //! @param[in] btn Button enumeration value to check
    //! @return true iff \p btn is pressed
    inline bool isPressed(GamepadButton btn) const
    {
        return ((buttons & (1 << btn)) != 0);
    }
};

//! Enumerates gamepad connection states
enum class DREAM_PICO_PORT_EXPORT_API GamepadConnectionState : std::uint8_t
{
    UNAVAILABLE = 0, //!< No gamepad available at this index
    NOT_CONNECTED = 1, //!< Gamepad available but not connected
    CONNECTED = 2 //!< Gamepad available and connected
};

namespace msg
{
namespace rx
{

struct Msg
{
    //! One of kCmd* values
    std::int16_t cmd = kCmdSendFailure;

    //! The cmd response for successful execution
    static constexpr const std::int16_t kCmdSuccess = 0x0A;
    //! The cmd response for execution complete with warning
    static constexpr const std::int16_t kCmdAttention = 0x0B;
    //! The cmd response for execution failure
    static constexpr const std::int16_t kCmdFailure = 0x0F;
    //! The cmd response for invalid command or missing data
    static constexpr const std::int16_t kCmdInvalid = 0xFE;
    //! The cmd response value set in the callback when send failure occurred
    static constexpr const std::int16_t kCmdSendFailure = -1;
    //! The cmd response value set in the callback when timeout occurred before response received
    static constexpr const std::int16_t kCmdTimeout = -2;
    //! The cmd response value set in the callback when device disconnected before response received
    static constexpr const std::int16_t kCmdDisconnect = -3;
};

struct Maple32 : Msg
{
    //! when cmd is kCmdSuccess, the returned maple payload
    std::vector<std::uint32_t> packet;

    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

struct Maple : Msg
{
    //! when cmd is kCmdSuccess, the returned maple payload
    std::vector<std::uint8_t> packet;

    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

struct PlayerReset : Msg
{
    //! Number of players that have been reset
    std::uint8_t numReset = 0;

    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

struct ChangePlayerDisplay : Msg
{
    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

struct GetDcSummary : Msg
{
    //! When cmd is kCmdSuccess, this contains peripheral summary data
    //! - Each element in the outer vector represents a peripheral in order (first is main)
    //! - Each element in the inner vector represents function definition (max of 3)
    //! - First array element is function code, second is function definition word
    std::vector<std::vector<std::array<uint32_t, 2>>> summary;

    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

struct GetInterfaceVersion : Msg
{
    //! Major version number
    std::uint8_t verMajor = 0;
    //! Minor version number
    std::uint8_t verMinor = 0;

    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

struct GetControllerState : Msg
{
    //! When cmd is kCmdSuccess, the current controller state
    ControllerState controllerState;

    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

struct RefreshGamepad : Msg
{
    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

struct GetConnectedGamepads : Msg
{
    //! Controller connection state for each controller
    std::array<GamepadConnectionState, 4> gamepadConnectionStates;

    //! Internally called to set data based on received payload
    //! @param[in] cmd The received command
    //! @param[in] payload The received payload
    virtual void set(std::int16_t cmd, std::vector<std::uint8_t>& payload);
};

} // namespace rx
namespace tx
{

struct Maple32
{
    //! The maple payload which contains at least 1 word (MSB is command)
    std::vector<std::uint32_t> packet;

    //! Set to true to send through emulator interface
    bool emu = false;

    //! The expected response type
    using ResponseType = rx::Maple32;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

struct Maple
{
    //! The maple payload which contains at least 4 bytes (first byte is command)
    std::vector<std::uint8_t> packet;

    //! Set to true to send through emulator interface
    bool emu = false;

    //! The expected response type
    using ResponseType = rx::Maple;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

struct PlayerReset
{
    //! Player index [0,3] or -1 for all players
    std::int8_t idx;

    //! The expected response type
    using ResponseType = rx::PlayerReset;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

struct ChangePlayerDisplay
{
    //! Player index [0,3] of the target controller
    std::uint8_t idx;
    //! Player index [0,3] to change the display to
    std::uint8_t toIdx;

    //! The expected response type
    using ResponseType = rx::ChangePlayerDisplay;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

struct GetDcSummary
{
    //! Player index [0,3] of the target controller
    std::uint8_t idx;

    //! The expected response type
    using ResponseType = rx::GetDcSummary;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

struct GetInterfaceVersion
{
    //! The expected response type
    using ResponseType = rx::GetInterfaceVersion;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

struct GetControllerState
{
    //! Player index [0,3] of the target controller
    std::uint8_t idx;

    //! The expected response type
    using ResponseType = rx::GetControllerState;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

struct RefreshGamepad
{
    //! Player index [0,3] of the target controller
    std::uint8_t idx;

    //! The expected response type
    using ResponseType = rx::RefreshGamepad;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

struct GetConnectedGamepads
{
    //! The expected response type
    using ResponseType = rx::GetConnectedGamepads;

    //! Internally called to pack this message into outgoing data
    //! @return pair containing command and payload for the message
    std::pair<std::uint8_t, std::vector<std::uint8_t>> get() const;
};

} // namespace tx
} // namespace msg

class DREAM_PICO_PORT_API DppDevice
{
private:
    //! Constructor
    //! @param dev Pointer to internal implementation
    DppDevice(std::unique_ptr<class DppDeviceImp>&& dev);

public:
    //! Destructor
    //! NOTICE: DppDevice may not be destructed from any callback
    virtual ~DppDevice();

    //! Filter used to find a DreamPicoPort device
    struct Filter
    {
        //! Device serial or empty string for any serial
        std::string serial = std::string();
        //! Device index
        //! @note A device is removed from the searched set if a handle to it has already been made.
        //!       For example, if find() returns device at index 0, the device at the previous index 1 moves to index 0.
        std::uint32_t idx = 0;
        //! Vendor ID (not recommended to change this from default unless another device implements this protocol)
        std::uint16_t idVendor = 0x1209;
        //! Product ID (not recommended to change this from default unless another device implements this protocol)
        std::uint16_t idProduct = 0x2F07;
        //! Minimum BCD version number (inclusive, default is 1.2.1)
        //! @note Version 1.2.0 is compatible but contains a bug which only allows for 1 command at a time.
        //!       Any less than version 1.2.0 will not connect.
        std::uint16_t minBcdDevice = 0x0121;
        //! Maximum BCD version number (inclusive, 0xFFFF for no limit)
        std::uint16_t maxBcdDevice = 0xFFFF;
    };

    //! Find a device
    //! @param[in] filter The filter parameters
    //! @return pointer to the located device if found
    //! @return nullptr otherwise
    static std::unique_ptr<DppDevice> find(const Filter& filter);

    //! @param[in] filter The filter parameters (idx is ignored)
    //! @return the number of DreamPicoPort devices
    static std::uint32_t getCount(const Filter& filter);

    //! Sets the maximum return address value used to tag each command
    //! @note the minimum maximum is 0x0FFFFFFF to ensure proper execution
    //! @param[in] maxAddr The maximum address value to set
    static void setMaxAddr(std::uint64_t maxAddr);

    //! @return the serial of this device
    const std::string& getSerial() const;

    //! @return USB version number {major, minor, patch}
    std::array<std::uint8_t, 3> getVersion() const;

    //! @return string representation of last error
    std::string getLastErrorStr();

    //! Connect to the device and start operation threads. If already connected, disconnect before reconnecting.
    //! @param[in] fn When true is returned, this is the function that will execute when the device is disconnected
    //!               errStr: the reason for disconnection or empty string if disconnect() was called
    //!               NOTICE: Any attempt to call connect() within any callback function will always fail
    //! @return false on failure and getLastErrorStr() will return error description
    //! @return true if connection succeeded
    bool connect(const std::function<void(std::string& errStr)>& fn = nullptr);

    //! Disconnect from the previously connected device and stop all threads
    //! @return false on failure and getLastErrorStr() will return error description
    //! @return true if disconnection succeeded or was already disconnected
    bool disconnect();

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
        const std::function<void(std::int16_t cmd, std::vector<std::uint8_t>& payload)>& respFn = nullptr,
        std::uint32_t timeoutMs = 1000
    );

    //! Send a dpp_api::msg::tx::* type and asynchronously get the associated dpp_api::msg::rx:* type
    //! @tparam T a dpp_api::msg::tx::* type
    //! @param[in] tx The transmission data
    //! @param[in] respFn The function to call on received response, timeout, or disconnect (may be set to nullptr)
    //!                   NOTICE: Any attempt to call connect() within any callback function will always fail
    //! @param[in] timeoutMs The maximum amount of time before receiving a response at respFn
    //! @return 0 if send failed and getLastErrorStr() will return error description
    //! @return the ID of the sent data
    template <typename T>
    std::uint64_t send(
        const T& tx,
        const std::function<void(typename T::ResponseType&)>& respFn = nullptr,
        std::uint32_t timeoutMs = 1000
    )
    {
        std::pair<std::uint8_t, std::vector<std::uint8_t>> txData = tx.get();

        if (respFn)
        {
            return send(
                txData.first,
                txData.second,
                [respFn](std::int16_t cmd, std::vector<std::uint8_t>& payload)
                {
                    typename T::ResponseType response;
                    response.set(cmd, payload);
                    respFn(response);
                },
                timeoutMs
            );
        }
        else
        {
            return send(txData.first, txData.second, nullptr, timeoutMs);
        }
    }

    //! Send a dpp_api::msg::tx::* type and synchronously get the associated dpp_api::msg::rx:* type
    //! @tparam T a dpp_api::msg::tx::* type
    //! @param[in] tx The transmission data
    //! @param[in] timeoutMs The maximum amount of time to block before receiving a response
    //! @return the resulting data
    template <typename T>
    typename T::ResponseType sendSync(const T& tx, std::uint32_t timeoutMs = 1000)
    {
        std::mutex mutex;
        std::condition_variable cv;
        bool done = false;
        typename T::ResponseType result;

        std::uint64_t v = send(
            tx,
            [&mutex, &cv, &done, &result](typename T::ResponseType& response)
            {
                std::lock_guard<std::mutex> lock(mutex);
                result = std::move(response);
                done = true;
                cv.notify_all();
            },
            timeoutMs
        );

        if (v > 0)
        {
            std::unique_lock<std::mutex> lock(mutex);
            cv.wait(lock, [&done](){return done;});
        }

        return result;
    }

    //! @return true iff currently connected
    bool isConnected();

    //! @return number of waiting responses
    std::size_t getNumWaiting();

    //! Retrieve the currently connected interface number (first VENDOR interface found on connect())
    //! @return the connected interface number
    int getInterfaceNumber();

    //! @return the currently used IN endpoint
    std::uint8_t getEpIn();

    //! @return the currently used OUT endpoint
    std::uint8_t getEpOut();

private:
    //! Forward declared pointer to internal implementation class
    std::unique_ptr<class DppDeviceImp> mImp;
};

}

#endif // __DREAM_PICO_PORT_API_HPP__
