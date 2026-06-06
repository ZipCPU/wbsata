////////////////////////////////////////////////////////////////////////////////
//
// Filename:	sw/satadrv.c
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	This is the software driver for the SATA controller, used for
//		interacting with a SATA drive.
//
// Entry points: This driver has four external entry points, which can be used
//	to define it's operation:
//
//	1. sata_init
//		This should be called first.  It will generate the driver's
//		data structure, and attempt to interact with the device.
//		It needs to be passed the hardware address of the device in
//		the address map.
//
//	2. sata_write(dev, sector, count, buf)
//		Writes "count" sectors of data to the device, starting at
//		the sector numbered "sector".  The data are sourced from the
//		*buf pointer, which *must* either be word aligned or the CPU
//		must be able to handle unaligned accesses.
//
//	3. sata_read(dev, sector, count, buf)
//		Reads "count" sectors of data to the device, starting at
//		the sector numbered "sector".  The data are saved into the
//		*buf pointer, which *must* either be word aligned or the CPU
//		must be able to handle unaligned accesses.
//
//	4. sdio_ioctl
//		Other odds and ends as necessary.
//
// Issues:
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
#include <stdlib.h>
#include <stdint.h>
// typedef	uint8_t  BYTE;
// typedef	uint16_t WORD;
// typedef	uint32_t DWORD, LBA_t, UINT;
#include <diskio.h>
#include "sdiodrv.h"

// tx* -- debugging output functions
// {{{
// Debugging isn't quite as simple as using printf(), since I want to guarantee
// that I can still compile and build this into a memory that isn't large enough
// to hold a printf function.  The txstr(), txchr(), and txhex() functions fit
// that low memory footprint need.  For cases where these are not sufficient,
// we use the STDIO_DEBUG flag to determine if the regular ?rintf() functions
// are available.
#ifndef	TXFNS_H
#include <stdio.h>

#define	txchr(A)		putchar(A)
#define	txstr(A)		fputs(A, stdout)
#define	txhex(A)		printf("%08x", A)
#define	txdecimal(A)		printf("%d", A)
#define	STDIO_DEBUG
#else
// extern	void	txstr(const char *);
// extern	void	txhex(unsigned);
// extern	void	txdecimal(int);
#define	printf(...)
#endif
// }}}

// WBScope
// {{{
// The following defines may be useful when a WBScope has been attached
// to the device.  They are mostly useful for debugging.  If no WBScope
// is attached, these macros are given null definitions.
#ifdef	_BOARD_HAS_SATATSCOPE
  #ifdef	_BOARD_HAS_SATALSCOPE
    #define	SET_SCOPE	_satatscope->s_ctrl = 0x04000100; _satalscope->s_ctrl = 0x04000100
    #define	TRIGGER_SCOPE	_satatscope->s_ctrl = 0xff000100; _satalscope->s_ctrl = 0xff000100
  #else
    #define	SET_SCOPE	_satatscope->s_ctrl = 0x04000100
    #define	TRIGGER_SCOPE	_satatscope->s_ctrl = 0xff000100
  #endif // TSCOPE
#else
  #ifdef	_BOARD_HAS_SATALSCOPE
    #define	SET_SCOPE	_satalscope->s_ctrl = 0x04000100
    #define	TRIGGER_SCOPE	_satalscope->s_ctrl = 0xff000100
  #else
    #define	SET_SCOPE
    #define	TRIGGER_SCOPE
  #endif
#endif
// }}}

// SINFO & SDEBUG
// {{{
// These are designed to be compile time constants, to allow the compiler to
// remove the logic they generate for space reasons.
//	SDEBUG: Set to turn on debugging output.  Ideally, debugging output
//		should not be necessary in a *working* design, so its use is
//		primary until the design starts working.  This debugging
//		output will tell you (among other things) when the design
//		issues commands, what command are issued, which routines are
//		called.  etc.
//	SINFO: Set to turns on a verbose reporting.  This will dump values of
//		registers, together with their meanings.  When reading,
//		it will dump sectors read.  Often requires SDEBUG.
static	const int	SINFO = 0, SDEBUG = 0;
// }}}

// SDMULTI
// {{{
// SDMULTI: Controls whether the reads and/or writes will be issued one block
// at a time, or across many blocks.  Set to 1 to allow multiblock commands,
// 0 otherwise.
static	const int	SDMULTI = 1;
// }}}
// }}}

#define	NEW_MUTEX
#define	GRAB_MUTEX
#define	RELEASE_MUTEX
#ifndef	CLEAR_DCACHE
#define	CLEAR_DCACHE
#endif

static	const unsigned	SATA_DMA_WRITE = 0x00ca4027,
			SATA_DMA_READ  = 0x00c84027;

typedef	struct	SATADRV_S {
	SATA		*d_dev;
	uint32_t	d_sector_count, d_block_size;
} SATADRV;

static	void	sata_wait_while_busy(SATADRV *dev);
// static	int	sata_write_block(SATADRV *dev, uint32_t sector, uint32_t *buf);	  // CMD 24
// static	int	sata_read_block(SATADRV *dev, uint32_t sector, uint32_t *buf);	  // CMD 17

extern	SATADRV *sata_init(SDIO *dev);
extern	int	sata_write(SATADRV *dev, const unsigned sector, const unsigned count, const char *buf);
extern	int	sata_read(SATADRV *dev, const unsigned sector, const unsigned count, char *buf);
extern	int	sata_ioctl(SATADRV *dev, char cmd, char *buf);


void	sata_wait_while_busy(SATADRV *dev) {
	// {{{

	// Could also do a system call and yield to the scheduler while waiting
	// if (SDIO_OS) {
	//	os_wait(dev->d_int);
	// } else if (SDIO_INT) {
	//	// Can wait for an interrupt here, such as by calling an
	//	// external wait_int function with our interrupt ID.
	//	wait_int(dev->d_int);
	// } else {

	// Busy wait implementation
	uint32_t	st;

	st = dev->d_dev->sd_cmd;
	while(st & SDIO_BUSY)
		st = dev->d_dev->sd_cmd;

	// }
}
// }}}

SATADRV *sata_init(SDIO *dev) {
	// {{{
	unsigned	ifcond, op_cond, hcs;
	SATADRV	*dv = (SATADRV *)malloc(sizeof(SATADRV));
	unsigned op_cond_query;
	unsigned	clk_phase = 16 << 16;

	// Check for memory allocation failure.
	if (NULL == dv) {
		txstr("PANIC:  No memory for SDIO driver!\n");
		// PANIC;
		return NULL;
	}

	dv->d_dev = dev;
	dv->d_sector_count = 0;
	dv->d_block_size   = 0;

	SET_SCOPE;

	// NEW_MUTEX;
	// GRAB_MUTEX;

	// Any initialization we need ...
	//   For example, we need to get the sector count here

	// RELEASE_MUTEX;

	if (SDEBUG) {
		txstr("Block size:   ");
		txdecimal(dv->d_block_size);
		txstr("\nSector count: "); txdecimal(dv->d_sector_count);
		txstr("\n");
	}

	return	dv;
}
// }}}

int	sata_write(SATADRV *dev, const unsigned sector,
			const unsigned count, const char *buf) {
	// {{{
	unsigned	dev_stat, err = 0;

	if (0 == count)
		return	RES_OK;

	if (SDEBUG) {
		// {{{
		txstr("SATA-WRITE(MNY): ");
		txhex(sector);
		txstr(", ");
		txhex(count);
		txstr(", ");
		txhex(buf);
		txstr("\n");
	}
	// }}}

	GRAB_MUTEX;

	dev->d_dev->s_count = count;	// Number of sectors
	dev->d_dev->s_dma   = buf;	// Address to source the data from
	dev->d_dev->s_lbalo = sector & 0x0ffffff;
	dev->d_dev->s_lbahi = 0;

	// Here's the *go* command
	dev->d_dev->s_cmd   = SATA_DMA_WRITE | ((sector >> 16) & 0x0f00);

	sata_wait_while_busy(dev);

	dev_stat  = dev->d_dev->s_cmd;

	RELEASE_MUTEX;

	// Error handling
	// {{{
	if (err) {
		// If we had any write failures along the way, return
		// an error status.

		// Immediately trigger the scope (if not already triggered)
		// to avoid potentially losing any more data.
		TRIGGER_SCOPE;
	}
	// }}}

	if (err) {
		if (SDEBUG)
			txstr("SATA-WRITE -> ERR\n");
		return	RES_ERROR;
	} return RES_OK;
}
// }}}

int	sata_read(SATADRV *dev, const unsigned sector,
				const unsigned count, char *buf) {
	// {{{
	if (0 == count)
		return RES_OK;

	if (SDEBUG) {
		// {{{
		txstr("SATA-READ(MNY): ");
		txhex(sector);
		txstr(", ");
		txhex(count);
		txstr(", ");
		txhex(buf);
		txstr("\n");
	}
	// }}}

	GRAB_MUTEX;

	dev->d_dev->s_count = count;	// Number of sectors
	dev->d_dev->s_dma   = buf;	// Address to source the data from
	dev->d_dev->s_lbalo = sector & 0x0ffffff;
	dev->d_dev->s_lbahi = 0;

	// Here's the *go* command
	dev->d_dev->s_cmd   = SATA_DMA_READ | ((sector >> 16) & 0x0f00);

	sata_wait_while_busy(dev);

	dev_stat  = dev->d_dev->s_cmd;

	RELEASE_MUTEX;

	if (err) {
		if (SDEBUG)
			txstr("SATA-READ -> ERR\n");
		return RES_ERROR;
	} return RES_OK;
}
// }}}

int	sdio_ioctl(SATADRV *dev, char cmd, char *buf) {
	// {{{
	int		dstat;
	unsigned	vc;

	switch(cmd) {
	case CTRL_SYNC: {
			GRAB_MUTEX;
			sata_wait_while_busy(dev);
			RELEASE_MUTEX;
			return	RES_OK;
		} break;
	case GET_SECTOR_COUNT:
		{	DWORD	*w = (DWORD *)buf;
			*w = dev->d_sector_count;
			return RES_OK;
		} break;
		break;
	case GET_SECTOR_SIZE:
		{	WORD	*w = (WORD *)buf;
			*w = 512;	// *MUST* be
			return RES_OK;
		} break;
	}

	return	RES_PARERR;
}
// }}}
