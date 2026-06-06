////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/mdl_txword.v
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
// Copyright (C) 2023-2026, Gisselquist Technology, LLC
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
		input	wire		S_VALID,
		output	wire		S_READY,
		input	wire		S_CTRL,
		input	wire	[31:0]	S_DATA,
		//
		output	wire	[39:0]	o_tx_word
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[32:0]	P_ALIGN = { 1'b0, 8'hbc, 8'h4a, 8'h4a, 8'h7b };

	reg	[32:0]	raw_dword;
	wire		ign_enc_valid, enc_ready;
	wire	[39:0]	enc_data;
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
		.M_VALID(ign_enc_valid),
		.M_READY(enc_ready),
		.M_DATA(o_tx_word)
	);
	// }}}

	assign	enc_ready = 1'b1;

	// Verilator lint_off UNUSED
	wire	[31:0]	test_decode;
	wire		ign_test_ready, tst_valid, tst_illegal, tst_control;
	// Verilator lint_on  UNUSED

	mdl_s10b8bw
	u_s10b8bw (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset),
		//
		.S_VALID(ign_enc_valid),
		.S_READY(ign_test_ready),
		.S_DATA(o_tx_word),
		//
		.M_VALID(tst_valid),
		.M_READY(1'b1),
		.M_ILLEGAL(tst_illegal), .M_CTRL(tst_control),
		.M_DATA(test_decode)
		// }}}
	);

	// Make Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, ign_enc_valid };
	// Verilator lint_on  UNUSED
	// }}}
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
	// No properties (yet)
`endif
// }}}
endmodule
