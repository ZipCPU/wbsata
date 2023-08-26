////////////////////////////////////////////////////////////////////////////////
//
// Filename:
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
// }}}
module	sata_pextend #(
		parameter	COUNTS = 4
	) (
		input	wire	i_clk, i_reset,
		input	wire	i_sig,
		output	reg	o_sig
	);

	localparam	LGCOUNTS = $clog2(COUNTS+1);
	reg	[LGCOUNTS-1:0]	counter;

	always @(posedge i_clk)
	if (i_reset)
	begin
		counter <= 0;
		o_sig <= 1'b0;
	end else if (counter != 0)
	begin
		counter <= counter -1;
		o_sig <= (counter > 1);
		if (i_sig && counter == 1)
		begin
			counter <= 1;
			o_sig <= 1'b1;
		end
	end else if (i_sig)
	begin
		counter <= COUNTS;
		o_sig <= 1'b1;
	end

endmodule
