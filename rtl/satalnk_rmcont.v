////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./rtl/satalnk_rmcont.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Removes align and continue primitives.  This includes all of
//		the "data" (i.e. not-primitives) following any continue
//	primitives, and just removing such data from the outgoing stream.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2021-2026, Gisselquist Technology, LLC
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
module	satalnk_rmcont #(
		parameter [0:0]	OPT_LOWPOWER = 1'b0
	) (
		// {{{
		input	wire		i_clk, i_reset,
		//
		input	wire		i_valid,
					i_primitive,
		input	wire	[31:0]	i_data,
		//
		output	reg		o_valid,
					o_primitive,
		output	reg	[31:0]	o_data
		// }}}
	);

	// Local declarations
	// {{{
`include "sata_primitives.vh"
	reg		r_active; // r_align;
	reg	[31:0]	r_last;
	// }}}

	initial	o_valid  = 0;
	initial	r_active = 0;
	always @(posedge i_clk)
	begin
		o_valid     <= i_valid;
		o_primitive <= r_active || i_primitive;
		o_data      <= (i_valid || !OPT_LOWPOWER) ? i_data : 32'h0;

		if (i_valid && { i_primitive, i_data } == P_ALIGN)
		begin
			o_valid <= 0;
			if (OPT_LOWPOWER)
				{ o_primitive, o_data } <= 33'h0;
		end

		if (i_valid && !i_primitive && r_active)
		begin
			o_valid <= 0;
			if (OPT_LOWPOWER)
				{ o_primitive, o_data } <= 33'h0;
		end

		if (i_valid && i_primitive)
		begin
			r_active <= 1'b0;
			if (i_data[31:0] == P_CONT[31:0]) begin
				r_active <= 1'b1;
				o_data 	 <= r_last;
				o_valid	 <= 1'b0;
				if (OPT_LOWPOWER)
				begin
					o_primitive <= 1'b0;
					o_data <= 32'h0;
				end
			end else begin
				r_last   <= i_data;
				// r_align  <= (i_data == P_ALIGN[31:0]);
				r_active <= 1'b0;
				// Always pass primitives forward
				o_data 	 <= i_data;
				if (OPT_LOWPOWER && i_data == P_ALIGN[31:0])
					o_data <= 0;
			end
		end else if (i_valid && r_active)
		begin
			// On any data, while P_CONT is active, repeat the
			// last primitive -- save that we'll drop o_valid,
			// to make it easier to cross clock domains
			o_data <= r_last;
			if (OPT_LOWPOWER)
				o_data <= 32'h0;
		end

		if (OPT_LOWPOWER)
			r_last <= 32'h0;

		if (OPT_LOWPOWER && (!i_valid || (r_active && !i_primitive)))
			{ o_primitive, o_data } <= 33'h0;

		if (i_reset)
		begin
			r_active <= 0;
			o_valid  <= 0;
			if (OPT_LOWPOWER)
			begin
				{ o_primitive, o_data } <= 33'h0;
			end
		end
	end
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
	reg	f_past_valid;
	(* anyconst *)	reg	[32:0]	fnvr_data;

	initial	f_past_valid = 0;
	always @(posedge i_clk)
		f_past_valid <= 1;

	always @(*)
	if (!f_past_valid)
		assume(i_reset);

	always @(posedge i_clk)
	if (!i_reset && r_active)
		assert(!o_valid);

	always @(posedge i_clk)
	if (i_valid)
		assume({ i_primitive, i_data } != fnvr_data);

	always @(posedge i_clk)
	if (!i_reset && o_valid)
	begin
		assume(fnvr_data[31:0] != 32'h0);
		assert({ o_primitive, o_data } != fnvr_data);
	end

	always @(posedge i_clk)
	if (!i_reset && o_valid)
	begin
		assert({ o_primitive, o_data } != P_ALIGN);
		assert({ o_primitive, o_data } != P_CONT);
	end

	always @(posedge i_clk)
	if (!i_reset && !$past(i_reset) && $past(i_valid))
	begin
		if ($past(i_primitive))
		begin
			assert(r_active == $past(i_data[31:0] == P_CONT[31:0]));
		end else begin
			assert($stable(r_active));
		end
	end

	always @(posedge i_clk)
	if (f_past_valid && OPT_LOWPOWER && !o_valid)
	begin
		assert(33'h0 == { o_primitive, o_data });
	end

`endif
// }}}
endmodule
