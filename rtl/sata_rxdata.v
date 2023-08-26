////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	sata/sata_rxdata.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Create an AXI Stream of data by stringing DATA FIS's together,
//	removing the first word of each packet, and forwarding the packet
//	downstream.  The stream ends when the first word of the next packet
//	is not a data FIS.
//
// Status:
//	Lint check:		Yes
//	Formal check:		NO
//	Simulation check:	NO
//	Hardware check:		NO
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
module	sata_rxdata #(
		// {{{
		parameter [0:0]	OPT_LOWPOWER = 0,
		parameter	DW = 32
		// }}}
	) (
		// {{{
		input	wire		i_clk, i_reset,
		//
		input	wire			S_VALID,
		output	wire			S_READY,
		input	wire	[DW-1:0]	S_DATA,
		input	wire			S_LAST,
		input	wire			S_ABORT,
		//
		output	wire			M_VALID,
		input	wire			M_READY,
		output	wire	[DW-1:0]	M_DATA,
		output	wire	[$clog2(DW/8+1)-1:0]	M_BYTES,
		output	wire			M_LAST
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[7:0]	FIS_DATA = 8'h46;
	wire	abort_valid;
	reg	s_sop;

	reg			r_valid, r_active, r_last;
	reg	[DW-1:0]	r_data;

	reg			m_valid, m_last;
	reg	[DW-1:0]	m_data;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// S_
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// s_sop -- true on the first beat of any incoming packet
	initial	s_sop = 1;
	always @(posedge i_clk)
	if (i_reset)
		s_sop <= 1'b1;
	else if (abort_valid)
		s_sop <= 1'b1;
	else if (S_VALID && S_READY)
		s_sop <= S_LAST;

	assign	abort_valid = (S_VALID && S_READY && S_ABORT)
						|| (!S_VALID && S_ABORT);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// R_
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// r_active
	// {{{
	always @(posedge i_clk)
	if (i_reset)
		r_active <= 1'b0;
	else if (abort_valid)
		r_active <= 1'b0;
	else if (S_VALID && S_READY && s_sop)
		r_active <= (S_DATA[7:0] == FIS_DATA);
	// }}}

	// r_valid
	// {{{
	initial	r_valid = 1'b0;
	always @(posedge i_clk)
	if (i_reset)
		r_valid <= 1'b0;
	else if (abort_valid && r_valid)
		r_valid <= (M_VALID && !M_READY);
	else if (S_VALID && S_READY && r_active)
		r_valid <= 1'b1;
	else if ((!M_VALID || M_READY) && S_VALID)
		r_valid <= 1'b0;
	// }}}

	// r_data
	// {{{
	initial r_data = 0;
	always @(posedge i_clk)
	if (i_reset && OPT_LOWPOWER)
		r_data <= 0;
	else if (S_VALID && S_READY && r_active)
		r_data <= S_DATA;
	// }}}

	// r_last, r_data
	// {{{
	initial	r_last = 0;
	always @(posedge i_clk)
	if (i_reset && OPT_LOWPOWER)
		r_last <= 0;
	else if (r_valid && abort_valid)
		r_last <= 1;
	else if (S_VALID && S_READY && r_active)
		r_last <= S_LAST;
	// }}}

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// M_
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	initial	m_valid = 1'b0;
	always @(posedge i_clk)
	if (i_reset)
		m_valid <= 0;
	else if (!M_VALID || M_READY)
		m_valid <= r_valid && S_VALID;

	initial	m_last = 1'b0;
	always @(posedge i_clk)
	if (i_reset)
		{ m_last, m_data } <= 0;
	else if (!M_VALID || M_READY)
	begin
		m_data <= r_data;
		m_last <= r_valid && r_last
				&& S_VALID && S_DATA[7:0] != FIS_DATA;
		if ((S_VALID && S_READY && S_ABORT) || (!S_VALID && S_ABORT))
			m_last <= 1'b1;
	end

	assign	M_VALID = m_valid;
	assign	M_DATA  = m_data;
	assign	M_LAST  = m_last;
	// Verilator lint_off WIDTH
	assign	M_BYTES = DW/8;
	// Verilator lint_on  WIDTH

	// }}}

	assign	S_READY = !r_valid || !M_VALID || M_READY;
endmodule
