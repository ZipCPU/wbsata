////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/satalnk_txpacket.v
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
// Copyright (C) 2021-2024, Gisselquist Technology, LLC
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
`default_nettype	none
`timescale	1ns/1ps
// }}}
module	satalnk_txpacket #(
		// {{{
		parameter	[0:0]	OPT_LITTLE_ENDIAN = 0,
		parameter	[0:0]	OPT_SKIDBUFFER = 0,
		parameter	[32:0]	P_SOF = 33'h1_7cb5_3737,
					P_EOF = 33'h1_7cb5_d5b5,
					P_HOLD= 33'h1_7caa_d5d5
		// }}}
	) (
		// {{{
		input	wire		i_clk, i_reset,
		//
		input	wire		s_valid,
		output	wire		s_ready,
		input	wire	[31:0]	s_data,
		input	wire		s_last,
		//
		output	wire		m_valid,
		input	wire		m_ready,
		output	wire		m_primitive,
		output	wire	[31:0]	m_data,
		output	wire		m_last
		// }}}
	);

	// Local definitions
	// {{{
	wire		skd_valid, skd_ready, skd_last;
	wire	[31:0]	skd_data;

	wire		crc_valid, crc_ready, crc_last;
	wire	[31:0]	crc_data;

	wire		sc_valid, sc_ready, sc_last;
	wire	[31:0]	sc_data;
	// }}}

	// Optional skidbuffer
	// {{{
	skidbuffer #(
		// {{{
		.OPT_PASSTHROUGH(!OPT_SKIDBUFFER),
		.DW(1+32)
		// }}}
	) skd (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset),
		.i_valid(s_valid), .o_ready(s_ready),
			.i_data({ s_last, s_data }),
		.o_valid(skd_valid), .i_ready(skd_ready),
			.o_data({ skd_last, skd_data })
		// }}}
	);
	// }}}

	// Step #1: Add a CRC
	// {{{
	satatx_crc
	tx_crc (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.S_AXIS_TVALID(skd_valid),
		.S_AXIS_TREADY(skd_ready),
		.S_AXIS_TDATA(SWAP_ENDIAN(skd_data)),
		.S_AXIS_TLAST(skd_last),
		//
		.M_AXIS_TVALID(crc_valid),
		.M_AXIS_TREADY(crc_ready),
		.M_AXIS_TDATA(crc_data),
		.M_AXIS_TLAST(crc_last)
		// }}}
	);
	// }}}

	// Step #2: Scramble the packet
	// {{{
	satatx_scrambler
	scrambler (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.S_AXIS_TVALID(crc_valid),
		.S_AXIS_TREADY(crc_ready),
		.S_AXIS_TDATA(crc_data),
		.S_AXIS_TLAST(crc_last),
		//
		.M_AXIS_TVALID(sc_valid),
		.M_AXIS_TREADY(sc_ready),
		.M_AXIS_TDATA(sc_data),
		.M_AXIS_TLAST(sc_last)
		// }}}
	);
	// }}}

	// Step #3: Add framing
	// {{{
	satatx_framer #(
		.P_SOF(P_SOF), .P_EOF(P_EOF), .P_HOLD(P_HOLD)
	) framer (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.S_AXIS_TVALID(sc_valid),
		.S_AXIS_TREADY(sc_ready),
		.S_AXIS_TDATA(SWAP_ENDIAN(sc_data)),
		.S_AXIS_TLAST(sc_last),
		//
		.M_AXIS_TVALID(m_valid),
		.M_AXIS_TREADY(m_ready),
		.M_AXIS_TDATA({ m_primitive, m_data }),
		.M_AXIS_TLAST(m_last)
		// }}}
	);
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

	// Keep Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0 };
	// Verilator lint_on  UNUSED
	// }}}
endmodule
