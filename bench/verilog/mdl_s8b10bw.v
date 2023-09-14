////////////////////////////////////////////////////////////////////////////////
//
// Filename:	mdl_s8b10bw.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Encodes a 32-bit word in 8b10b encoding.  The first byte of this
//		word is found in bits 7:0, in little endian fashion.  When it
//	comes to the output, bit[39] is to be transmitted first, and bit[0]
//	last.  So ... little endian in, big endian out.
//
//	Both inputs and outputs are based upon the AXI stream protocol, offering
//	full backpressure support.  (This is intended for a device *model*,
//	where such support might actually be achieved.)  External events (i.e.
//	clocks, CDCs, etc) will determine handshaking.
//
//	The implementation works by calling a sub-block to handle 8b10b
//	encoding on a byte by byte level.  Again, this works and meets
//	timing because this is for a test bench that will have no timing issues.
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2022-2023, Gisselquist Technology, LLC
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
`default_nettype none
// }}}
module	mdl_s8b10bw (
		// {{{
		input	wire	i_clk, i_reset,
		input	wire		S_VALID,	// *MUST* be == 1
		output	wire		S_READY,
		input	wire		S_CTRL,		//Is this a control wrd?
		input	wire	[31:0]	S_DATA,
		//
		output	reg		M_VALID,
		input	wire		M_READY,
		output	reg	[39:0]	M_DATA	
		// }}}
	);

	// Local declarations
	// {{{
	reg		running_disparity;
	wire		d0, d1, d2, d3;
	wire	[39:0]	w_data;
	// }}}

	mdl_s8b10b
	u_b0 (
		.S_DATA({ running_disparity, S_CTRL, S_DATA[7:0] }),
		.M_DATA({ d0, w_data[39:30] })	// Transmitted *first*
	);

	mdl_s8b10b
	u_b1 (
		.S_DATA({ d0, 1'b0, S_DATA[15:8] }),
		.M_DATA({ d1, w_data[29:20] })
	);

	mdl_s8b10b
	u_b2 (
		.S_DATA({ d1, 1'b0, S_DATA[23:16] }),
		.M_DATA({ d2, w_data[19:10] })
	);

	mdl_s8b10b
	u_b3 (
		.S_DATA({ d2, 1'b0, S_DATA[31:24] }),
		.M_DATA({ d3, w_data[9:0] })
	);

	always @(posedge i_clk)
	if (i_reset)
		running_disparity <= 1'b0;
	else if (S_VALID && (!M_VALID || M_READY))
		running_disparity <= d3;

	initial	M_VALID = 1'b0;
	always @(posedge i_clk)
	if (i_reset)
		M_VALID <= 1'b0;
	else if (!M_VALID || M_READY)
		M_VALID <= S_VALID;

	always @(posedge i_clk)
	if (!M_VALID || M_READY)
		M_DATA <= w_data;

	assign	S_READY = !M_VALID || M_READY;
endmodule
