#pragma once
#include <stdint.h>

// clang-format off

#if defined(DISCORD_DYNAMIC_LIB)
#  if defined(_WIN32)
#    if defined(DISCORD_BUILDING_SDK)
#      define DISCORD_EXPORT __declspec(dllexport)
#    else
#      define DISCORD_EXPORT __declspec(dllimport)
#    endif
#  else
#    define DISCORD_EXPORT __attribute__((visibility("default")))
#  endif
#else
#  define DISCORD_EXPORT
#endif

// clang-format on

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DiscordButton {
    const char* label;
    const char* url;
} DiscordButton;

typedef struct DiscordRichPresence {
    const char* state;   /* max 128 bytes */
    const char* details; /* max 128 bytes */
    int64_t startTimestamp;
    int64_t endTimestamp;
    const char* largeImageKey;  /* max 32 bytes */
    const char* largeImageText; /* max 128 bytes */
    const char* smallImageKey;  /* max 32 bytes */
    const char* smallImageText; /* max 128 bytes */
    const char* partyId;        /* max 128 bytes */
    int partySize;
    int partyMax;
    int partyPrivacy;
    const char* matchSecret;    /* max 128 bytes */
    const char* joinSecret;     /* max 128 bytes */
    const char* spectateSecret; /* max 128 bytes */
    int8_t instance;
    const DiscordButton* buttons;
} DiscordRichPresence;

typedef struct DiscordUser {
    const char* userId;
    const char* username;
    const char* discriminator;
    const char* globalName;
    const char* avatar;
} DiscordUser;

typedef struct DiscordEventHandlers {
    void (*ready)(const DiscordUser* user);
    void (*disconnected)(int errorCode, const char* message);
    void (*errored)(int errorCode, const char* message);
    void (*debug)(char isOut, const char* opcodeName, const char* message, uint32_t messageLength);
    void (*joinGame)(const char* joinSecret);
    void (*spectateGame)(const char* spectateSecret);
    void (*joinRequest)(const DiscordUser* user);
    void (*invited)(/* DISCORD_ACTIVITY_ACTION_TYPE_ */ int8_t type,
                    const DiscordUser* user,
                    const DiscordRichPresence* activity,
                    const char* sessionId,
                    const char* channelId,
                    const char* messageId);
} DiscordEventHandlers;

#define DISCORD_REPLY_NO 0
#define DISCORD_REPLY_YES 1
#define DISCORD_REPLY_IGNORE 2

#define DISCORD_PARTY_PRIVATE 0
#define DISCORD_PARTY_PUBLIC 1

#define DISCORD_ACTIVITY_ACTION_TYPE_JOIN 1
#define DISCORD_ACTIVITY_ACTION_TYPE_SPECTATE 2

#define DISCORD_ACTIVITY_TYPE_PLAYING 0
#define DISCORD_ACTIVITY_TYPE_STREAMING 1
#define DISCORD_ACTIVITY_TYPE_LISTENING 2
#define DISCORD_ACTIVITY_TYPE_WATCHING 3
#define DISCORD_ACTIVITY_TYPE_CUSTOM 4
#define DISCORD_ACTIVITY_TYPE_COMPETING 5

DISCORD_EXPORT void Discord_Initialize(const char* applicationId,
                                       DiscordEventHandlers* handlers,
                                       int autoRegister,
                                       const char* optionalSteamId);
DISCORD_EXPORT void Discord_Shutdown(void);

/* checks for incoming messages, dispatches callbacks */
DISCORD_EXPORT void Discord_RunCallbacks(void);

/* If you disable the lib starting its own io thread, you'll need to call this from your own */
#ifdef DISCORD_DISABLE_IO_THREAD
DISCORD_EXPORT void Discord_UpdateConnection(void);
#endif

DISCORD_EXPORT void Discord_UpdatePresence(const DiscordRichPresence* presence);
DISCORD_EXPORT void Discord_ClearPresence(void);

DISCORD_EXPORT void Discord_Respond(const char* userid, /* DISCORD_REPLY_ */ int reply);

DISCORD_EXPORT void Discord_AcceptInvite(const char* userId,
                                         /* DISCORD_ACTIVITY_ACTION_TYPE_ */ int8_t type,
                                         const char* sessionId,
                                         const char* channelId,
                                         const char* messageId);

DISCORD_EXPORT void Discord_OpenActivityInvite(/* DISCORD_ACTIVITY_ACTION_TYPE_ */ int8_t type);
DISCORD_EXPORT void Discord_OpenGuildInvite(const char* code);

DISCORD_EXPORT void Discord_UpdateHandlers(DiscordEventHandlers* handlers);

#ifdef __cplusplus
} /* extern "C" */
#endif
