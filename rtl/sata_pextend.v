////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./rtl/sata_pextend.v
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
`default_nettype none
`timescale	1ns/1ps
// }}}
module	sata_pextend (
		input	wire	i_clk, i_reset,
		input	wire	i_sig,
		output	reg	o_sig
	);

	(* ASYNC_REG = "TRUE" *)
	reg	[2:0]	sreg;
	(* ASYNC_REG = "TRUE" *)
	reg		cdc_xpipe;
	wire		trigger;

	assign	trigger = i_sig && !i_reset;

	always @(posedge i_clk or posedge trigger)
	if (trigger)
		sreg <= 3'h7;
	else
		sreg <= { sreg[1:0], 1'b0 };

	always @(posedge i_clk)
	if (i_reset)
		{ o_sig, cdc_xpipe } <= 2'b0;
	else
		{ o_sig, cdc_xpipe } <= { cdc_xpipe, sreg[2] };

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
	// This IP has been rewritten since it was last formally verified.
`endif
// }}}
endmodule
