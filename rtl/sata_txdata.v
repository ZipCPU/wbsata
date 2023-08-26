////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	sata/sata_txdata.v
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
`default_nettype none
// }}}
module	sata_txdata #(
		localparam	DW = 32
	) (
		// {{{
		input	wire		i_clk, i_reset,
		//
		input	wire	[3:0]	i_cfg_port,	// == 4'h0
		//
		input	wire		S_VALID,
		output	wire		S_READY,
		input	wire [DW-1:0]	S_DATA,
		input	wire		S_LAST,
		//
		output	wire		M_VALID,
		input	wire		M_READY,
		output	wire [DW-1:0]	M_DATA,
		output	wire		M_LAST
		// }}}
	);

	localparam	FIS_DATA_WORD = 32'h0000_0046;
	reg		m_valid, m_last;
	reg	[DW-1:0]	m_data;
	reg	[10:0]	pkt_posn;
	reg		r_first;

	reg	[31:0]	fis_data_word;

	always @(*)
	begin
		fis_data_word = FIS_DATA_WORD;
		fis_data_word[11:8] = i_cfg_port;
	end

	// r_first
	// {{{
	initial	r_first = 1;
	always @(posedge i_clk)
	if (i_reset)
		r_first <= 1;
	else if (S_VALID && S_READY)
		r_first <= S_LAST || (&pkt_posn);
	else if (S_VALID)
		r_first <= 1'b0;
	// }}}

	// pkt_posn -- keep track of where we are in a packet
	// {{{
	initial	pkt_posn = 0;
	always @(posedge i_clk)
	if(i_reset)
		pkt_posn <= 0;
	else if (S_VALID && S_READY)
	begin
		pkt_posn <= pkt_posn + 1;
		if (S_LAST || r_first)
			pkt_posn <= 0;
	end
	// }}}

	// m_valid
	// {{{
	always @(posedge i_clk)
	if(i_reset)
		m_valid <= 0;
	else if (!M_VALID || M_READY)
		m_valid <= S_VALID && (r_first || S_READY);

	always @(posedge i_clk)
	if (!M_VALID || M_READY)
	begin
		if (r_first)
			m_data <= fis_data_word;
		else
			m_data <= S_DATA;
	end

	always @(posedge i_clk)
	if(i_reset)
		m_last <= 0;
	else if (!M_VALID || M_READY)
		m_last <= !r_first && (S_LAST || (&pkt_posn));

	assign	M_VALID = m_valid;
	assign	M_DATA  = m_data;
	assign	M_LAST  = m_last;
	assign	S_READY = (!M_VALID || M_READY) && !r_first;
endmodule
