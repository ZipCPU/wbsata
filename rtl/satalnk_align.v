////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./rtl/satalnk_align.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Adds ALIGN primitives to the outgoing data stream.  Also, if
//		so configured, will issue CONT primitives with scrambled data.
//
// Rules:
//	1. All primitives must be repeated at least twice
//	2. Every N outputs shall be ALIGN primitives
//	3. If any primitive is repeated more than twice, and this IP is so
//			enabled,
//		4. The third repeat should be replaced with CONT
//		5. Fourth and subsequent repeats should be scrambled
//		6. On a new data, the last primitive of the repeated sequence
//			should be passed through without replacement before
//			allowing the data through
//		7. On a new primitive, we don't need to repeat the last
//			primitive
//	8. Data should be passed through.
//
//	No assumption(s) may be made regarding incoming primtives.  They may
//	(or may not) be repeated on input.  We'll need to guarantee they get
//	repeated if they are not repeated on input.
//
//	Incoming ready
//		IF NOT time for ALIGNMENT
//		&& (incoming primitive && (either it repeats
//			|| the last primitive has already been repeated)
//		&& (we have incoming data && the last primitive has been
//			repeated twice again)
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
module	satalnk_align #(
		// {{{
		parameter	[0:0]	OPT_LITTLE_ENDIAN = 0,
		parameter	[15:0]	INITIAL_SCRAMBLER = 16'hffff,
		parameter	[15:0]	SCRAMBLER_POLY = 16'ha011,
`ifdef	FORMAL
		parameter	[0:0]	OPT_SKIDBUFFER = 1'b0,
`else
		parameter	[0:0]	OPT_SKIDBUFFER = 1'b1,
`endif
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
	localparam [3:0]	S_ALIGN1 =	4'd0,
				S_ALIGN2 =	4'd1,
				S_PRIMITIVE1 =	4'd2,
				S_PRIMITIVE2 =	4'd3,
				S_CONT =	4'd4,
				S_SCRAMBLED =	4'd5,
				S_RPT1 =	4'd6,
				S_RPT2 =	4'd7,
				S_DATA =	4'd8;
	reg	[3:0]	fsm_state, next_fsm;
	reg		skd_ready;
	wire	[32:0]	skd_data;
	reg	[32:0]	next_data;

	reg	[31:0]	last_primitive;

	reg		align_trigger, need_repeat;
	reg	[$clog2(ALIGN_TIMEOUT+1)-1:0]	align_counter;
	reg	[15:0]	align_fill;
	wire	[15:0]	next_state;
	wire	[31:0]	next_mask;
	// }}}

	generate if (OPT_SKIDBUFFER)
	begin : GEN_SKIDBUFFER
		// {{{
		reg	i_ready;
		wire	ign_skd_valid;

		initial	i_ready = 1'b0;
		always @(posedge i_clk)
		if (i_reset)
			i_ready <= 1'b0;
		else
			i_ready <= 1'b1;

		sata_skid #(
			.DW(33), .OPT_OUTREG(1'b0)
		) u_skid (
			.i_clk(i_clk), .i_reset(i_reset),
			.i_valid(i_ready), .o_ready(s_ready),
				.i_data(s_data),
			.o_valid(ign_skd_valid), .i_ready(skd_ready),
				.o_data(skd_data)
		);

		// Verilator lint_off UNUSED
		wire	unused_valid;
		assign	unused_valid = &{ 1'b0, ign_skd_valid };
		// Verilator lint_on  UNUSED
		// }}}
	end else begin : NO_SKIDBUFFER
		assign	s_ready  = skd_ready;
		assign	skd_data = s_data;
	end endgenerate

	assign	next_mask = NEXT_SCRAMBLER_MASK(align_fill);
	assign	next_state= NEXT_SCRAMBLER_STATE(align_fill);

	// align_trigger, align_counter
	// {{{
	initial	align_counter = 0;
	initial	align_trigger = 1'b1;
	always @(posedge i_clk)
	if (i_reset)
	begin
		align_counter <= 0;
		align_trigger <= 1'b1;
	end else if (align_trigger)
	begin
		align_counter <= ALIGN_TIMEOUT;
		align_trigger <= 1'b0;
	end else begin
		align_counter <= align_counter - 1;
		align_trigger <= (align_counter <= 1);
	end
	// }}}

	////////////////////////////////////////////////////////////////////////
	//
	// The giant state machine: fsm_state, skd_ready, o_primitive, o_data
	// {{{
	always @(*)
	begin
		next_fsm = fsm_state;
		next_data  = { o_primitive, o_data };
		skd_ready = 1;

		if (align_trigger)
		begin
			// {{{
			next_fsm = S_ALIGN1;
			next_data  = P_ALIGN;
			skd_ready = 0;
			// }}}
		end else case(fsm_state)
		S_ALIGN1: begin
			// {{{
			next_fsm = S_ALIGN2;
			next_data  = P_ALIGN;
			skd_ready = 0;
			end
			// }}}
		S_ALIGN2: begin
			// {{{
			next_fsm   = need_repeat ? S_RPT1
				: skd_data[32] ? S_PRIMITIVE1 : S_DATA;
			if (need_repeat)
			begin
				next_fsm   = S_RPT1;
				next_data  = { 1'b1, last_primitive };
			end else begin
				if (skd_data[32])
					next_fsm   = S_PRIMITIVE1;
				else
					next_fsm   = S_DATA;

				next_data  = skd_data;
				skd_ready = 1'b1;
			end end
			// }}}
		S_PRIMITIVE1: begin
			// {{{
			next_fsm   = S_PRIMITIVE2;
			next_data  = { o_primitive, o_data };
			skd_ready = 1'b0;
			end
			// }}}
		S_PRIMITIVE2: begin
			// {{{
			next_fsm   = !skd_data[32] ? S_DATA
				:(i_cfg_continue_en && skd_data[31:0] == o_data)
				? S_CONT : S_PRIMITIVE1;
			next_data  = skd_data;
			if (skd_data[32] && i_cfg_continue_en
						&& skd_data[31:0] == o_data)
				next_data = P_CONT;
			skd_ready = 1'b1;
			end
			// }}}
		S_CONT: begin
			// {{{
			next_fsm   = !skd_data[32] ? S_RPT1
					: (skd_data[31:0] == o_data)
					? S_SCRAMBLED : S_PRIMITIVE1;
			skd_ready = 1'b0;
			if (!skd_data[32])
				next_data  = { 1'b1, last_primitive };
			else if (skd_data[31:0] == o_data)
			begin
				next_data  = { 1'b0, next_mask };
				skd_ready  = 1'b1;
			end else begin
				next_data  = skd_data;
				skd_ready  = 1'b1;
			end end
			// }}}
		S_SCRAMBLED: begin
			// {{{
			next_fsm   = !skd_data[32] ? S_RPT1
					: (skd_data[31:0] == o_data)
					? S_SCRAMBLED : S_PRIMITIVE1;
			next_data  = { 1'b0, next_mask };
			if (!skd_data[32])
			begin
				next_data  = { 1'b1, last_primitive };
				skd_ready = 1'b0;
			end else if (skd_data[31:0] == o_data)
			begin
				next_data  = { 1'b0, next_mask };
				skd_ready  = 1'b1;
			end else begin
				next_data  = skd_data;
				skd_ready  = 1'b1;
			end end
			// }}}
		S_RPT1: begin
			// {{{
			next_fsm   = S_RPT2;
			next_data  = { 1'b1, last_primitive };
			skd_ready = 1'b0;
			end
			// }}}
		S_RPT2: begin
			// {{{
			next_fsm   = S_DATA;
			next_data  = skd_data;
			skd_ready = 1'b1;
			end
			// }}}
		S_DATA: begin
			// {{{
			next_fsm   = (skd_data[32]) ? S_PRIMITIVE1 : S_DATA;
			next_data  = skd_data;
			skd_ready = 1'b1;
			end
			// }}}
		default: begin
			// {{{
			next_fsm = S_ALIGN1;
			next_data  = P_ALIGN;
			skd_ready = 0;
			end
			// }}}
		endcase
	end

	initial	{ o_primitive, o_data } = P_ALIGN;
	initial	fsm_state = S_ALIGN1;
	always @(posedge i_clk)
	if (i_reset)
	begin
		{ o_primitive, o_data } <= P_ALIGN;
		fsm_state <= S_ALIGN1;

		need_repeat <= 1'b0;
	end else begin
		{ o_primitive, o_data } <= next_data;
		fsm_state <= next_fsm;
		if (skd_ready && s_data[32])
			last_primitive <= s_data[31:0];

		need_repeat <= 1'b0;
		if (align_trigger)
		begin
			case(fsm_state)
			S_ALIGN1:	need_repeat <= need_repeat;
			S_ALIGN2:	need_repeat <= need_repeat;
			S_PRIMITIVE1:   need_repeat <= 1'b1;
			S_PRIMITIVE2:   need_repeat <= 1'b0;
			S_CONT:		need_repeat <= 1'b0;
			S_SCRAMBLED:	need_repeat <= 1'b0;
			S_DATA:		need_repeat <= 1'b0;
			S_RPT1:		need_repeat <= 1'b1;
			S_RPT2:		need_repeat <= 1'b0;
			default:	need_repeat <= 1'b0;
			endcase
		end
	end
	// }}}

	// align_fill -- the scrambler fill
	// {{{
	initial	align_fill = INITIAL_SCRAMBLER;
	always @(posedge i_clk)
	if (i_reset)
		align_fill <= INITIAL_SCRAMBLER;
	else if (align_trigger || fsm_state != S_SCRAMBLED)
		align_fill <= INITIAL_SCRAMBLER;
	else
		align_fill  <= next_state;
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
	reg		f_past_valid;
	wire		i_primitive;
	wire	[31:0]	i_data;
	(* anyconst *)	reg	f_en;
	(* anyconst *)	reg	[31:0]	fnvr_data;
	reg	[32:0]	f_p0, f_p1, f_p2;

	assign	i_primitive = s_data[32];
	assign	i_data = s_data[31:0];

	initial	f_past_valid = 1'b0;
	always @(posedge i_clk)
		f_past_valid <= 1'b1;

	always @(*)
	if (!f_past_valid)
		assume(i_reset);

	always @(*)
		assume(f_en == i_cfg_continue_en);

	// Incoming ready/valid stability
	// {{{
	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
	end else if ($past(!s_ready))
		assume($stable(s_data));
	// }}}

	// Align counter checking
	// {{{
	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
		assert(align_counter == 0);
		assert(align_trigger);
	end else if ($past(align_trigger))
	begin
		assert(align_counter == ALIGN_TIMEOUT);
		assert(!align_trigger);
	end else begin
		assert(align_counter < ALIGN_TIMEOUT);
		assert(align_trigger == (align_counter == 0));
	end

	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset) || $past(align_trigger))
	begin
		assert({ o_primitive, o_data } == P_ALIGN);
	end
	// }}}

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && $past(skd_ready))
	begin
		if (!$past(i_primitive))
			assert({ o_primitive, o_data }=={ 1'b0, $past(i_data)});
	end

	always @(*)
		assert(align_fill != 0);

	always @(*)
	begin
		assume(s_data != P_ALIGN);
		assume(s_data != P_CONT);
		assume(s_data != { 1'b0, fnvr_data });
	end

	initial	{ f_p2, f_p1, f_p0 } = {(3){P_ALIGN}};
	always @(posedge i_clk)
	if (!f_past_valid || i_reset)
	begin
		{ f_p2, f_p1, f_p0 } = {(3){P_ALIGN}};
	end else begin
		{ f_p2, f_p1, f_p0 } <= { f_p1, f_p0, o_primitive, o_data };
	end

	always @(posedge i_clk)
	if (f_p2 == P_ALIGN)
	begin
	end else if (!o_primitive || o_data != P_ALIGN[31:0])
	begin
		// Never repeat a primitive more than twice
		if (f_p1 == f_p0 && f_p0[32] && f_en)
			assert(!o_primitive || o_data[31:0] != f_p0[31:0]
					|| o_data == P_CONT[31:0]);

		// Always repeat each primitive (except P_CONT) at least twice
		if (f_p1 != f_p0 && f_p0[32] && f_p0 != P_CONT)
			assert(f_p0 == { o_primitive, o_data });
	end

	always @(posedge i_clk)
	if (f_past_valid && fsm_state == S_DATA)
		assert(o_primitive || o_data != fnvr_data);

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && $past(skd_ready))
	begin
		if (!$past(skd_data[32]))
		begin
			assert(!o_primitive && o_data == $past(skd_data[31:0]));
		end else if (o_primitive)
		begin
			assert(o_data == $past(skd_data[31:0])
				|| (last_primitive == $past(skd_data[31:0])
					&& o_data == P_CONT[31:0]));
		end
	end
	////////////////////////////////////////////////////////////////////////
	//
	// State machine checking
	// {{{
	always @(posedge i_clk)
	if (f_past_valid)
	case(fsm_state)
	S_ALIGN1: assert({ o_primitive, o_data } == P_ALIGN);
	S_ALIGN2: assert({ o_primitive, o_data } == P_ALIGN);
	S_PRIMITIVE1: assert(o_primitive);
	S_PRIMITIVE2: begin
			assert(o_primitive);
			assert($stable(o_data));
			end
	S_CONT: begin
		assert(o_primitive);
		assert(o_data == P_CONT[31:0]);
		end
	S_SCRAMBLED: assert(!o_primitive);
	S_RPT1: assert(o_primitive && o_data == last_primitive);
	S_RPT2: assert(o_primitive && o_data == last_primitive);
	S_DATA: assert(!o_primitive);
	default: assert(0);
	endcase
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// "Careless" assumptions
	// {{{
	always @(*)
		assume(f_en);
	// }}}
`endif
// }}}
endmodule
