////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/cpp/memsim.cpp
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	This creates a memory like device to act on a WISHBONE bus.
//		It doesn't exercise the bus thoroughly, but does give some
//	exercise to the bus to see whether or not the bus master can control
//	it.
//
//	This particular version differs from the memsim version within the
//	ZipCPU project in that there is a variable delay from request to
//	completion.
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2023-2025, Gisselquist Technology, LLC
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
// }}}
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include "memsim.h"
#include "byteswap.h"

// Byte swap buffer function - swaps endianness if needed
void byteswapbuf(unsigned int n, uint32_t *buf) {
	// Only perform byte swapping if the system is little endian
	// This is a simple implementation - system-specific optimizations may be needed
	#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
	for(unsigned int i = 0; i < n; i++) {
		uint32_t v = buf[i];
		buf[i] = ((v & 0xff) << 24) | ((v & 0xff00) << 8) 
			   | ((v & 0xff0000) >> 8) | ((v & 0xff000000) >> 24);
	}
	#endif
}

const int	MEMSIM::NWRDWIDTH = 1;

MEMSIM::MEMSIM(const unsigned int nbytes, const unsigned int delay) {
	// {{{
	unsigned int	nxt;
	for(nxt=1; nxt < nbytes; nxt<<=1)
		;
	m_len = nxt; m_mask = nxt-1;
	m_mem = new BUSW[m_len];
	memset(m_mem, 0, sizeof(BUSW)*m_len);

	m_cleared = false;
	m_delay = delay;
	for(m_delay_mask=1; m_delay_mask < delay; m_delay_mask<<=1)
		;
	m_fifo_ack  = new int[m_delay_mask];
	memset(m_fifo_ack, 0, sizeof(int)*m_delay_mask);
	m_fifo_data = new BUSW[m_delay_mask*NWRDWIDTH];
	memset(m_fifo_data, 0, sizeof(BUSW)*m_delay_mask*NWRDWIDTH);
	for(unsigned i=0; i<m_delay_mask; i++)
		m_fifo_ack[i] = 0;
	m_delay_mask-=1;
	m_head = 0; m_tail = (m_head - delay)&m_delay_mask;
}
// }}}

MEMSIM::~MEMSIM(void) {
	// {{{
	delete[]	m_mem;
	delete[] m_fifo_ack;
    delete[] m_fifo_data;
}
// }}}

void	MEMSIM::load(const char *fname) {
	// {{{
	FILE	*fp;
	unsigned int	nr;

	fp = fopen(fname, "r");
	if (!fp) {
		fprintf(stderr, "Could not open/load file \'%s\'\n",
			fname);
		perror("O/S Err:");
		fprintf(stderr, "\tInitializing memory with zero instead.\n");
		nr = 0;
	} else {
		nr = fread(m_mem, sizeof(BUSW), m_len, fp);
		byteswapbuf(nr, m_mem);
		fclose(fp);

		if (nr != m_len) {
			fprintf(stderr, "Only read %d of %d words\n",
				nr, m_len);
			fprintf(stderr, "\tFilling the rest with zero.\n");
		}
	}

	for(; nr<m_len; nr++)
		m_mem[nr] = 0l;
}
// }}}

void	MEMSIM::load(const unsigned int addr, const char *buf, const size_t len) {
	// {{{
	memcpy(&m_mem[addr], buf, len);
	byteswapbuf(len/sizeof(BUSW), &m_mem[addr]);
}
// }}}

void	MEMSIM::apply(const uchar wb_cyc, const uchar wb_stb, const uchar wb_we,
		const BUSW wb_addr, const uint32_t *wb_data, const uint64_t wb_sel,
		unsigned char &o_stall, unsigned char &o_ack, uint32_t *o_data){
	// {{{
	unsigned	sel = 0, addr = wb_addr*NWRDWIDTH, m_write;
	const uint32_t	*sp = &wb_data[NWRDWIDTH-1];
	uint32_t	*dp = &o_data[NWRDWIDTH-1];
	uint64_t	wbsel = ((uint64_t)wb_sel);//&0xfffffffffffffffful;
	bool		DEBUG = false;

	if (!wb_cyc) {
		// {{{
		o_ack = 0;
		o_stall= 0;
		m_head = 0;
		m_tail = (m_head - m_delay)&m_delay_mask;
		if (!m_cleared) {
			for(unsigned k=0; k<m_delay_mask+1; k++)
				m_fifo_ack[k] = 0;
			m_cleared = true;
		}
		return;
		// }}}
	} if (wb_stb)
		m_cleared = false;

	if ((DEBUG)&&(wb_stb)&&(wb_we)) {
		// {{{
		printf("MEMSIM::WR[%08x]&%0*lx: <- ", addr,
				(NWRDWIDTH*32/8/4),wbsel);
		for(unsigned k=0; k<NWRDWIDTH; k++)
			printf("%08x%s", wb_data[(NWRDWIDTH-1)-k],
				(k<NWRDWIDTH-1)?":":"");

		printf("\n");
	}
	// }}}

	m_head++;
	m_tail = (m_head - m_delay)&m_delay_mask;
	m_head &= m_delay_mask;
	m_write = (m_head - m_delay/2)&m_delay_mask;

	o_stall= (rand() & 0x03f)==0;	// 1 in 64
	o_ack = m_fifo_ack[m_tail];
	m_fifo_ack[m_head] = 0;

	for(unsigned k=0; k<NWRDWIDTH; k++)
		*dp-- = m_fifo_data[m_tail*NWRDWIDTH + k];

	if (wb_cyc && wb_stb && !o_stall) {
		// {{{
		if (wb_we) {
			for(unsigned k= m_write; k != (m_head & m_delay_mask);
							k=(k+1)&m_delay_mask) {
				if (m_fifo_ack[k]) {
					m_fifo_ack[m_head] = 1;
					break;
				}
			} if (!m_fifo_ack[m_head])
				m_fifo_ack[m_write] = 1;
		} else
			m_fifo_ack[m_head] = 1;

		if (wb_we) { for(unsigned k=0; k<NWRDWIDTH; k++) {

			unsigned dsel  = ((uint64_t)wbsel)>>((NWRDWIDTH-1-k)*4);
			dsel &= 0x0f;

			if ((dsel&0x0f)==0x0f) {
				uint32_t memv = *sp--;
				if (DEBUG) printf("MEMSIM: %02x:%02x:%02x:%02x\n",
					(memv>>24)&0x0ff,
					(memv>>16)&0x0ff,
					(memv>> 8)&0x0ff,
					memv&0x0ff);
				m_mem[(addr+k) & m_mask] = memv;
			} else {
				uint32_t memv = m_mem[(addr+k)&m_mask];

				sel = 0;
				if (dsel&0x8)
					sel |= 0x0ff000000;
				if (dsel&0x4)
					sel |= 0x000ff0000;
				if (dsel&0x2)
					sel |= 0x00000ff00;
				if (dsel&0x1)
					sel |= 0x0000000ff;

				memv &= ~sel;
				memv |= (*sp-- & sel);
				m_mem[(addr+k) & m_mask] = memv;

				if (DEBUG) {
					if (sel&0x0ff000000)
						printf("MEMSIM: %02x:", (memv>>24)&0x0ff);
					else
						printf("MEMSIM: --:");

					if (sel&0x0ff0000)
						printf("%02x:", (memv>>16)&0x0ff);
					else
						printf("--:");

					if (sel&0x0ff00)
						printf("%02x:", (memv>>8)&0x0ff);
					else
						printf("--:");

					if (sel&0x0ff)
						printf("%02x  ", (memv)&0x0ff);
					else
						printf("--  ");

					printf("\n");
				}
			}
		}} else { for(unsigned k=0; k<NWRDWIDTH; k++) {
			// if (!wb_we)
			m_fifo_data[m_head*NWRDWIDTH + k] = m_mem[(addr+k) & m_mask];
			if (DEBUG && !wb_we) { printf("MEMBUS-RD[%08x + %d & %08x] = %08x\n", addr, k, m_mask, m_fifo_data[m_head*NWRDWIDTH+k]); }
		}}

		if (DEBUG) {
			printf("MEMBUS %s[%08x] = ",
				(wb_we)?"W":"R", (addr << 2));
			for(unsigned k=0; k<NWRDWIDTH; k++)
				printf("%08x%s", m_mem[(addr+k)&m_mask],
					(k < NWRDWIDTH-1) ? ":":"\n");
		}
	}
	// }}}

	if (DEBUG && o_ack) {
		// {{{
		printf("MEMBUS -- ACK: ");
		for(unsigned k=0; k<NWRDWIDTH; k++)
			printf("%08x%s", o_data[(NWRDWIDTH-1)-k],
				(k < NWRDWIDTH-1) ? ":":"\n");
	}
	// }}}
	// if ((wb_stb)&&(wb_we)) printf("\n");
}
// }}}
