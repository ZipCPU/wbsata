////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/verilog/mdl_txword.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	This is basically a 40:1 OSERDES combined with the 8b10b
//		encoder feeding it.  As a result, 1+32b control words may be
//	given via AXI stream, and they'll be fed out the output one bit at a
//	time.
//
// A (potential) modification can be made via i_cfg_speed, so allow this
// component to support multiple SATA speeds.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2023-2024, Gisselquist Technology, LLC
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
`timescale	1ns/1ps
// }}}
module	mdl_txword (
		// {{{
		input	wire		i_clk,
		input	wire		i_reset,
		input	wire	[1:0]	i_cfg_speed,//0(1.5Gb/s), 1(3Gb/s), 2(6)
		input	wire		S_VALID,
		output	wire		S_READY,
		input	wire		S_CTRL,
		input	wire	[31:0]	S_DATA,
		//
		output	wire		o_tx
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[32:0]	P_ALIGN = { 1'b0, 8'hbc, 8'h4a, 8'h4a, 8'h7b };

	wire		subbit_ready;
	reg	[1:0]	r_subbit;
	reg	[5:0]	r_posn;
	reg	[32:0]	raw_dword;
	reg	[39:0]	r_sreg;
	wire		enc_valid, enc_ready;
	wire	[39:0]	enc_data;
	// }}}

	// r_subbit
	// {{{
	always @(posedge i_clk)
	if (i_reset)
		r_subbit <= 0;
	else case(i_cfg_speed)
	1: r_subbit <= r_subbit + 1;
	2: r_subbit <= { r_subbit[1], 1'b0 } + 2;
	default:
		r_subbit <= 0;
	endcase
	// }}}

	// r_posn
	// {{{
	initial	r_posn = 0;
	always @(posedge i_clk)
	if (i_reset)
		r_posn <= 0;
	else if (enc_ready)
		r_posn <= 39;
	else if (subbit_ready)
	begin
		if (r_posn > 0)
			r_posn <= r_posn - 1;
		else
			r_posn <= 0;
	end
	// }}}

	// raw_dword: P_ALIGN until we have a valid
	// {{{
	always @(*)
	if (i_reset)
		raw_dword = P_ALIGN;
	else if (S_VALID)
		raw_dword = { S_CTRL, S_DATA };
	else
		raw_dword = P_ALIGN;
	// }}}

	// 8b->10b encoding across all 32-bits: S_* -> enc_*
	// {{{
	mdl_s8b10bw #(
		.OPT_REGISTERED(1'b0)
	) u_8b10b_encoder (
		.i_clk(i_clk),
		.i_reset(i_reset),
		//
		.S_VALID(S_VALID),
		.S_READY(S_READY),
		.S_CTRL(raw_dword[32]),
		.S_DATA(raw_dword[31:0]),
		//
		.M_VALID(enc_valid),
		.M_READY(enc_ready),
		.M_DATA(enc_data)
	);
	// }}}

	// r_sreg
	// {{{
	always @(posedge i_clk)
	if (S_READY)
		r_sreg <= enc_data;
	else if (subbit_ready)
		r_sreg <= r_sreg << 1;
	// }}}

	assign	subbit_ready = (r_subbit == 0);
	assign	enc_ready = (r_posn == 0) && subbit_ready;
	assign	o_tx = r_sreg[39];

	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, enc_valid };
	// Verilator lint_on  UNUSED
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
// Formal properties
// {{{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
`ifdef	FORMAL
`endif
// }}}
endmodule
