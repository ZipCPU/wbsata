////////////////////////////////////////////////////////////////////////////////
//
// Filename:	mdl_s10b8bw.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Decodes a 40bit 8b/10b encoded word.  S_DATA[39] is assumed to
//		have arrived *first* (big-endian), whereas M_DATA[7:0] is the
//	first byte out (little-endian).
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
module	mdl_s10b8bw #(
		parameter	OPT_REGISTERED = 1
	) (
		// {{{
		input	wire	i_clk, i_reset,
		//
		input	wire		S_VALID,
		output	wire		S_READY,	// *MUST* be one
		input	wire	[39:0]	S_DATA,
		//
		output	reg		M_VALID,
		input	wire		M_READY,
		output	reg		M_ILLEGAL, M_CTRL,
		output	reg	[31:0]	M_DATA
		// }}}
	);

	// Local declarations
	// {{{
	wire	[3:0]	w_ctrl;
	wire	[31:0]	w_data;
	wire		nxt_illegal, nxt_ctrl;
	wire	[31:0]	nxt_data;
	// }}}

	mdl_s10b8b
	u_b0 (
		.S_DATA(S_DATA[39:30]),
		.M_DATA({ w_ctrl[0], w_data[7:0] })
	);

	mdl_s10b8b
	u_b1 (
		.S_DATA(S_DATA[29:20]),
		.M_DATA({ w_ctrl[1], w_data[15:8] })
	);

	mdl_s10b8b
	u_b2 (
		.S_DATA(S_DATA[19:10]),
		.M_DATA({ w_ctrl[2], w_data[23:16] })
	);

	mdl_s10b8b
	u_b3 (
		.S_DATA(S_DATA[9:0]),
		.M_DATA({ w_ctrl[3], w_data[31:24] })
	);

	assign	nxt_illegal = S_VALID && ((|w_ctrl[3:1])
			|| (w_ctrl[0] && w_data[6:0] != 7'h7c));
	assign	nxt_ctrl = S_VALID && w_ctrl[0] && w_data[6:0] == 7'h7c;
	assign	nxt_data = S_VALID ? w_data : 32'h0;

	generate if (OPT_REGISTERED)
	begin : GEN_OUTPUT
		always @(posedge i_clk)
		if (i_reset)
			M_VALID <= 1'b0;
		else if (!M_VALID || M_READY)
			M_VALID <= S_VALID;

		always @(posedge i_clk)
		if (i_reset)
		begin
			M_ILLEGAL <= 1'b0;
			M_CTRL <= 1'b0;
			M_DATA <= 32'b0;
		end else if (!M_VALID || M_READY)
		begin
			M_ILLEGAL <= nxt_illegal;
			M_CTRL <= nxt_ctrl;
			M_DATA <= nxt_data;
		end
	end else begin : COMB_OUTPUT
		always @(*)
		begin
			M_VALID = S_VALID;

			M_ILLEGAL= nxt_illegal;
			M_CTRL   = nxt_ctrl;
			M_DATA   = nxt_data;
		end

		// Make Verilator happy
		// {{{
		// Verilator lint_off UNUSED
		wire	unused;
		assign	unused = &{ 1'b0, i_clk, i_reset };
		// Verilator lint_on  UNUSED
		// }}}
	end endgenerate

	assign	S_READY = !M_VALID || M_READY;
endmodule
