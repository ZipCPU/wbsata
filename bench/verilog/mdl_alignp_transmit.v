////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/mdl_alignp_transmit.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	
//
// Creator:	Sukru Uzun
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2025-2026, Gisselquist Technology, LLC
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
`timescale 1ns/1ps
// }}}
module mdl_alignp_transmit #(
		parameter WORD_SIZE = 40
	) (
		input	wire		i_clk,
		input	wire		i_reset,
		input	wire		i_elec_idle,
		input	wire [WORD_SIZE-1:0]	i_data_p,
		// output wire		o_ready,
		output	reg		o_tx_p,
		output	reg		o_tx_n
	);

	reg	[WORD_SIZE-1:0]		shift_reg;
	reg [$clog2(WORD_SIZE+1)-1:0]	bit_count;
	reg				r_idle;

	always @(*)
	if (!r_idle)
	begin
		// The top bit of the shift register is sent first, and
		// so assigned to o_tx_p
		o_tx_p =  shift_reg[WORD_SIZE-1];

		// The differential signal, o_tx_n, is always the inverse
		// of o_tx_p
		o_tx_n = !shift_reg[WORD_SIZE-1];
	end else begin
		o_tx_p = 1'bX;
		o_tx_n = 1'bX;
	end

	// Bit counter and associated shift register
	//	r_idle is true if we are supposed to be electrically idle
	initial	r_idle = 1'b1;
	always @(posedge i_clk or posedge i_reset)
	if (i_reset)
	begin
		shift_reg <= 40'h0; 
		bit_count <= 0;
		r_idle <= 1'b1;
	end else if (bit_count >= (WORD_SIZE-1))
	begin
		// Advance to the next word
		bit_count <= 0;
		r_idle <= i_elec_idle;
		shift_reg <= (i_elec_idle) ? 40'h0 : i_data_p;
	end else begin
		// Send the next bit
		bit_count <= bit_count + 1;
		// Veriyi sola kaydır
		shift_reg <= {shift_reg[WORD_SIZE-2:0], 1'b0};
	end
endmodule

