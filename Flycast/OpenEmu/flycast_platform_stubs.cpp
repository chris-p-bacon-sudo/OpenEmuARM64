// Copyright (c) 2025, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
// EVENT SHALL OpenEmu Team BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// Platform-specific stubs for features unused in the OpenEmu single-player
// sandbox: networking (NAOMI, GGPO, modem, BBA, picotcp), input discovery
// (dreampotato), video routing, and screenshot saving.

#include "types.h"
#include "oslib/oslib.h"
#include "oslib/i18n.h"
#include "network/net_handshake.h"
#include "network/ggpo.h"
#include "network/naomi_network.h"
#include "network/netservice.h"
#include "network/output.h"
#include "input/dreampotato.h"

#include <cstdarg>
#include <cstdio>
#include <future>
#include <mutex>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// i18n stubs
// ---------------------------------------------------------------------------
namespace i18n {
std::string getCurrentLocale() { return "en"; }
}

// ---------------------------------------------------------------------------
// darw_printf — macOS debug print (declared in types.h for Apple targets)
// ---------------------------------------------------------------------------
int darw_printf(const char *text, ...)
{
    va_list args;
    va_start(args, text);
    int ret = vprintf(text, args);
    va_end(args);
    return ret;
}

// ---------------------------------------------------------------------------
// oslib stubs
// ---------------------------------------------------------------------------
void os_DoEvents() {}
void os_RunInstance(int /*argc*/, const char * /*argv*/[]) {}

std::string os_PrecomposedString(std::string string) { return string; }

// ---------------------------------------------------------------------------
// Video routing stubs (USE_OPENGL path in gles.cpp)
// ---------------------------------------------------------------------------
void os_VideoRoutingTermGL() {}
// GLuint == unsigned int; avoids pulling in GL headers here.
void os_VideoRoutingPublishFrameTexture(unsigned int /*texID*/,
                                        unsigned int /*texTarget*/,
                                        float /*w*/, float /*h*/) {}

// ---------------------------------------------------------------------------
// hostfs stubs
// getScreenshotsPath() — called by oslib.cpp's saveScreenshot; return tmp dir.
// saveScreenshot is implemented in oslib.cpp for non-iOS targets; we only need
// to supply the path helper it calls.
// ---------------------------------------------------------------------------
// Forward declaration expected by oslib.cpp in the hostfs namespace:
namespace hostfs {
std::string getScreenshotsPath() { return "/tmp"; }
}

// ---------------------------------------------------------------------------
// Serial modem stubs (alienfnt_modem.h)
// ---------------------------------------------------------------------------
void serialModemInit() {}
void serialModemTerm() {}

// ---------------------------------------------------------------------------
// dreampotato stubs (controller discovery, not needed in OpenEmu)
// ---------------------------------------------------------------------------
namespace dreampotato {
void update() {}
void term()   {}
}

// ---------------------------------------------------------------------------
// GGPO / rollback netcode stubs
// ---------------------------------------------------------------------------
namespace ggpo {

bool inRollback = false;

std::future<bool> startNetwork()
{
    std::promise<bool> p;
    p.set_value(false);
    return p.get_future();
}

void startSession(int /*localPort*/, int /*localPlayerNum*/) {}
void stopSession() {}
void getInput(MapleInputState * /*inputState*/) {}
bool nextFrame()    { return false; }
bool active()       { return false; }
void displayStats() {}
void endOfFrame()   {}
void sendChatMessage(int /*playerNum*/, const std::string & /*msg*/) {}
void receiveChatMessages(void (* /*callback*/)(int, const std::string &)) {}

} // namespace ggpo

// ---------------------------------------------------------------------------
// NetworkHandshake stubs
// ---------------------------------------------------------------------------
NetworkHandshake *NetworkHandshake::instance = nullptr;
void NetworkHandshake::init() {}
void NetworkHandshake::term() {}

// ---------------------------------------------------------------------------
// net::modbba stubs (modem/BBA, handled by picoppp.cpp normally)
// ---------------------------------------------------------------------------
namespace net::modbba {

bool start()  { return false; }
void stop()   {}

void writeModem(u8 /*b*/) {}
int  readModem()          { return -1; }
int  modemAvailable()     { return 0;  }

void receiveEthFrame(const u8 * /*frame*/, u32 /*size*/) {}

} // namespace net::modbba

// ---------------------------------------------------------------------------
// NaomiNetwork global instance + unimplemented receive() stub
// ---------------------------------------------------------------------------
NaomiNetwork naomiNetwork;

bool NaomiNetwork::receive(const sockaddr_in * /*addr*/,
                           const NaomiNetwork::Packet * /*packet*/,
                           u32 /*size*/)
{
    return false;
}

bool NaomiNetworkSupported() { return false; }

// ---------------------------------------------------------------------------
// NetworkOutput global instance
// ---------------------------------------------------------------------------
NetworkOutput networkOutput;

// ---------------------------------------------------------------------------
// picotcp mutex stubs (normally in network/picoppp.cpp)
// ---------------------------------------------------------------------------
extern "C" {

void *pico_mutex_init(void)
{
    return new std::mutex();
}

void pico_mutex_lock(void *mux)
{
    static_cast<std::mutex *>(mux)->lock();
}

void pico_mutex_unlock(void *mux)
{
    static_cast<std::mutex *>(mux)->unlock();
}

void pico_mutex_deinit(void *mux)
{
    delete static_cast<std::mutex *>(mux);
}

} // extern "C"
