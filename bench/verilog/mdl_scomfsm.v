////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/mdl_scomfsm.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Implements the SATA COM handshake, from the perspective of
//		the device.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2022-2026, Gisselquist Technology, LLC
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
`default_nettype	none
`timescale 1ns / 1ps
// }}}
module	mdl_scomfsm #(
		parameter realtime	CLOCK_SYM_NS = 1000.0 / 1500.0
	) (
		// {{{
		input	wire		i_txclk, i_reset,
		output	reg		o_reset,
		// input wire		i_comfinish,
		// input wire		i_cominit_det, i_comwake_det,
		// input wire		i_oob_done, i_link_layer_up,
		input	wire		i_rx_p, i_rx_n,
		input	wire	[39:0]	i_tx_word,
		output	wire		o_tx_p, o_tx_n
		// }}}
	);

	// Local decalarations
	// {{{
	// localparam P_BITS = 40;
	// localparam [(P_BITS/4)-1:0] D21_4 = 10'b1010101101;
	// localparam [(P_BITS/4)-1:0] K28_3 = 10'b0011110011;
	// localparam [(P_BITS/4)-1:0] D21_5 = 10'b1010101010;

	// localparam [P_BITS-1:0] SYNC_P = { D21_5, D21_5, D21_4, K28_3 };

	// wire	w_comwake, w_comreset;
	wire	oob_done;
	// }}}

	// OOB
	// {{{
	mdl_oob
	u_oob (
		.i_clk(i_txclk),
		.i_reset(i_reset),
		.i_rx(i_rx_p),
		.i_data_word(i_tx_word),
		.o_done(oob_done),
		.o_tx_p(o_tx_p),
		.o_tx_n(o_tx_n)
	);
	// }}}

/*
	mdl_srxcomsigs #(
		.OVERSAMPLE(4), .CLOCK_SYM_NS(CLOCK_SYM_NS)
	) u_comdet (
		.i_clk(i_txclk),
		.i_reset(i_reset),
		.i_rx_p(i_rx_p), .i_rx_n(i_rx_n),
		// .i_cominit_det(i_cominit_det), .i_comwake_det(i_comwake_det),
		.o_comwake(w_comwake), .o_comreset(w_comreset)
	);
*/

	always @(posedge i_txclk or i_reset)
	if (i_reset)
	begin
		o_reset <= 1'b1;
	end else if (oob_done)
		o_reset <= 1'b0;

	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0 };
	// Verilator lint_on  UNUSED
endmodule
