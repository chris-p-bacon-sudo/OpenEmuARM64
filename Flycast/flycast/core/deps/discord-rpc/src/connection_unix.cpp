#include "connection.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>
#include <vector>
#include <string>

int GetProcessId()
{
    return ::getpid();
}

struct BaseConnectionUnix : public BaseConnection {
    int sock{-1};
};

static BaseConnectionUnix Connection;
static sockaddr_un PipeAddr{};
#ifdef MSG_NOSIGNAL
static int MsgFlags = MSG_NOSIGNAL;
#else
static int MsgFlags = 0;
#endif

static const char* GetTempPath()
{
    const char* temp = getenv("XDG_RUNTIME_DIR");
    temp = temp ? temp : getenv("TMPDIR");
    temp = temp ? temp : getenv("TMP");
    temp = temp ? temp : getenv("TEMP");
    temp = temp ? temp : "/tmp";
    return temp;
}

/*static*/ BaseConnection* BaseConnection::Create()
{
    PipeAddr.sun_family = AF_UNIX;
    return &Connection;
}

/*static*/ void BaseConnection::Destroy(BaseConnection*& c)
{
    auto self = reinterpret_cast<BaseConnectionUnix*>(c);
    self->Close();
    c = nullptr;
}

bool BaseConnection::Open()
{
    const char* tempPath = GetTempPath();
    auto self = reinterpret_cast<BaseConnectionUnix*>(this);
    int socket_type = SOCK_STREAM;
#ifdef SOCK_CLOEXEC
    socket_type |= SOCK_CLOEXEC;
#endif
    self->sock = socket(AF_UNIX, socket_type, 0);
    if (self->sock == -1) {
        return false;
    }
#ifndef SOCK_CLOEXEC
    fcntl(self->sock, F_SETFD, FD_CLOEXEC);
#endif
    fcntl(self->sock, F_SETFL, O_NONBLOCK);
#ifdef SO_NOSIGPIPE
    int optval = 1;
    setsockopt(self->sock, SOL_SOCKET, SO_NOSIGPIPE, &optval, sizeof(optval));
#endif

    std::vector<std::string> basePaths = {std::string(tempPath) + "/snap.discord", tempPath};

    for (const auto& basePath : basePaths) {
        for (int pipeNum = 0; pipeNum < 10; ++pipeNum) {
            snprintf(PipeAddr.sun_path,
                     sizeof(PipeAddr.sun_path),
                     "%s/discord-ipc-%d",
                     basePath.c_str(),
                     pipeNum);
            int err = connect(self->sock, (const sockaddr*)&PipeAddr, sizeof(PipeAddr));
            if (err == 0) {
                self->isOpen = true;
                return true;
            }
        }
    }
    self->Close();
    return false;
}

bool BaseConnection::Close()
{
    auto self = reinterpret_cast<BaseConnectionUnix*>(this);
    if (self->sock == -1) {
        return false;
    }
    close(self->sock);
    self->sock = -1;
    self->isOpen = false;
    return true;
}

bool BaseConnection::Write(const void* data, size_t length)
{
    auto self = reinterpret_cast<BaseConnectionUnix*>(this);

    if (self->sock == -1) {
        return false;
    }

    ssize_t sentBytes = send(self->sock, data, length, MsgFlags);
    if (sentBytes < 0) {
        Close();
    }
    return sentBytes == (ssize_t)length;
}

bool BaseConnection::Read(void* data, size_t length)
{
    auto self = reinterpret_cast<BaseConnectionUnix*>(this);

    if (self->sock == -1) {
        return false;
    }

    int res = (int)recv(self->sock, data, length, MsgFlags);
    if (res < 0) {
        if (errno == EAGAIN) {
            return false;
        }
        Close();
    }
    else if (res == 0) {
        Close();
    }
    return res == (int)length;
}
