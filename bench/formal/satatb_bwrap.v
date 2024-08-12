////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/formal/satatb_bwrap.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Verify that the tables are invertable
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
// }}}
module	satatb_bwrap (
		input	wire	[9:0]	i_data,
		output	wire	[8:0]	o_data
	);

	wire		valid_input;
	wire	[10:0]	w_data;

	satatb_8b10b
	u_8b10b (
		.S_DATA(i_data),
		.M_DATA(w_data)
	);

	satatb_10b8b
	u_10b8b (
		.S_DATA(w_data),
		.M_DATA(o_data)
	);

	assign	valid_input = !i_data[8] || i_data == { 3'h7, 5'd28 }
				|| i_data[7:0] == { 3'h5, 5'd28 };
	
	always @(*)
	if (valid_input)
	begin
		assert(o_data[8:0] == i_data[8:0]);
		assert(o_data != 9'h1ff);
	end

	// else if (o_data[8])
		// assert(o_data == 9'h1ff);

endmodule
