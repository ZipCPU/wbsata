////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/verilog/mdl_salign.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Locks on to 8B/10B keywords, to produce a 32b stream of RX
//		data (+ keyword notification).
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2022-2024, Gisselquist Technology, LLC
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
module	mdl_salign // #()
	(
		// {{{
		input	wire		i_clk,		// Bit clock
					i_reset,	// Async reset
		input	wire		i_rx_p,
		output	reg		o_valid,
		output	reg		o_keyword,
		output	reg	[31:0]	o_data
		// }}}
	);

	// Local declarations
	// {{{
	reg		syncd;
	reg	[5:0]	offset;

	reg	[39:0]	ishift_reg, pre_sync;
	wire		dcd_ctrl, dcd_illegal, ign_dcd_valid, ign_dcd_ready;
	wire	[31:0]	dcd_data;
	// }}}

	initial	ishift_reg = 0;
	always @(posedge i_clk)
	if (i_reset)
		ishift_reg <= 0;
	else
		ishift_reg <= { ishift_reg[38:0], i_rx_p };

	mdl_s10b8bw #(
		.OPT_REGISTERED(1'b1)
	) u_decoder (
		.i_clk(i_clk),
		.i_reset(i_reset),
		.S_VALID(1'b1),
		.S_READY(ign_dcd_ready),	// *MUST* be one
		.S_DATA(ishift_reg),
		//
		.M_VALID(ign_dcd_valid),
		.M_READY(1'b1),
		.M_ILLEGAL(dcd_illegal),
		.M_CTRL(dcd_ctrl),
		.M_DATA(dcd_data)
	);

	initial	pre_sync  = 0;
	always @(posedge i_clk)
	if (i_reset)
		pre_sync  <= 0;
	else
		pre_sync <= { pre_sync[38:0], (dcd_ctrl && !dcd_illegal) };

	always @(posedge i_clk)
	if (i_reset)
	begin
		syncd  <= 0;
		offset <= 0;
	end else if (!syncd)
	begin
		offset <= 0;
		if (dcd_ctrl && pre_sync[39])
		begin
			syncd  <= 1'b1;
			offset <= 1;
		end
	end else begin
		offset <= offset + 1;
		if (offset >= 39)
			offset <= 0;
		if (offset == 39 && dcd_illegal)
			syncd  <= 0;
	end

	always @(posedge i_clk)
	if (!i_reset)
		o_valid <= 0;
	else
		o_valid <= (syncd && offset == 6'd39 && !dcd_illegal);

	always @(posedge i_clk)
	if (!i_reset)
		{ o_keyword, o_data } <= 0;
	else if (!syncd)
		{ o_keyword, o_data } <= 0;
	else if (syncd && offset == 6'd39)
		{ o_keyword, o_data } <= { dcd_ctrl, dcd_data };

	// Keep Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, ign_dcd_valid, ign_dcd_ready };
	// Verilator lint_on  UNUSED
	// }}}
endmodule
