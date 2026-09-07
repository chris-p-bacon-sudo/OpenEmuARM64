/*
    This file is part of CrabEmu.

    Copyright (C) 2012 Lawrence Sebald

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

#ifndef COLECOMEM_H
#define COLECOMEM_H

#include "CrabEmu.h"

CLINKAGE

#include <stdio.h>

extern void coleco_port_write(uint16 port, uint8 data);
extern uint8 coleco_port_read(uint16 port);

extern int coleco_mem_load_bios(const char *fn);
extern int coleco_mem_load_rom(const char *fn);

extern int coleco_mem_read_context(const uint8 *buf);
extern int coleco_regs_read_context(const uint8 *buf);
extern int coleco_mem_write_context(FILE *fp);

extern int coleco_game_write_context(FILE *fp);
extern int coleco_game_read_context(const uint8 *buf);

extern int coleco_mem_init(void);
extern int coleco_mem_shutdown(void);
extern void coleco_mem_reset(void);

extern void coleco_get_checksums(uint32 *crc, uint32 *adler);

extern uint8 *coleco_get_ram(void);
extern void coleco_cheat_poke(uint16 addr, uint8 data);

ENDCLINK

#endif /* !COLECOMEM_H */
