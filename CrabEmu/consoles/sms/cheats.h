/*
    This file is part of CrabEmu.

    Copyright (C) 2009, 2015 Lawrence Sebald

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

#ifndef CHEATS_H
#define CHEATS_H

#include "CrabEmu.h"
#include "queue.h"

CLINKAGE

typedef struct smscheat_s {
    TAILQ_ENTRY(smscheat_s) qentry;
    uint32 ar_code;
    char desc[64];
    int enabled;
} sms_cheat_t;

extern int sms_cheat_init(void);
extern void sms_cheat_shutdown(void);
extern void sms_cheat_reset(void);

extern void sms_cheat_frame(void);

/* Consoles that don't route through sms_write_map (e.g. ColecoVision) can
   install a poke function so cheat writes reach their own memory map.
   Pass NULL to restore the default sms_write_map behavior. */
typedef void (*sms_cheat_poke_func)(uint16 addr, uint8 data);
extern void sms_cheat_set_poke_func(sms_cheat_poke_func func);

extern int sms_cheat_add(sms_cheat_t *c);
extern int sms_cheat_remove(int index);
extern int sms_cheat_count(void);
extern sms_cheat_t *sms_cheat_get(int index);
extern int sms_cheat_read(const char *fn);
extern int sms_cheat_write(const char *fn);

extern void sms_cheat_enable(void);
extern void sms_cheat_disable(void);

ENDCLINK

#endif /* !CHEATS_H */
