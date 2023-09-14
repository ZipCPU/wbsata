////////////////////////////////////////////////////////////////////////////////
//
// Filename:	mdl_s8b10b.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	An 8B/10B Encoder: receives 8bits at a time, produces 10bits
//		at the output with exceptions.  This encoder is designed to be
//	used as a component of a 32-bit encoder.  Hence, clock and reset are
//	expected to be handled externally.
//
//	S_DATA[9]	: Previous running disparity
//	S_DATA[8]	: Control code indicator.  Since SATA only supports
//			two control codes, S_DATA[7:0] must then either be
//			8'h7c or 8'hbc.
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
module	mdl_s8b10b (
		input	wire	[9:0]	S_DATA,
		//
		output	wire	[10:0]	M_DATA	// Bit[9] TX FIRST, Bit[0] Last
	);

	// Local declarations
	// {{{
	wire		rd = S_DATA[9];

	reg		r_6d, r_nd;	// Running disparity
	reg	[5:0]	r_6b;
	reg	[3:0]	r_4b;
	reg	[10:0]	encoded;
	// }}}

	always @(*)
	case(S_DATA[4:0])	// = EDCBA
	5'h00: { r_6b, r_6d } = { (rd) ? 6'b011_000 : 6'b100_111, !rd };
	5'h01: { r_6b, r_6d } = { (rd) ? 6'b100_010 : 6'b011_101, !rd };
	5'h02: { r_6b, r_6d } = { (rd) ? 6'b010_010 : 6'b101_101, !rd };
	5'h03: { r_6b, r_6d } = { 6'b110_001, rd };
	5'h04: { r_6b, r_6d } = { (rd) ? 6'b001_010 : 6'b110_101, !rd };
	5'h05: { r_6b, r_6d } = { 6'b101_001, rd };
	5'h06: { r_6b, r_6d } = { 6'b011_001, rd };
	5'h07: { r_6b, r_6d } = { (rd) ? 6'b000_111 : 6'b111_000,  rd };
	5'h08: { r_6b, r_6d } = { (rd) ? 6'b000_110 : 6'b111_001, !rd };
	5'h09: { r_6b, r_6d } = { 6'b100_101, rd };
	5'h0a: { r_6b, r_6d } = { 6'b010_101, rd };
	5'h0b: { r_6b, r_6d } = { 6'b110_100, rd };
	5'h0c: { r_6b, r_6d } = { 6'b001_101, rd };
	5'h0d: { r_6b, r_6d } = { 6'b101_100, rd };
	5'h0e: { r_6b, r_6d } = { 6'b011_100, rd };
	5'h0f: { r_6b, r_6d } = { (rd) ? 6'b101_000 : 6'b010_111, !rd };
	//
	5'h10: { r_6b, r_6d } = { (rd) ? 6'b100_100 : 6'b011_011, !rd };
	5'h11: { r_6b, r_6d } = { 6'b100_011, rd };
	5'h12: { r_6b, r_6d } = { 6'b010_011, rd };
	5'h13: { r_6b, r_6d } = { 6'b110_010, rd };
	5'h14: { r_6b, r_6d } = { 6'b001_011, rd };
	5'h15: { r_6b, r_6d } = { 6'b101_010, rd };
	5'h16: { r_6b, r_6d } = { 6'b011_010, rd };
	5'h17: { r_6b, r_6d } = { (rd) ? 6'b000_101 : 6'b111_010, !rd };
	5'h18: { r_6b, r_6d } = { (rd) ? 6'b001_100 : 6'b110_011, !rd };
	5'h19: { r_6b, r_6d } = { 6'b100_110, rd };
	5'h1a: { r_6b, r_6d } = { 6'b010_110, rd };
	5'h1b: { r_6b, r_6d } = { (rd) ? 6'b001_001 : 6'b110_110, !rd };
	5'h1c: { r_6b, r_6d } = { 6'b001_110, rd };
	5'h1d: { r_6b, r_6d } = { (rd) ? 6'b010_001 : 6'b101_110, !rd };
	5'h1e: { r_6b, r_6d } = { (rd) ? 6'b100_001 : 6'b011_110, !rd };
	5'h1f: { r_6b, r_6d } = { (rd) ? 6'b010_100 : 6'b101_011, !rd };
	endcase

	always @(*)
	case(S_DATA[7:5])	// = HGF
	3'h0: { r_4b, r_nd } = { (r_6d) ? 4'b0100 : 4'b1011, !r_6d };
	3'h1: { r_4b, r_nd } = { 4'b1001, r_6d };
	3'h2: { r_4b, r_nd } = { 4'b0101, r_6d };
	3'h3: { r_4b, r_nd } = { (r_6d) ? 4'b0011 : 4'b1100,  r_6d };
	3'h4: { r_4b, r_nd } = { (r_6d) ? 4'b0010 : 4'b1101, !r_6d };
	3'h5: { r_4b, r_nd } = { 4'b1010, r_6d };
	3'h6: { r_4b, r_nd } = { 4'b0110, r_6d };
	3'h7: { r_4b, r_nd } = ((r_6d && r_6b[1:0] == 2'b0)
					|| (!r_6d && r_6b[1:0] == 2'b11))
				? { (r_6d) ? 4'b1000 : 4'b0111, !r_6d }
				: { (r_6d) ? 4'b0001 : 4'b1110, !r_6d };
	endcase

	always @(*)
	case(S_DATA[8:7])
	2'b10: encoded = { !rd, (!rd) ? { 6'b001_111, 4'b0011 }
					: { 6'b110_000, 4'b1100 } };
	2'b11: encoded = { !rd, (!rd) ? { 6'b001_111, 4'b1010 }
					: { 6'b110_000, 4'b0101 } };
	default: encoded = { r_nd, r_6b, r_4b };
	endcase

	// Outoing bits are abcdeifghj -- "a" is transmitted first, and notice
	//	that the "i" is out of place,
	// so we remap here from abcdefghij to abcdeifghj
	//                       9876543210    9876514320
	assign	M_DATA  = encoded;

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
	(* keep *)	wire	[4:0]	abcdei = r_6b;
	(* keep *)	wire	[3:0]	fghj = r_4b;
	(* keep *)	wire	[4:0]	Dx = S_DATA[4:0];
	(* keep *)	wire	[2:0]	Dy = S_DATA[7:5];

	always @(*)
	if (S_DATA[8])
		assume(S_DATA[7:0] == 8'h7c || S_DATA[7:0] == 8'hbc);

	always @(*)
	if (!rd && S_DATA[8:0] == 9'h04a)	// D10.2
		assert({ r_6b, r_4b, r_nd } == { 6'b010101, 4'b0101, 1'b0 });

	always @(*)
	if ( rd && S_DATA[8:0] == 9'h0eb)	// D11.7
		assert({ r_6b, r_4b, r_nd } == { 6'b110100, 4'b1000, 1'b0 });
`endif
// }}}
endmodule
