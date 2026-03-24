/*
    This is a simple example in C of using the rich presence API asynchronously.
*/

#define _CRT_SECURE_NO_WARNINGS /* thanks Microsoft */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "discord_rpc.h"

static const char* APPLICATION_ID = "345229890980937739";
static int FrustrationLevel = 0;
static int64_t StartTime;
static char SendPresence = 1;
static char SendButtons = 0;
static char Debug = 1;

static int prompt(char* line, size_t size)
{
    int res;
    char* nl;
    printf("\n> ");
    fflush(stdout);
    res = fgets(line, (int)size, stdin) ? 1 : 0;
    line[size - 1] = 0;
    nl = strchr(line, '\n');
    if (nl) {
        *nl = 0;
    }
    return res;
}

static void updateDiscordPresence()
{
    if (SendPresence) {
        char buffer[256];
        DiscordRichPresence discordPresence;
        memset(&discordPresence, 0, sizeof(discordPresence));
        discordPresence.state = "West of House";
        sprintf(buffer, "Frustration level: %d", FrustrationLevel);
        discordPresence.details = buffer;
        discordPresence.startTimestamp = StartTime;
        discordPresence.endTimestamp = time(0) + 5 * 60;
        discordPresence.largeImageKey = "canary-large";
        discordPresence.smallImageKey = "ptb-small";
        discordPresence.partyId = "party1234";
        discordPresence.partySize = 1;
        discordPresence.partyMax = 6;
        discordPresence.partyPrivacy = DISCORD_PARTY_PUBLIC;
        discordPresence.matchSecret = "xyzzy";
        discordPresence.joinSecret = "join";
        discordPresence.spectateSecret = "look";
        discordPresence.instance = 0;

        DiscordButton buttons[] = {
          {.label = "Test", .url = "https://example.com"},
          {.label = "Test 2", .url = "https://discord.gg/fortnite"},
          {0, 0},
        };

        if (SendButtons) {
            discordPresence.buttons = buttons;
        }

        Discord_UpdatePresence(&discordPresence);
    }
    else {
        Discord_ClearPresence();
    }
}

static void handleDiscordReady(const DiscordUser* connectedUser)
{
    if (!connectedUser->discriminator[0] || strcmp(connectedUser->discriminator, "0") == 0) {
        printf("\nDiscord: connected to user @%s (%s) - %s\n",
               connectedUser->username,
               connectedUser->globalName,
               connectedUser->userId);
    }
    else {
        printf("\nDiscord: connected to user %s#%s (%s) - %s\n",
               connectedUser->username,
               connectedUser->discriminator,
               connectedUser->globalName,
               connectedUser->userId);
    }
}

static void handleDiscordDisconnected(int errcode, const char* message)
{
    printf("\nDiscord: disconnected (%d: %s)\n", errcode, message);
}

static void handleDiscordError(int errcode, const char* message)
{
    printf("\nDiscord: error (%d: %s)\n", errcode, message);
}

static void handleDebug(char isOut,
                        const char* opcodeName,
                        const char* message,
                        uint32_t messageLength)
{
    unsigned int len = (messageLength > 7 ? messageLength : 7) + 6 + 7 + 7 + 1;
    char* buf = (char*)malloc(len);
    char* direction = isOut ? "send" : "receive";
    if (!messageLength || !message || !message[0]) {
        snprintf(buf, len, "[%s] [%s] <empty>", direction, opcodeName);
    }
    else {
        int written = snprintf(buf, len, "[%s] [%s] ", direction, opcodeName);
        int remaining = len - written;
        int toWrite = remaining > (messageLength + 1) ? (messageLength + 1) : remaining;
        int written2 = snprintf(buf + written, toWrite, message);
    }
    printf("[DEBUG] %s\n", buf);
    free(buf);
}

static void handleDiscordJoin(const char* secret)
{
    printf("\nDiscord: join (%s)\n", secret);
}

static void handleDiscordSpectate(const char* secret)
{
    printf("\nDiscord: spectate (%s)\n", secret);
}

static void handleDiscordJoinRequest(const DiscordUser* request)
{
    int response = -1;
    char yn[4];
    printf("\nDiscord: join request from %s#%s - %s\n",
           request->username,
           request->discriminator,
           request->userId);
    do {
        printf("Accept? (y/n)");
        if (!prompt(yn, sizeof(yn))) {
            break;
        }

        if (!yn[0]) {
            continue;
        }

        if (yn[0] == 'y') {
            response = DISCORD_REPLY_YES;
            break;
        }

        if (yn[0] == 'n') {
            response = DISCORD_REPLY_NO;
            break;
        }
    } while (1);
    if (response != -1) {
        Discord_Respond(request->userId, response);
    }
}

static void handleDiscordInvited(/* DISCORD_ACTIVITY_ACTION_TYPE_ */ int8_t type,
                                 const DiscordUser* user,
                                 const DiscordRichPresence* activity,
                                 const char* sessionId,
                                 const char* channelId,
                                 const char* messageId)
{
    printf("Received invite type: %i, from user: %s, with activity state: %s, with session id: %s, "
           "from channel id: %s, with message id: %s",
           type,
           user->username,
           activity->state,
           sessionId,
           channelId,
           messageId);

    // Discord_AcceptInvite(user->userId, type, sessionId, channelId, messageId);
}

static void populateHandlers(DiscordEventHandlers* handlers)
{
    memset(handlers, 0, sizeof(handlers));
    handlers->ready = handleDiscordReady;
    handlers->disconnected = handleDiscordDisconnected;
    handlers->errored = handleDiscordError;
    if (Debug)
        handlers->debug = handleDebug;
    handlers->joinGame = handleDiscordJoin;
    handlers->spectateGame = handleDiscordSpectate;
    handlers->joinRequest = handleDiscordJoinRequest;
    handlers->invited = handleDiscordInvited;
}

static void discordUpdateHandlers()
{
    DiscordEventHandlers handlers;
    populateHandlers(&handlers);
    Discord_UpdateHandlers(&handlers);
}

static void discordInit()
{
    DiscordEventHandlers handlers;
    populateHandlers(&handlers);
    Discord_Initialize(APPLICATION_ID, &handlers, 1, NULL);
}

static void gameLoop()
{
    char line[512];
    char* space;

    StartTime = time(0);

    printf("You are standing in an open field west of a white house.\n");
    while (prompt(line, sizeof(line))) {
        if (line[0]) {
            if (line[0] == 'q') {
                break;
            }

            if (line[0] == 't') {
                printf("Shutting off Discord.\n");
                Discord_Shutdown();
                continue;
            }

            if (line[0] == 'y') {
                printf("Reinit Discord.\n");
                discordInit();
                continue;
            }

            if (line[0] == 'c') {
                if (SendPresence) {
                    printf("Clearing presence information.\n");
                    SendPresence = 0;
                }
                else {
                    printf("Restoring presence information.\n");
                    SendPresence = 1;
                }
                updateDiscordPresence();
                continue;
            }

            if (line[0] == 'b') {
                if (SendButtons) {
                    printf("Removing buttons.\n");
                    SendButtons = 0;
                }
                else {
                    printf("Adding buttons.\n");
                    SendButtons = 1;
                }
                updateDiscordPresence();
                continue;
            }

            if (line[0] == 'i' && line[1]) {
                if (line[1] == 'a') {
                    printf("Opening activity invite (type 1).\n");
                    Discord_OpenActivityInvite(1);
                    continue;
                }

                if (line[1] == '2') { // does not seem to work
                    printf("Opening activity invite (type 2).\n");
                    Discord_OpenActivityInvite(2);
                    continue;
                }

                if (line[1] == '0') { // does not seem to work either...
                    printf("Opening activity invite (type 0).\n");
                    Discord_OpenActivityInvite(0);
                    continue;
                }

                if (line[1] == 'g') {
                    printf("Opening guild invite.\n");
                    Discord_OpenGuildInvite("fortnite");
                    continue;
                }
            }

            if (line[0] == 'd') {
                printf("Turning debug %s\n", Debug ? "off" : "on");
                Debug = !Debug;
                discordUpdateHandlers();
                continue;
            }

            if (time(NULL) & 1) {
                printf("I don't understand that.\n");
            }
            else {
                space = strchr(line, ' ');
                if (space) {
                    *space = 0;
                }
                printf("I don't know the word \"%s\".\n", line);
            }

            ++FrustrationLevel;

            updateDiscordPresence();
        }

#ifdef DISCORD_DISABLE_IO_THREAD
        Discord_UpdateConnection();
#endif
        Discord_RunCallbacks();
    }
}

int main(int argc, char* argv[])
{
    discordInit();

    updateDiscordPresence();

    gameLoop();

    Discord_Shutdown();
    return 0;
}
