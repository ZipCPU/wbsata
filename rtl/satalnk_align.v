////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	rtl/sata/satalnk_align.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Adds ALIGN primitives to the outgoing data stream.  Also, if
//		so configured, will issue CONT primitives with scrambled data.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2021-2023, Gisselquist Technology, LLC
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
module	satalnk_align #(
		// {{{
		parameter	[0:0]	OPT_LITTLE_ENDIAN = 0,
		parameter	[15:0]	INITIAL_SCRAMBLER = 16'hffff,
		parameter	[15:0]	SCRAMBLER_POLY = 16'ha011,
		// ALIGN primitives must be sent at most 256 DWORDs apart
		//  P_ALIGN,P_ALIGN,(Up to 256 DWORDS),P_ALIGN,P_ALIGN
		parameter		ALIGN_TIMEOUT = 257,
		parameter	[32:0]	P_CONT  = 33'h17caa9999,
					P_ALIGN = 33'h1bc4a4a7b
		// }}}
	) (
		// {{{
		input	wire		i_clk, i_reset,
		input	wire		i_cfg_continue_en,
		// Link interface: the output stream
		// {{{
		// input wire		s_valid, // We are always valid
		output	wire		s_ready,
		input	wire	[32:0]	s_data,
		// }}}
		// PHY (TX) interface
		// {{{
		output	reg		o_primitive,
		output	reg	[31:0]	o_data
		// }}}
		// }}}
	);

	// Local declarations
	// {{{
	reg	[32:0]	last_pdata;
	reg		align_repeat, last_palign, align_continued, align_ready;
	reg	[$clog2(ALIGN_TIMEOUT+1)-1:0]	align_counter;
	reg	[15:0]	align_fill;
	// }}}

	assign	s_ready = align_ready;

	// Generate P_CONT and P_ALIGN primitives
	// {{{
	always @(posedge i_clk)
	begin
		align_repeat <= s_data[32] && s_data == last_pdata
				&& i_cfg_continue_en;

		if (!align_ready)
		begin // P_ALIGN insertion
			// {{{
			{ o_primitive, o_data } <= P_ALIGN;
			align_ready <= ({ o_primitive, o_data } == P_ALIGN);
			last_pdata <= P_ALIGN;
			align_repeat <= 0;
			// }}}
		end else if (last_pdata == s_data && align_repeat
			&& i_cfg_continue_en)
		begin // Scrambled repeats
			// {{{
			align_continued <= 1;
			if (align_continued)
			begin
				o_primitive <= 0;
				o_data      <= NEXT_SCRAMBLER_MASK(align_fill);
				align_fill <= NEXT_SCRAMBLER_STATE(align_fill);
			end else begin
				{ o_primitive, o_data } <= P_CONT;
				align_fill <= INITIAL_SCRAMBLER;
			end
			// }}}
		end else begin // Normal pass-through operation
			{ o_primitive, o_data } <= s_data;
			align_continued <= 0;
			align_fill <= INITIAL_SCRAMBLER;
		end

		last_pdata <= s_data;
		if ({ o_primitive, o_data } == P_ALIGN)
			last_palign <= 1'b1;

		// align_counter, align_ready
		// {{{
		if ({ o_primitive, o_data } == P_ALIGN)
		begin
			align_counter <= ALIGN_TIMEOUT;
			align_ready   <= last_palign;
		end else begin
			align_counter <= align_counter - 1;
			align_ready   <= (align_counter > 1);
		end
		// }}}

		if (i_reset)
		begin
			align_repeat <= 1'b0;
			last_palign  <= 1'b0;
			{ o_primitive, o_data } <= P_ALIGN;
			align_counter <= ALIGN_TIMEOUT;
		end
	end
	// }}}

	function [15:0]	NEXT_SCRAMBLER_STATE(input [15:0] i_state);
		// {{{
		integer		ik;
		reg	[15:0]	fill;
	begin
		fill = i_state;
		for(ik=0; ik<32; ik=ik+1)
		begin
			if (i_state[15])
				fill = { i_state[14:0], 1'b0 }
							^ SCRAMBLER_POLY;
			else
				fill = { i_state[14:0], 1'b0 };
		end

		NEXT_SCRAMBLER_STATE = fill;
	end endfunction
	// }}}

	function [31:0]	NEXT_SCRAMBLER_MASK(input [15:0] i_state);
		// {{{
		integer		ik;
		reg	[15:0]	fill;
		reg	[31:0]	out;
	begin
		fill = i_state;
		for(ik=0; ik<32; ik=ik+1)
		begin
			out[ik] = fill[15];

			if (i_state[15])
				fill = { fill[14:0], 1'b0 } ^ SCRAMBLER_POLY;
			else
				fill = { fill[14:0], 1'b0 };
		end

		NEXT_SCRAMBLER_MASK = SWAP_ENDIAN(out);
	end endfunction
	// }}}

	function [31:0] SWAP_ENDIAN(input [31:0] i_data);
		// {{{
	begin
		if (!OPT_LITTLE_ENDIAN)
			SWAP_ENDIAN = { i_data[7:0], i_data[15:8], i_data[23:16], i_data[31:24] };
		else
			SWAP_ENDIAN = i_data;
	end endfunction
	// }}}
endmodule
