/*
    This file is part of CrabEmu.

    Copyright (C) 2005, 2006, 2007, 2008, 2009, 2010, 2012, 2014,
                  2016 Lawrence Sebald

    CrabEmu is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License version 2
    as published by the Free Software Foundation.

    CrabEmu is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with CrabEmu; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

#ifdef _arch_dreamcast
#include <inttypes.h>
#include <kos/fs.h>
#include <dc/vmufs.h>
#include <dc/vmu_pkg.h>
#include <dc/maple.h>
#include <zlib/zlib.h>
#include "icon.h"
#endif

#include "sms.h"
#include "smsvdp.h"
#include "smsmem.h"
#include "smsmem-gg.h"
#include "smsz80.h"
#include "sn76489.h"
#include "ym2413.h"
#include "sound.h"
#include "cheats.h"
#include "sdscterminal.h"
#include "console.h"

uint16 sms_pad = 0xFFFF;
int sms_psg_enabled = 1;
int sms_ym2413_enabled = 1;
sn76489_t psg;
int sms_region = SMS_REGION_EXPORT;
YM2413 *sms_fm = NULL;

uint32 psg_samples[313];

static const float NTSC_Z80_CLOCK = 3579545.0f;
static const int PSG_DIVISOR = 16;
static const int NTSC_FPS = 60;
static const int NTSC_LINES_PER_FRAME = 262;
static const float NTSC_CLOCKS_PER_SAMPLE = 5.073051303855f;

static const float PAL_Z80_CLOCK = 3546893.0f;
static const int PAL_FPS = 50;
static const int PAL_LINES_PER_FRAME = 313;
static const float PAL_CLOCKS_PER_SAMPLE = 5.02677579365f;

extern uint8 sms_gg_regs[7];
extern int sms_bios_active;
extern int sms_control_type[2];
extern uint32 sms_gfxbd_data[2];

static int cycles_run, cycles_to_run, scanline;

#ifndef _arch_dreamcast
static void sms_frame(int);
static void sms_scanline(void);
static void sms_single_step(void);
static void sms_finish_frame(void);
static void sms_finish_scanline(void);
#endif
static int sms_current_scanline(void);
static int sms_cycles_left(void);
static void sms_set_control(int player, int control);

/* Console declaration... */
sms_t sms_cons = {
    {
        CONSOLE_SMS,
        CONSOLE_SMS,
        0,
        &sms_shutdown,
        &sms_reset,
        &sms_soft_reset,
#ifndef _arch_dreamcast
        &sms_frame,
#else
        NULL,
#endif
        &sms_load_state,
        &sms_save_state,
        &sms_write_cartram_to_file,
        &sms_button_pressed,
        &sms_button_released,
        &sms_vdp_framebuffer,
        &sms_vdp_framesize,
        &sms_vdp_activeframe,
        &sms_cheat_write,
#ifndef _arch_dreamcast
        &sms_scanline,
        &sms_single_step,
        &sms_finish_frame,
        &sms_finish_scanline,
#else
        NULL,
        NULL,
        NULL,
        NULL,
#endif
        &sms_current_scanline,
        &sms_cycles_left,
        &sms_set_control
    }
};

int sms_init(int video_system, int region, int borders) {
    int i;
    float tmp;

    if(video_system == SMS_VIDEO_NTSC) {
        tmp = NTSC_Z80_CLOCK / PSG_DIVISOR / NTSC_FPS / NTSC_LINES_PER_FRAME /
              NTSC_CLOCKS_PER_SAMPLE;

        for(i = 0; i < NTSC_LINES_PER_FRAME; ++i) {
            psg_samples[i] = (uint32) (tmp * (i + 1)) -
                             (uint32) (tmp * i);
        }

        /* We end up generating 734 samples per frame @ 44100 Hz, 60fps, but we
           need 735. */
        psg_samples[261] += 1;

        region |= SMS_VIDEO_NTSC;

        sn76489_init(&psg, NTSC_Z80_CLOCK, 44100.0f,
                     SN76489_NOISE_BITS_SMS, SN76489_NOISE_TAPPED_SMS);
        sms_fm = ym2413_init(NTSC_Z80_CLOCK, 44100);
    }
    else {
        tmp = PAL_Z80_CLOCK / PSG_DIVISOR / PAL_FPS / PAL_LINES_PER_FRAME /
             PAL_CLOCKS_PER_SAMPLE;

        for(i = 0; i < PAL_LINES_PER_FRAME; ++i) {
            psg_samples[i] = (uint32) (tmp * (i + 1)) -
                             (uint32) (tmp * i);
        }

        /* We need 882 samples per frame @ 44100 Hz, 50fps. */
        region |= SMS_VIDEO_PAL;

        sn76489_init(&psg, PAL_Z80_CLOCK, 44100.0f,
                     SN76489_NOISE_BITS_SMS, SN76489_NOISE_TAPPED_SMS);
        sms_fm = ym2413_init(PAL_Z80_CLOCK, 44100);
    }

    sms_region = region;

    gui_set_console((console_t *)&sms_cons);

    sms_cheat_init();
    sms_cheat_set_poke_func(NULL);

    sms_mem_init();
    sms_vdp_init(video_system, borders);
    sms_z80_init();

    sound_init(2, video_system);

    sms_sdsc_reset();
    ym2413_reset(sms_fm);
    cycles_run = cycles_to_run = scanline = 0;

    sms_cons._base.initialized = 1;

    return 0;
}

int sms_reset(void) {
    if(sms_cons._base.initialized == 0)
        return 0;

    if(sms_region & SMS_VIDEO_NTSC) {
        sn76489_reset(&psg, NTSC_Z80_CLOCK, 44100.0f,
                      SN76489_NOISE_BITS_SMS, SN76489_NOISE_TAPPED_SMS);
    }
    else {
        sn76489_reset(&psg, PAL_Z80_CLOCK, 44100.0f,
                      SN76489_NOISE_BITS_SMS, SN76489_NOISE_TAPPED_SMS);
    }

    ym2413_reset(sms_fm);

    sound_reset_buffer();

    sms_cheat_reset();

    sms_mem_shutdown();
    sms_mem_init();

    sms_z80_reset();
    sms_vdp_reset();

    sms_sdsc_reset();

    cycles_run = cycles_to_run = scanline = 0;

    return 0;
}

int sms_soft_reset(void) {
    if(sms_cons._base.initialized == 0)
        return 0;

    ym2413_reset(sms_fm);

    sound_reset_buffer();

    sms_mem_reset();
    sms_z80_reset();
    sms_vdp_reset();

    sms_sdsc_reset();

    cycles_run = cycles_to_run = scanline = 0;

    return 0;
}

int sms_shutdown(void) {
    sms_cheat_shutdown();
    sms_mem_shutdown();
    sms_vdp_shutdown();
    sms_z80_shutdown();
    ym2413_shutdown(sms_fm);
    sound_shutdown();

    /* Reset a few things in case we reinit later. */
    sms_pad = 0xFFFF;
    sms_cons._base.initialized = 0;
    sms_cons._base.console_type = CONSOLE_SMS;

    return 0;
}

#ifndef _arch_dreamcast
static __INLINE__ int update_sound(int16 buf[], int start, int line) {
    int16 fmbuf[16];    /* More than we'll need, but meh. */
    int16 tmp;
    uint32 i;

    if(sms_psg_enabled)
        sn76489_execute_samples(&psg, buf + start, psg_samples[line]);
    else
        memset(buf + start, 0, psg_samples[line] << 2);

    if(sms_ym2413_enabled) {
        ym2413_update(sms_fm, fmbuf, psg_samples[line]);

        /* Mix in the FM unit's samples */
        for(i = 0; i < psg_samples[line]; ++i) {
            tmp = (fmbuf[i << 1] + fmbuf[(i << 1) + 1]);
            buf[(i << 1) + start] += tmp;
            buf[(i << 1) + 1 + start] += tmp;
        }
    }

    return start + (psg_samples[line] << 1);
}

static void sms_frame(int skip) {
    int16 buf[882 << 1];
    int samples = 0, total_lines, line;

    if(sms_region & SMS_VIDEO_NTSC)
        total_lines = NTSC_LINES_PER_FRAME;
    else
        total_lines = PAL_LINES_PER_FRAME;

    for(line = 0; line < total_lines; ++line) {
        cycles_to_run += SMS_CYCLES_PER_LINE;
        sms_cheat_frame();

        cycles_run += sms_vdp_execute(line, skip);
        cycles_run += sms_z80_run(cycles_to_run - cycles_run);

        samples = update_sound(buf, samples, line);
    }

    sound_update_buffer(buf, samples << 1);

    /* Reset the state for the next frame. */
    cycles_run -= cycles_to_run;
    cycles_to_run = 0;
    scanline = 0;
}

static void sms_scanline(void) {
    int16 buf[882 << 1];
    int total_lines, samples = 0;

    cycles_to_run += SMS_CYCLES_PER_LINE;
    sms_cheat_frame();

    /* Run the VDP and Z80 for the whole line. */
    cycles_run += sms_vdp_execute(scanline, 0);
    cycles_run += sms_z80_run(cycles_to_run - cycles_run);

    samples = update_sound(buf, 0, scanline);
    sound_update_buffer(buf, samples << 1);

    /* See if we hit the end of a frame by running this scanline. */
    if(sms_region & SMS_VIDEO_NTSC)
        total_lines = NTSC_LINES_PER_FRAME;
    else
        total_lines = PAL_LINES_PER_FRAME;

    if(++scanline == total_lines) {
        /* Reset the state for the next frame. */
        cycles_run -= cycles_to_run;
        cycles_to_run = 0;
        scanline = 0;
    }
}

static void sms_single_step(void) {
    int16 buf[882 << 1];
    int total_lines, run;

    /* If we're at the start of a frame, set things up for the first line. Also,
       if we finished a line last time (or are starting a new frame), run the
       VDP for the line. */
    if(!cycles_to_run || cycles_run >= cycles_to_run) {
        cycles_to_run += SMS_CYCLES_PER_LINE;
        sms_cheat_frame();
        if((run = sms_vdp_execute(scanline, 0))) {
            cycles_run += run;
            return;
        }
    }

    /* Run our one instruction. */
    cycles_run += sms_z80_run(1);

    /* Did we finish a line? */
    if(cycles_run >= cycles_to_run) {
        run = update_sound(buf, 0, scanline);
        sound_update_buffer(buf, run << 1);

        /* Was it the last line in the frame? */
        if(sms_region & SMS_VIDEO_NTSC)
            total_lines = NTSC_LINES_PER_FRAME;
        else
            total_lines = PAL_LINES_PER_FRAME;

        if(++scanline == total_lines) {
            /* Reset the state for the next frame. */
            cycles_run -= cycles_to_run;
            cycles_to_run = 0;
            scanline = 0;
        }
    }
}

static void sms_finish_frame(void) {
    int16 buf[882 << 1];
    int samples = 0, total_lines, line;

    if(sms_region & SMS_VIDEO_NTSC)
        total_lines = NTSC_LINES_PER_FRAME;
    else
        total_lines = PAL_LINES_PER_FRAME;

    for(line = scanline; line < total_lines; ++line) {
        cycles_to_run += SMS_CYCLES_PER_LINE;
        sms_cheat_frame();

        cycles_run += sms_vdp_execute(line, 0);
        cycles_run += sms_z80_run(cycles_to_run - cycles_run);

        samples = update_sound(buf, samples, line);
    }

    sound_update_buffer(buf, samples << 1);

    /* Reset the state for the next frame. */
    cycles_run -= cycles_to_run;
    cycles_to_run = 0;
    scanline = 0;
}

static void sms_finish_scanline(void) {
    int16 buf[882 << 1];
    int total_lines, samples = 0;

    /* Make sure we have something to do. */
    if(cycles_run >= cycles_to_run)
        return;
    
    /* Run the Z80 for the rest of the line. The VDP should've already been
       run. */
    cycles_run += sms_z80_run(cycles_to_run - cycles_run);

    samples = update_sound(buf, 0, scanline);
    sound_update_buffer(buf, samples << 1);

    /* See if we hit the end of a frame by finishing this line. */
    if(sms_region & SMS_VIDEO_NTSC)
        total_lines = NTSC_LINES_PER_FRAME;
    else
        total_lines = PAL_LINES_PER_FRAME;

    if(++scanline == total_lines) {
        /* Reset the state for the next frame. */
        cycles_run -= cycles_to_run;
        cycles_to_run = 0;
        scanline = 0;
    }
}

#endif

static void sms_set_control(int player, int control) {
    /* Verify what we got from the ui... */
    if(player < 0 || player > 1)
        return;

    if(control < SMS_PADTYPE_NONE || control > SMS_PADTYPE_GFX_BOARD)
        return;

    /* Set the control type. */
    sms_control_type[player] = control;
}

void sms_button_pressed(int player, int button) {
    uint16 mask = 0;

    if(player < 1 || player > 2)
        return;

    if(sms_control_type[player - 1] == SMS_PADTYPE_CONTROL_PAD) {
        if(button < SMS_UP || button > SMS_CONSOLE_RESET || button == SMS_QUIT)
            return;

        switch(button) {
            case SMS_UP:
            case SMS_DOWN:
            case SMS_LEFT:
            case SMS_RIGHT:
            case SMS_BUTTON_1:
            case SMS_BUTTON_2:
                mask = (player == 1) ? (1 << button) : (1 << (button + 6));
                break;

            case SMS_CONSOLE_RESET:
                mask = SMS_RESET;
                break;

            case GAMEGEAR_START:
                if(sms_cons._base.console_type == CONSOLE_GG) {
                    sms_gg_regs[0] &= 0x7F;
                }
                else if(sms_cons._base.console_type == CONSOLE_SMS) {
                    sms_z80_nmi();
                }
                return;
        }

        /* Update the pad */
        sms_pad &= ~mask;
    }
    else if(sms_control_type[player - 1] == SMS_PADTYPE_GFX_BOARD) {
        switch(button) {
            case SMS_GFXBD_1:
            case SMS_GFXBD_2:
            case SMS_GFXBD_3:
                sms_gfxbd_data[player - 1] &= ~(1 << button);
                break;

            case SMS_CONSOLE_RESET:
                sms_pad &= ~SMS_RESET;
                break;

            case GAMEGEAR_START:
                if(sms_cons._base.console_type == CONSOLE_GG)
                    sms_gg_regs[0] &= 0x7F;
                else if(sms_cons._base.console_type == CONSOLE_SMS)
                    sms_z80_nmi();
                break;
        }
    }
}

void sms_button_released(int player, int button) {
    uint16 mask = 0;

    if(player < 1 || player > 2)
        return;

    if(sms_control_type[player - 1] == SMS_PADTYPE_CONTROL_PAD) {
        if(button < SMS_UP || button > SMS_CONSOLE_RESET || button == SMS_QUIT)
            return;

        switch(button) {
            case SMS_UP:
            case SMS_DOWN:
            case SMS_LEFT:
            case SMS_RIGHT:
            case SMS_BUTTON_1:
            case SMS_BUTTON_2:
                mask = (player == 1) ? (1 << button) : (1 << (button + 6));
                break;

            case SMS_CONSOLE_RESET:
                mask = SMS_RESET;
                break;

            case GAMEGEAR_START:
                if(sms_cons._base.console_type == CONSOLE_GG) {
                    sms_gg_regs[0] |= 0x80;
                }
                return;
        }

        /* Update the pad */
        sms_pad |= mask;
    }
    else if(sms_control_type[player - 1] == SMS_PADTYPE_GFX_BOARD) {
        switch(button) {
            case SMS_GFXBD_1:
            case SMS_GFXBD_2:
            case SMS_GFXBD_3:
                sms_gfxbd_data[player - 1] |= (1 << button);
                break;

            case SMS_CONSOLE_RESET:
                sms_pad |= SMS_RESET;
                break;

            case GAMEGEAR_START:
                if(sms_cons._base.console_type == CONSOLE_GG)
                    sms_gg_regs[0] |= 0x80;
                break;
        }
    }
}

void sms_set_console(int console) {
    switch(console) {
        case CONSOLE_SMS:
            gui_set_aspect(4.0f, 3.0f);
            psg.noise_tapped = SN76489_NOISE_TAPPED_SMS;
            psg.noise_bits = SN76489_NOISE_BITS_SMS;
            psg.noise_shift = (1 << (SN76489_NOISE_BITS_SMS - 1));
            sms_z80_set_pread(&sms_port_read);
            sms_z80_set_pwrite(&sms_port_write);
            break;

        case CONSOLE_GG:
            gui_set_aspect(10.0f, 9.0f);
            psg.noise_tapped = SN76489_NOISE_TAPPED_SMS;
            psg.noise_bits = SN76489_NOISE_BITS_SMS;
            psg.noise_shift = (1 << (SN76489_NOISE_BITS_SMS - 1));
            sms_z80_set_pread(&sms_gg_port_read);
            sms_z80_set_pwrite(&sms_gg_port_write);
            break;

        case CONSOLE_SG1000:
        case CONSOLE_SC3000:
            gui_set_aspect(4.0f, 3.0f);
            psg.noise_tapped = SN76489_NOISE_TAPPED_SG1000;
            psg.noise_bits = SN76489_NOISE_BITS_SG1000;
            psg.noise_shift = (1 << (SN76489_NOISE_BITS_SG1000 - 1));
            sms_z80_set_pread(&sms_port_read);
            sms_z80_set_pwrite(&sms_port_write);
            break;

        default:
            return;
    }

    sms_cons._base.console_type = console;
}

static int sms_current_scanline(void) {
    return scanline;
}

static int sms_cycles_left(void) {
    return cycles_to_run - cycles_run;
}

int sms_cycles_elapsed(void) {
    return cycles_run + sms_z80_get_cycles();
}

static void sms_psg_read_context_v1(FILE *fp) {
    uint8 byte[2];
    int i;
    uint16 counter;

    fread(psg.volume, 4, 1, fp);

    for(i = 0; i < 3; ++i) {
        fread(&byte, 2, 1, fp);
        psg.tone[i] = byte[0] | (byte[1] << 8);
    }

    fread(&psg.noise, 1, 1, fp);
    fread(psg.tone_state, 4, 1, fp);
    fread(&psg.latched_reg, 1, 1, fp);

    for(i = 0; i < 4; ++i) {
        fread(&byte, 2, 1, fp);
        counter = byte[0] | (byte[1] << 8);
        psg.counter[i] = counter;
    }
}

int sms_psg_write_context(FILE *fp) {
    uint8 data[4];
    int i;
    uint32 tmp;

    data[0] = 'P';
    data[1] = 'S';
    data[2] = 'G';
    data[3] = '\0';
    fwrite(data, 1, 4, fp);             /* Block ID */

    UINT32_TO_BUF(56, data);
    fwrite(data, 1, 4, fp);             /* Length */

    UINT16_TO_BUF(1, data);
    fwrite(data, 1, 2, fp);             /* Version */
    fwrite(data, 1, 2, fp);             /* Flags (Importance = 1) */

    data[0] = data[1] = data[2] = data[3] = 0;
    fwrite(data, 1, 4, fp);             /* Child pointer */

    memcpy(data, psg.volume, 4);
    fwrite(data, 1, 4, fp);

    for(i = 0; i < 3; ++i) {
        UINT16_TO_BUF(psg.tone[i], data);
        fwrite(data, 1, 2, fp);
    }

    data[0] = psg.noise;
    data[1] = psg.latched_reg;
    fwrite(data, 1, 2, fp);

    memcpy(data, psg.tone_state, 4);
    fwrite(data, 1, 4, fp);

    for(i = 0; i < 4; ++i) {
        tmp = *((uint32 *)&psg.counter[i]);
        UINT32_TO_BUF(tmp, data);
        fwrite(data, 1, 4, fp);
    }

    UINT16_TO_BUF(psg.noise_shift, data);
    fwrite(data, 1, 2, fp);

    UINT16_TO_BUF(psg.noise_bits, data);
    fwrite(data, 1, 2, fp);

    UINT16_TO_BUF(psg.noise_tapped, data);
    fwrite(data, 1, 2, fp);

    data[0] = data[1] = 0;
    fwrite(data, 1, 2, fp);

    return 0;
}

int sms_psg_read_context(const uint8 *buf) {
    uint32 len, tmp;
    uint16 ver;
    int i;

    /* Check the size */
    BUF_TO_UINT32(buf + 4, len);
    if(len != 56)
        return -1;

    /* Check the version number */
    BUF_TO_UINT16(buf + 8, ver);
    if(ver != 1)
        return -1;

    /* Check the child pointer */
    if(buf[12] != 0 || buf[13] != 0 || buf[14] != 0 || buf[15] != 0)
        return -1;

    /* Copy in the registers */
    memcpy(psg.volume, buf + 16, 4);

    for(i = 0; i < 3; ++i) {
        BUF_TO_UINT16(buf + 20 + (i << 1), psg.tone[i]);
    }

    psg.noise = buf[26];
    psg.latched_reg = buf[27];
    memcpy(psg.tone_state, buf + 28, 4);

    for(i = 0; i < 4; ++i) {
        BUF_TO_UINT32(buf + 32 + (i << 2), tmp);
        *((uint32 *)&psg.counter[i]) = tmp;
    }

    BUF_TO_UINT16(buf + 48, psg.noise_shift);
    BUF_TO_UINT16(buf + 50, psg.noise_bits);
    BUF_TO_UINT16(buf + 52, psg.noise_tapped);

    return 0;
}

#ifdef _arch_dreamcast
static int sms_save_state_int(const char *filename)
#else
int sms_save_state(const char *filename)
#endif
{
    FILE *fp;
    uint8 data[4];

    if(sms_cons._base.initialized == 0)
        /* This shouldn't happen.... */
        return -1;

    /* Don't let users do this while the bios is running... */
    if(sms_bios_active)
        return -42;

    fp = fopen(filename, "wb");
    if(!fp)
        return -1;

    fprintf(fp, "CrabEmu Save State");

    /* Write save state version */
    data[0] = 0x00;
    data[1] = 0x02;
    fwrite(data, 1, 2, fp);

    /* Write out the Console Metadata block */
    data[0] = 'C';
    data[1] = 'O';
    data[2] = 'N';
    data[3] = 'S';
    fwrite(data, 1, 4, fp);             /* Block ID */

    UINT32_TO_BUF(24, data);
    fwrite(data, 1, 4, fp);             /* Length */

    UINT16_TO_BUF(1, data);
    fwrite(data, 1, 2, fp);             /* Version */
    fwrite(data, 1, 2, fp);             /* Flags (Importance = 1) */

    data[0] = data[1] = data[2] = data[3] = 0;
    fwrite(data, 1, 4, fp);             /* Child pointer */
    fwrite(data, 1, 4, fp);             /* Console (0 = SMS) */

    data[0] = sms_cons._base.console_type;  /* Console sub-type */
    data[1] = sms_region & 0x0F;            /* Region code */
    data[2] = sms_region >> 4;              /* Video system */
    data[3] = 0;                            /* Reserved */
    fwrite(data, 1, 4, fp);

    /* Write each block's state */
    if(sms_game_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_z80_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_psg_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_vdp_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_mem_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_ym2413_write_context(fp)) {
        fclose(fp);
        return -1;
    }

    fclose(fp);
    return 0;
}

#ifdef _arch_dreamcast
int sms_save_state(const char *filename) {
    char tmpfn[4096];
    int rv;
    uint32 crc, adler;
    uint8 *buf, *buf2;
    FILE *fp;
    long len;
    uLong clen;
    vmu_pkg_t pkg;
    uint8 *pkg_out;
    int pkg_size;
    maple_device_t *vmu;
    file_t f;
    int blocks_freed = 0;

    /* Make sure there's a VMU in port A1. */
    if(!(vmu = maple_enum_dev(0, 1))) {
        return -100;
    }

    if(!vmu->valid || !(vmu->info.functions & MAPLE_FUNC_MEMCARD)) {
        return -100;
    }

    sprintf(tmpfn, "/ram/%s", filename);
    rv = sms_save_state_int(tmpfn);

    if(rv)
        return rv;

    /* Read in the uncompressed save state */
    fp = fopen(tmpfn, "rb");
    if(!fp) {
        fs_unlink(tmpfn);
        return -1;
    }

    fseek(fp, 0, SEEK_END);
    len = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    if(!(buf = (uint8 *)malloc(len))) {
        fclose(fp);
        fs_unlink(tmpfn);
        return -1;
    }

    fread(buf, 1, len, fp);
    fclose(fp);

    fs_unlink(tmpfn);

    /* Create a compressed version */
    clen = len * 2;

    if(!(buf2 = (uint8 *)malloc(clen + 8))) {
        free(buf);
        return -1;
    }

    if(compress2(buf2 + 8, &clen, buf, len, 9) != Z_OK) {
        free(buf2);
        free(buf);
        return -1;
    }

    /* Clean up the old buffer and save the length of the uncompressed data into
       the new buffer */
    free(buf);
    *((uint32 *)buf2) = (uint32)len;
    *(((uint32 *)buf2) + 1) = (uint32)clen;

    /* Make the VMU save */
    sms_get_checksums(&crc, &adler);
    sprintf(tmpfn, "/vmu/a1/ss-%08" PRIX32, (uint32_t)crc);

    if(filename != NULL) {
        strncpy(pkg.desc_long, filename, 32);
        pkg.desc_long[31] = 0;
    }
    else {
        sprintf(pkg.desc_long, "CRC: %08" PRIX32 " Adler: %08" PRIX32,
                (uint32_t)crc, (uint32_t)adler);
    }

    strcpy(pkg.desc_short, "CrabEmu State");
    strcpy(pkg.app_id, "CrabEmu");
    pkg.icon_cnt = 1;
    pkg.icon_anim_speed = 0;
    memcpy(pkg.icon_pal, icon_pal, 32);
    pkg.icon_data = icon_img;
    pkg.eyecatch_type = VMUPKG_EC_NONE;
    pkg.data_len = clen + 4;
    pkg.data = buf2;

    vmu_pkg_build(&pkg, &pkg_out, &pkg_size);

    /* See if a file exists with that name, since we'll overwrite it. */
    f = fs_open(tmpfn, O_RDONLY);
    if(f != FILEHND_INVALID) {
        blocks_freed = fs_total(f) >> 9;
        fs_close(f);
    }

    /* Make sure there's enough free space on the VMU. */
    if(vmufs_free_blocks(vmu) + blocks_freed < (pkg_size >> 9)) {
        free(pkg_out);
        free(buf2);
        return pkg_size >> 9;
    }

    if(!(fp = fopen(tmpfn, "wb"))) {
        free(pkg_out);
        free(buf2);
        return -1;
    }

    if(fwrite(pkg_out, 1, pkg_size, fp) != (size_t)pkg_size)
        rv = -1;

    fclose(fp);

    free(pkg_out);
    free(buf2);

    return rv;
}
#endif

static int sms_cons_read_context(const uint8 *buf) {
    uint32 len, cons;
    uint16 ver;
    int vid, region;

    /* Check the size */
    BUF_TO_UINT32(buf + 4, len);
    if(len != 24)
        return -1;

    /* Check the version number */
    BUF_TO_UINT16(buf + 8, ver);
    if(ver != 1)
        return -1;

    /* Check the child pointer */
    if(buf[12] != 0 || buf[13] != 0 || buf[14] != 0 || buf[15] != 0)
        return -1;

    /* Read the console type to make sure its sane */
    BUF_TO_UINT32(buf + 16, cons);
    if(cons != 0)
        return -1;

    if(buf[20] != sms_cons._base.console_type)
        return -1;

    region = buf[21] == 1 ? SMS_REGION_DOMESTIC : SMS_REGION_EXPORT;
    vid = buf[22] == 1 ? SMS_VIDEO_NTSC : SMS_VIDEO_PAL;

    if(sms_region != (region | vid))
        return -1;

    return 0;
}

static int sms_load_state_v2(FILE *fp) {
    uint8 buf[4];
    int rv;
    uint32 fourcc, len;
    uint16 flags;
    uint8 *ptr;
    size_t read;

    for(;;) {
        rv = 0;

        /* Read in the fourcc */
        read = fread(buf, 1, 4, fp);
        if(!read)
            break;
        else if(read != 4)
            return -1;

        BUF_TO_UINT32(buf, fourcc);

        /* Read in the length */
        if(fread(buf, 1, 4, fp) != 4)
            return -1;

        BUF_TO_UINT32(buf, len);

        /* Check for a malformed block */
        if(len < 16)
            return -1;

        /* Allocate space for the block and read it in. */
        if(!(ptr = (uint8 *)malloc(len)))
            return -1;
        UINT32_TO_BUF(fourcc, ptr);
        UINT32_TO_BUF(len, ptr + 4);

        if(fread(ptr + 8, 1, len - 8, fp) != len - 8) {
            free(ptr);
            return -1;
        }

        switch(fourcc) {
            case FOURCC_TO_UINT32('C', 'O', 'N', 'S'):
                rv = sms_cons_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('G', 'A', 'M', 'E'):
                rv = sms_game_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('Z', '8', '0', '\0'):
                rv = sms_z80_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('P', 'S', 'G', '\0'):
                rv = sms_psg_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('9', '9', '1', '8'):
                rv = sms_vdp_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('D', 'R', 'A', 'M'):
                rv = sms_mem_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('G', 'G', 'R', 'G'):
                rv = sms_ggregs_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('S', 'M', 'S', 'R'):
                rv = sms_regs_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('M', 'A', 'P', 'R'):
                rv = sms_mapper_read_context(ptr);
                break;

            case FOURCC_TO_UINT32('2', '4', '1', '3'):
                rv = sms_ym2413_read_context(ptr);
                break;

            default:
                /* See if its marked as essential... */
                BUF_TO_UINT16(ptr + 10, flags);
                if(flags & 1) {
                    rv = -1;
#ifdef DEBUG
                    printf("Unknown block %c%c%c%c, bailing out!\n", ptr[0],
                           ptr[1], ptr[2], ptr[3]);
#endif
                }
                else {
#ifdef DEBUG
                    printf("Ignoring unknown block %c%c%c%c\n", ptr[0], ptr[1],
                           ptr[2], ptr[3]);
#endif
                }
        }

        /* Clean up this pass */
        free(ptr);

        if(rv)
            return rv;
    }

    sms_pad = 0xFFFF;

    return 0;
}

#ifdef _arch_dreamcast
static int sms_load_state_int(const char *filename)
#else
int sms_load_state(const char *filename)
#endif
{
    char str[19];
    FILE *fp;
    char byte;

    if(sms_cons._base.initialized == 0) {
        /* This shouldn't happen.... */
        return -1;
    }

    fp = fopen(filename, "rb");
    if(!fp)
        return -1;

    fread(str, 18, 1, fp);
    str[18] = 0;
    if(strcmp("CrabEmu Save State", str)) {
        fclose(fp);
        return -2;
    }

    /* Read save state version */
    fread(&byte, 1, 1, fp);
    if(byte != 0x00) {
        fclose(fp);
        return -2;
    }

    fread(&byte, 1, 1, fp);

    if(byte == 0x01) {
        /* Read in the current Z80 context */
        sms_z80_read_context_v1(fp);

        /* Next, read the current VDP state */
        sms_vdp_read_context_v1(fp);

        /* Now, read the current PSG state */
        sms_psg_read_context_v1(fp);

        /* Finally, read the current memory contents from the file */
        sms_mem_read_context_v1(fp);
    }
    else if(byte == 0x02) {
        if(sms_load_state_v2(fp))
            return -1;
    }
    else {
        /* Unknown version... */
        fclose(fp);
        return -2;
    }

    fclose(fp);

    sound_reset_buffer();

    return 0;
}

#ifdef _arch_dreamcast
int sms_load_state(const char *filename __UNUSED__) {
    vmu_pkg_t pkg;
    uint8 *pkg_out, *raw;
    int pkg_size;
    FILE *fp;
    char savename[32];
    uint32 real_size;
    uint32 crc, adler;
    int rv;

    /* Grab the checksums and build the filename */
    sms_get_checksums(&crc, &adler);
    sprintf(savename, "/vmu/a1/ss-%08" PRIX32, (uint32_t)crc);

    /* Read the file in and grab the uncompressed length */
    if(!(fp = fopen(savename, "rb")))
        return -1;

    fseek(fp, 0, SEEK_END);
    pkg_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    if(!(pkg_out = (uint8 *)malloc(pkg_size)))
        return -1;

    fread(pkg_out, pkg_size, 1, fp);
    fclose(fp);

    vmu_pkg_parse(pkg_out, &pkg);
    real_size = *((uint32 *)pkg.data);
    pkg_size = *(((uint32 *)pkg.data) + 1);

    /* Uncompress the data and write it out to a /ram file */
    if(!(raw = (uint8 *)malloc(real_size))) {
        free(pkg_out);
        return -1;
    }

    uncompress(raw, &real_size, ((uint8 *)pkg.data) + 8, pkg.data_len - 8);
    free(pkg_out);

    sprintf(savename, "/ram/cs-%08" PRIX32, (uint32_t)crc);
    if(!(fp = fopen(savename, "wb"))) {
        free(raw);
        return -1;
    }

    fwrite(raw, 1, real_size, fp);
    fclose(fp);
    free(raw);

    rv = sms_load_state_int(savename);
    fs_unlink(savename);

    return rv;
}
#endif

int sms_write_state(FILE *fp)
{
    uint8 data[4];

    if(sms_cons._base.initialized == 0)
    /* This shouldn't happen.... */
        return -1;

    /* Don't let users do this while the bios is running... */
    if(sms_bios_active)
        return -42;

    if(!fp)
        return -1;

    fprintf(fp, "CrabEmu Save State");

    /* Write save state version */
    data[0] = 0x00;
    data[1] = 0x02;
    fwrite(data, 1, 2, fp);

    /* Write out the Console Metadata block */
    data[0] = 'C';
    data[1] = 'O';
    data[2] = 'N';
    data[3] = 'S';
    fwrite(data, 1, 4, fp);             /* Block ID */

    UINT32_TO_BUF(24, data);
    fwrite(data, 1, 4, fp);             /* Length */

    UINT16_TO_BUF(1, data);
    fwrite(data, 1, 2, fp);             /* Version */
    fwrite(data, 1, 2, fp);             /* Flags (Importance = 1) */

    data[0] = data[1] = data[2] = data[3] = 0;
    fwrite(data, 1, 4, fp);             /* Child pointer */
    fwrite(data, 1, 4, fp);             /* Console (0 = SMS) */

    data[0] = sms_cons._base.console_type;  /* Console sub-type */
    data[1] = sms_region & 0x0F;            /* Region code */
    data[2] = sms_region >> 4;              /* Video system */
    data[3] = 0;                            /* Reserved */
    fwrite(data, 1, 4, fp);

    /* Write each block's state */
    if(sms_game_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_z80_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_psg_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_vdp_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_mem_write_context(fp)) {
        fclose(fp);
        return -1;
    }
    else if(sms_ym2413_write_context(fp)) {
        fclose(fp);
        return -1;
    }

    fclose(fp);
    return 0;
}

int sms_read_state(FILE *fp)
{
    char str[19];
    char byte;

    if(sms_cons._base.initialized == 0) {
        /* This shouldn't happen.... */
        return -1;
    }

    if(!fp)
        return -1;

    fread(str, 18, 1, fp);
    str[18] = 0;
    if(strcmp("CrabEmu Save State", str)) {
        fclose(fp);
        return -2;
    }

    /* Read save state version */
    fread(&byte, 1, 1, fp);
    if(byte != 0x00) {
        fclose(fp);
        return -2;
    }

    fread(&byte, 1, 1, fp);

    if(byte == 0x01) {
        /* Read in the current Z80 context */
        sms_z80_read_context_v1(fp);
        
        /* Next, read the current VDP state */
        sms_vdp_read_context_v1(fp);
        
        /* Now, read the current PSG state */
        sms_psg_read_context_v1(fp);
        
        /* Finally, read the current memory contents from the file */
        sms_mem_read_context_v1(fp);
    }
    else if(byte == 0x02) {
        if(sms_load_state_v2(fp))
            return -1;
    }
    else {
        /* Unknown version... */
        fclose(fp);
        return -2;
    }

    fclose(fp);

    sound_reset_buffer();

    return 0;
}
