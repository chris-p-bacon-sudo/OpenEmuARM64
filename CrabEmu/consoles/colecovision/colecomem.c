/*
    This file is part of CrabEmu.

    Copyright (C) 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012,
                  2014, 2015, 2016 Lawrence Sebald

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
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdint.h>

#ifdef DEBUG
#include <inttypes.h>
#endif

#ifdef _arch_dreamcast
#include <zlib/zlib.h>
#include <bzlib/bzlib.h>
#else
#ifndef NO_ZLIB
#include <zlib.h>
#endif

#ifndef NO_BZ2
#include <bzlib.h>
#endif
#endif

#include "colecovision.h"
#include "colecomem.h"
#include "sn76489.h"
#include "smsz80.h"
#include "tms9918a.h"
#include "sms.h"
#include "rom.h"

#ifndef NO_ZLIB
#include "unzip.h"
#endif

static uint8 ram[1024];
static uint8 bios_rom[8192];
static int bios_loaded = 0;
static uint8 *read_map[256];
static uint8 *write_map[256];
static uint8 dummy_arear[256];
static uint8 dummy_areaw[256];

static uint8 *cart_rom = NULL;
static uint32 cart_len = 0;
static uint8 cont_mode = 0;
static uint32 rom_crc, rom_adler;

static uint32 megacart_page = 0;
static uint32 megacart_pages = 0;

extern sn76489_t psg;

uint16 coleco_cont_bits[2];

uint8 coleco_port_read(uint16 port) {
    uint8 tmp;

    switch(port & 0xE0) {
        case 0xA0:
            if(port & 0x01)
                return tms9918a_vdp_status_read();
            else
                return tms9918a_vdp_data_read();

        case 0xE0:
            if(cont_mode == 0)
                tmp = ~((uint8)(coleco_cont_bits[(port & 0x02) >> 1] & 0xFF));
            else
                tmp = ~((uint8)(coleco_cont_bits[(port & 0x02) >> 1] >> 8));

            return tmp & 0x7f;

        default:
            return 0xFF;
    }
}

void coleco_port_write(uint16 port, uint8 data) {
    switch(port & 0xE0) {
        case 0xA0:
            if(port & 0x01)
                tms9918a_vdp_ctl_write(data);
            else
                tms9918a_vdp_data_write(data);
            break;

        case 0x80:
            cont_mode = 0;
            break;

        case 0xC0:
            cont_mode = 1;
            break;

        case 0xE0:
            sn76489_write(&psg, data);
            break;
    }
}

uint8 coleco_mem_read(uint16 addr) {
    if(megacart_pages && addr >= 0xFFC0) {
        int i;

        megacart_page = (addr & (megacart_pages - 1));

        /* Fix the paging... */
        for(i = 0; i < 0x40; ++i) {
            read_map[i + 0xC0] = cart_rom + (megacart_page << 14) + (i << 8);
        }

        sms_z80_set_readmap(read_map);
    }

    return read_map[addr >> 8][addr & 0xFF];
}

void coleco_mem_write(uint16 addr, uint8 data) {
    if(megacart_pages && addr >= 0xFFC0) {
        int i;

        megacart_page = (addr & (megacart_pages - 1));

        /* Fix the paging... */
        for(i = 0; i < 0x40; ++i) {
            read_map[i + 0xC0] = cart_rom + (megacart_page << 14) + (i << 8);
        }

        sms_z80_set_readmap(read_map);
    }

    write_map[addr >> 8][addr & 0xFF] = data;
}

uint16 coleco_mem_read16(uint16 addr) {
    uint16 rv = (uint16)read_map[addr >> 8][addr & 0xFF];
    ++addr;

    /* Nobody'd be stupid enough to do this, would they?... */
    if(megacart_pages && addr >= 0xFFC0) {
        int i;

        megacart_page = (addr & (megacart_pages - 1));

        /* Fix the paging... */
        for(i = 0; i < 0x40; ++i) {
            read_map[i + 0xC0] = cart_rom + (megacart_page << 14) + (i << 8);
        }

        sms_z80_set_readmap(read_map);
    }

    rv |= ((uint16)read_map[addr >> 8][addr & 0xFF]) << 8;
    return rv;
}

void coleco_mem_write16(uint16 addr, uint16 data) {
    write_map[addr >> 8][addr & 0xFF] = (uint8)data;
    ++addr;

    /* Hopefully if nobody's stupid enough to trigger the one above, there
       really won't be anyone triggering THIS one... */
    if(megacart_pages && addr >= 0xFFC0) {
        int i;

        megacart_page = (addr & (megacart_pages - 1));

        /* Fix the paging... */
        for(i = 0; i < 0x40; ++i) {
            read_map[i + 0xC0] = cart_rom + (megacart_page << 14) + (i << 8);
        }

        sms_z80_set_readmap(read_map);
    }

    write_map[addr >> 8][addr & 0xFF] = (uint8)(data >> 8);
}

static void finalize_load(const char *fn) {
    char *name;
    uint32 i;

    /* Calculate the checksums of the game */
    rom_adler = rom_adler32(cart_rom, cart_len);
    rom_crc = rom_crc32(cart_rom, cart_len);

#ifdef DEBUG
    printf("Checksums: Adler-32: 0x%08" PRIX32 " CRC32: 0x%08" PRIX32 "\n",
           (uint32_t)rom_adler, (uint32_t)rom_crc);
#endif

    /* Set up the memory map */
    for(i = 0; i < 0x20; ++i) {
        read_map[i] = bios_rom + (i << 8);
        write_map[i] = dummy_areaw;
    }

    /* Nothing mapped to the expansion port for now... */
    for(; i < 0x60; ++i) {
        read_map[i] = dummy_arear;
        write_map[i] = dummy_areaw;
    }

    /* RAM */
    for(; i < 0x80; ++i) {
        write_map[i] = read_map[i] = ram + ((i & 0x03) << 8);
    }

    /* ROM */
    if(cart_len > 0x8000) {
        /* We have a MegaCart... */
        megacart_page = 0;
        megacart_pages = cart_len >> 14;

#ifdef DEBUG
        printf("coleco_mem_load_rom: Detected MegaCart\n"
               "    %" PRIu32 " bytes long = %" PRIu32 " pages\n",
               cart_len, megacart_pages);
#endif

        /* Always map 0x8000-0xBFFF to the top 16k of the cart... The page
           selected for 0xC000-0xFFFF starts out as page 0. */
        for(i = 0; i < 0x40; ++i) {
            write_map[i + 0x80] = dummy_areaw;
            write_map[i + 0xC0] = dummy_areaw;
            read_map[i + 0x80] = cart_rom + (cart_len - 0x4000) + (i << 8);
            read_map[i + 0xC0] = cart_rom + (i << 8);
        }

    }
    else {
        megacart_pages = megacart_page = 0;

        for(i = 0; i < 0x80; ++i) {
            write_map[i + 0x80] = dummy_areaw;

            if(i < (cart_len >> 8))
                read_map[i + 0x80] = cart_rom + (i << 8);
            else
                read_map[i + 0x80] = dummy_arear;
        }
    }

    sms_z80_set_readmap(read_map);
    sms_z80_set_mread(&coleco_mem_read);
    sms_z80_set_mwrite(&coleco_mem_write);
    sms_z80_set_mread16(&coleco_mem_read16);
    sms_z80_set_mwrite16(&coleco_mem_write16);

    name = strrchr(fn, '/');

    if(name != NULL) {
        /* we have a filename, but the first char is /, so skip that */
        gui_set_title(name + 1);
    }
    else {
        gui_set_title("CrabEmu");
    }
}

int coleco_mem_load_bios(const char *fn) {
    FILE *fp;
    long size;

    if(!(fp = fopen(fn, "rb"))) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_bios: Could not open ROM: %s!\n", fn);
#endif
        return -1;
    }

    /* Determine the size of the file */
    fseek(fp, 0, SEEK_END);
    size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    /* Make sure its sane */
    if(size != 8192) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_bios: ROM (%s) is invalid size\n", fn);
#endif
        return -1;
    }

    fread(bios_rom, 8192, 1, fp);
    fclose(fp);

    bios_loaded = 1;

    return 0;
}

#ifndef NO_ZLIB
static int load_gz_rom(const char *fn) {
    int len;
    gzFile fp;
    void *tmp;

    /* Open up the file in question. */
    if(!(fp = gzopen(fn, "rb"))) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Could not open ROM: %s!\n", fn);
#endif
        return ROM_LOAD_E_OPEN;
    }

    /* Read one chunk of the file at a time, until we have no more left. */
    cart_rom = (uint8 *)malloc(0x100);

    if(!cart_rom) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Couldn't allocate space!\n");
#endif
        gzclose(fp);
        return ROM_LOAD_E_ERRNO;
    }

    cart_len = 0;
    len = gzread(fp, cart_rom, 0x100);

    while(len != 0 && len != -1) {
        cart_len += 0x100;
        tmp = realloc(cart_rom, cart_len + 0x100);

        if(!tmp) {
#ifdef DEBUG
            fprintf(stderr, "coleco_mem_load_rom: Couldn't allocate space!\n");
#endif
            gzclose(fp);
            free(cart_rom);
            cart_rom = NULL;
            return ROM_LOAD_E_ERRNO;
        }

        cart_rom = (uint8 *)tmp;
        memset(cart_rom + cart_len, 0xFF, 0x100);
        len = gzread(fp, cart_rom + cart_len, 0x100);
    }

    gzclose(fp);
    finalize_load(fn);

    return ROM_LOAD_SUCCESS;
}
#endif

#ifndef NO_BZ2
static int load_bz2_rom(const char *fn) {
    int len;
    BZFILE *fp;
    void *tmp;

    /* Open up the file in question. */
    if(!(fp = BZ2_bzopen(fn, "rb"))) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Could not open ROM: %s!\n", fn);
#endif
        return ROM_LOAD_E_OPEN;
    }

    /* Read one chunk of the file at a time, until we have no more left. */    
    if(!(cart_rom = (uint8 *)malloc(0x100))) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Couldn't allocate space!\n");
#endif
        BZ2_bzclose(fp);
        return ROM_LOAD_E_ERRNO;
    }

    cart_len = 0;
    len = BZ2_bzread(fp, cart_rom, 0x100);

    while(len != 0 && len != -1) {
        cart_len += 0x100;
        tmp = realloc(cart_rom, cart_len + 0x100);

        if(!tmp) {
#ifdef DEBUG
            fprintf(stderr, "coleco_mem_load_rom: Couldn't allocate space!\n");
#endif
            BZ2_bzclose(fp);
            free(cart_rom);
            cart_rom = NULL;
            return ROM_LOAD_E_ERRNO;
        }

        cart_rom = (uint8 *)tmp;
        memset(cart_rom + cart_len, 0xFF, 0x100);
        len = BZ2_bzread(fp, cart_rom + cart_len, 0x100);
    }

    BZ2_bzclose(fp);
    finalize_load(fn);

    return ROM_LOAD_SUCCESS;
}
#endif

#ifndef NO_ZLIB
static int load_zip_rom(const char *fn) {
    int found = 0;
    unzFile fp;
    unz_file_info inf;
    char fn2[4096];
    char *ext;
    int size, realsize;

    /* Open up the file in question. */
    fp = unzOpen(fn);

    if(!fp) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Could not open ROM: %s!\n", fn);
#endif
        return ROM_LOAD_E_OPEN;
    }

    if(unzGoToFirstFile(fp) != UNZ_OK) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Couldn't find file in zip!\n");
#endif
        unzClose(fp);
        return ROM_LOAD_E_CORRUPT;
    }

    /* Keep looking at files until we find a rom. */
    while(!found) {
        if(unzGetCurrentFileInfo(fp, &inf, fn2, 4096, NULL, 0, NULL,
                                 0) != UNZ_OK) {
#ifdef DEBUG
            fprintf(stderr, "coleco_mem_load_rom: Error parsing Zip file!\n");
#endif
            unzClose(fp);
            return ROM_LOAD_E_CORRUPT;
        }

        /* Check if this file looks like a rom. */
        ext = strrchr(fn2, '.');

        if(ext) {
            if(!strcmp(ext, ".col") || !strcmp(ext, ".rom")) {
                found = 1;
            }
        }

        /* If we haven't found a rom yet, move to the next file. */
        if(!found) {
            if(unzGoToNextFile(fp) != UNZ_OK) {
#ifdef DEBUG
                fprintf(stderr, "coleco_mem_load_rom: End of zip file!\n");
#endif
                unzClose(fp);
                return ROM_LOAD_E_NO_ROM;
            }
        }
    }

    /* If the size isn't a nice even amount, round it. */
    size = realsize = inf.uncompressed_size;

    if(size & 0xFF)
        realsize = ((size + 0xFF) & 0xFF00);

    if(!(cart_rom = (uint8 *)malloc(realsize))) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Could not load ROM: %s!\n", fn);
        fprintf(stderr, "Reason: %s\n", strerror(errno));
#endif
        unzClose(fp);
        return ROM_LOAD_E_ERRNO;
    }

    memset(cart_rom, 0xFF, realsize);

    /* Attempt to open the file we think is a rom. */
    if(unzOpenCurrentFile(fp) != UNZ_OK) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Couldn't open rom from zip!\n");
#endif
        unzClose(fp);
        free(cart_rom);
        cart_rom = NULL;
        return ROM_LOAD_E_CORRUPT;
    }

    /* Attempt to read the file. */
    if(unzReadCurrentFile(fp, cart_rom, size) < 0) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Couldn't read rom from zip!\n");
#endif
        unzCloseCurrentFile(fp);
        unzClose(fp);
        free(cart_rom);
        cart_rom = NULL;
        return ROM_LOAD_E_CORRUPT;
    }

    /* We're done with the file, close everything. */
    unzCloseCurrentFile(fp);
    unzClose(fp);

    cart_len = realsize;
    finalize_load(fn);

    return ROM_LOAD_SUCCESS;
}
#endif

int coleco_mem_load_rom(const char *fn) {
    FILE *fp;
    int size, realsize;
    char *ext;

    /* If its a compressed format, go onto the handler for it... */
    ext = strrchr(fn, '.');

    if(ext) {
#ifndef NO_ZLIB
        if(!strcmp(ext, ".gz")) {
            return load_gz_rom(fn);
        }
        else if(!strcmp(ext, ".zip")) {
            return load_zip_rom(fn);
        }
#endif
#ifndef NO_BZ2
        if(!strcmp(ext, ".bz2")) {
            return load_bz2_rom(fn);
        }
#endif
    }

    if(!(fp = fopen(fn, "rb"))) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Could not open ROM: %s!\n", fn);
#endif
        return ROM_LOAD_E_ERRNO;
    }

    /* Determine the size of the file */
    fseek(fp, 0, SEEK_END);
    realsize = size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    /* If the size isn't a nice even amount, round it. */
    if(size & 0xFF)
        realsize = ((size + 0xFF) & 0xFF00);

    if(!(cart_rom = (uint8 *)malloc(realsize))) {
#ifdef DEBUG
        fprintf(stderr, "coleco_mem_load_rom: Could not load ROM: %s!\n", fn);
        fprintf(stderr, "Reason: %s\n", strerror(errno));
#endif
        return ROM_LOAD_E_ERRNO;
    }

    memset(cart_rom, 0xFF, realsize);
    fread(cart_rom, size, 1, fp);
    fclose(fp);

    cart_len = realsize;
    finalize_load(fn);

    return ROM_LOAD_SUCCESS;
}

int coleco_mem_read_context(const uint8 *buf) {
    uint32 len;
    uint16 ver;

    /* Check the size */
    BUF_TO_UINT32(buf + 4, len);
    if(len != 1040)
        return -1;

    /* Check the version number */
    BUF_TO_UINT16(buf + 8, ver);
    if(ver != 1)
        return -1;

    /* Check the child pointer */
    if(buf[12] != 0 || buf[13] != 0 || buf[14] != 0 || buf[15] != 0)
        return -1;

    /* Copy in the memory */
    memcpy(ram, buf + 16, 1024);
    return 0;
}

int coleco_regs_read_context(const uint8 *buf) {
    uint32 len;
    uint16 ver;

    /* Check the size */
    BUF_TO_UINT32(buf + 4, len);
    if(len != 20)
        return -1;

    /* Check the version number */
    BUF_TO_UINT16(buf + 8, ver);
    if(ver != 1)
        return -1;

    /* Check the child pointer */
    if(buf[12] != 0 || buf[13] != 0 || buf[14] != 0 || buf[15] != 0)
        return -1;

    /* Copy in the registers */
    cont_mode = buf[16];

    if(megacart_pages) {
        int i;

        megacart_page = buf[17];

        /* Fix the paging... */
        for(i = 0; i < 0x40; ++i) {
            read_map[i + 0xC0] = cart_rom + (megacart_page << 14) + (i << 8);
            sms_z80_set_readmap(read_map);
        }
    }

    return 0;
}

int coleco_mem_write_context(FILE *fp) {
    uint8 data[4];

    /* Write the RAM block */
    data[0] = 'D';
    data[1] = 'R';
    data[2] = 'A';
    data[3] = 'M';
    fwrite(data, 1, 4, fp);             /* Block ID */

    UINT32_TO_BUF(1040, data);
    fwrite(data, 1, 4, fp);             /* Length */

    UINT16_TO_BUF(1, data);
    fwrite(data, 1, 2, fp);             /* Version */
    fwrite(data, 1, 2, fp);             /* Flags (Importance = 1) */

    data[0] = data[1] = data[2] = data[3] = 0;
    fwrite(data, 1, 4, fp);             /* Child pointer */

    fwrite(ram, 1, 1024, fp);

    /* Write the ColecoVision Registers block */
    data[0] = 'C';
    data[1] = 'V';
    data[2] = 'R';
    data[3] = 'G';
    fwrite(data, 1, 4, fp);             /* Block ID */

    UINT32_TO_BUF(20, data);
    fwrite(data, 1, 4, fp);             /* Length */

    UINT16_TO_BUF(1, data);
    fwrite(data, 1, 2, fp);             /* Version */
    fwrite(data, 1, 2, fp);             /* Flags (Importance = 1) */

    data[0] = data[1] = data[2] = data[3] = 0;
    fwrite(data, 1, 4, fp);             /* Child pointer */

    data[0] = cont_mode;
    data[1] = megacart_page;
    data[2] = data[3] = 0;
    fwrite(data, 1, 4, fp);

    return 0;
}

int coleco_game_read_context(const uint8 *buf) {
    uint32 len, crc;
    uint16 ver;

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

    /* Check if the game matches... */
    BUF_TO_UINT32(buf + 16, crc);
    if(crc != rom_crc)
        return -2;

    BUF_TO_UINT32(buf + 20, crc);
    if(crc != rom_adler)
        return -2;

    return 0;
}

int coleco_game_write_context(FILE *fp) {
    uint8 data[4];

    data[0] = 'G';
    data[1] = 'A';
    data[2] = 'M';
    data[3] = 'E';
    fwrite(data, 1, 4, fp);             /* Block ID */

    UINT32_TO_BUF(24, data);
    fwrite(data, 1, 4, fp);             /* Length */

    UINT16_TO_BUF(1, data);
    fwrite(data, 1, 2, fp);             /* Version */
    UINT16_TO_BUF(0, data);
    fwrite(data, 1, 2, fp);             /* Flags (Importance = 0) */

    data[0] = data[1] = data[2] = data[3] = 0;
    fwrite(data, 1, 4, fp);             /* Child pointer */

    UINT32_TO_BUF(rom_crc, data);
    fwrite(data, 1, 4, fp);

    UINT32_TO_BUF(rom_adler, data);
    fwrite(data, 1, 4, fp);

    return 0;
}

int coleco_mem_init(void) {
    memset(ram, 0, 1024);
    memset(bios_rom, 0, 8192);

    bios_loaded = 0;
    megacart_page = megacart_pages = 0;
    coleco_cont_bits[0] = 0;
    coleco_cont_bits[1] = 0;

    return 0;
}

int coleco_mem_shutdown(void) {
    if(cart_rom)
        free(cart_rom);

    cart_rom = NULL;
    cart_len = 0;

    return 0;
}

void coleco_mem_reset(void) {
    memset(ram, 0, 1024);
    coleco_cont_bits[0] = 0;
    coleco_cont_bits[1] = 0;
}

void coleco_get_checksums(uint32 *crc, uint32 *adler) {
    *crc = rom_crc;
    *adler = rom_adler;
}

uint8 *coleco_get_ram(void) {
    return ram;
}

void coleco_cheat_poke(uint16 addr, uint8 data) {
    /* Cheat addresses are RAM-relative (0x0000-0x03FF), matching legacy
       libretro .cht addresses, not the real $6000-$7FFF CPU range. */
    ram[addr & 0x03FF] = data;
}
