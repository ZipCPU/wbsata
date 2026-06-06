////////////////////////////////////////////////////////////////////////////////
//
// Filename:	sw/satadrv.h
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2025, Gisselquist Technology, LLC
// {{{
// This file is part of the WBSATA project.
//
// The WBSATA project is a free software (firmware) project: you may
// redistribute it and/or modify it under the terms of  the GNU General Public
// License as published by the Free Software Foundation, either version 3 of
// the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  If not, please see <http://www.gnu.org/licenses/> for a
// copy.
// }}}
// License:	GPL, v3, as defined and found on www.gnu.org,
// {{{
//		http://www.gnu.org/licenses/gpl.html
//
////////////////////////////////////////////////////////////////////////////////
//
// }}}
#ifndef	SATADRV_H
#define	SATADRV_H
#include <stdint.h>

typedef	struct SATA_S {
	volatile uint32_t	s_cmd, s_lbalo, s_lbahi, s_count;
	volatile uint32_t	s_unused, s_phy;
	volatile void		*s_dma;
	volatile uint32_t	s_unused_tail;
} SATA;

struct	SATADRV_S;

extern	struct	SATADRV_S *sata_init(SATA *dev);
extern	int	sata_write(struct SATADRV_S *dev, const unsigned sector,
				const unsigned count, const char *buf);
extern	int	sata_read(struct SATADRV_S *dev, const unsigned sector,
				const unsigned count, char *buf);
extern	int	sata_ioctl(struct SATADRV_S *dev, char cmd, char *buf);
#endif
