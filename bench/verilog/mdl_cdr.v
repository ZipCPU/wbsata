////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/verilog/mdl_cdr.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Clock and data recovery module, specifically designed and
//		modified to support SATA.  For non-AXI streams, simply
//	hold S_VALID=1 and M_READY=1.  For use with SATA, you can set
//	S_DATA[1] to an electric IDLE condition, and S_DATA[0] to one
//	wire from a differential pair.
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2024, Gisselquist Technology, LLC
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
module mdl_cdr #(
		// {{{
		parameter	SAMPLES_PER_BAUD = 5,
		parameter	PHASE_BITS = 20,
		parameter	DW = 2,	// Data width
		localparam	[PHASE_BITS:0]	CK_STEP_WIDE
			= { 1'b1, {(PHASE_BITS){1'b0}} } / SAMPLES_PER_BAUD,
		parameter [PHASE_BITS-1:0] CK_STEP
					= CK_STEP_WIDE[PHASE_BITS-1:0]

		// }}}
	) (
		// {{{
		input	wire		i_clk, i_reset,
		//
		input	wire		s_valid,
		output	wire		s_ready,
		input	wire [DW-1:0]	s_data,
		//
		output	reg		m_valid,
		input	wire		m_ready,
		output	reg		m_stb,
		output	reg [DW-1:0]	m_dat,
		output	wire		m_ck
		// }}}
	);

	// Local declarations
	// {{{
	localparam [PHASE_BITS-1:0]	HALF_PERIOD
			= { 2'b10, {(PHASE_BITS-2){1'b0}} } + CK_STEP;

	reg				tr_last;
	wire				tr_now, w_stb;
	reg	[PHASE_BITS-1:0]	ck_counter;
	wire	[PHASE_BITS-1:0]	ck_next;
	// }}}

	// tr_now, tr_last -- Transition detection
	// {{{
	initial	tr_last = 0;
	always @(posedge i_clk)
	if (i_reset)
		tr_last <= 0;
	else if (s_valid && s_ready)
		tr_last <= s_data;

	assign	tr_now = (s_data != tr_last);
	// }}}

	// w_stb, ck_next, ck_counter -- Clock tracking, ck_counter=cycle phase
	// {{{
	assign	{ w_stb, ck_next } = ck_counter + CK_STEP;

	always @(posedge i_clk)
	if (i_reset)
		ck_counter <= 0;
	else if (s_valid && s_ready)
	begin
		if (tr_now)
			ck_counter <= HALF_PERIOD + CK_STEP;
		else
			ck_counter <= ck_next;
	end
	// }}}

	generate if (OPT_RESAMPLE)
	begin : GEN_RESAMPLE
	end else begin : NO_RESAMPLE
		reg	r_stb;

		always @(posedge i_clk)
		if (i_reset)
			m_valid <= 0;
		else if (!m_valid || m_ready)
			m_valid <= s_valid;

		initial	r_stb = 0;
		always @(posedge i_clk)
		if (i_reset)
			r_stb <= 0;
		else if (s_valid && s_ready)
			r_stb <= (!tr_now) && w_stb;

		assign	m_ck = !ck_counter[PHASE_BITS-1];
	end endgenerate

	always @(posedge i_clk)
	if (i_reset)
		m_dat <= 0;
	else if (s_valid && s_ready && (!tr_now && w_stb))
		m_dat <= s_data;

	assign	s_ready = !m_valid || m_ready;

	// Keep Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0 };
	// Verilator lint_on  UNUSED
	// }}}
endmodule
