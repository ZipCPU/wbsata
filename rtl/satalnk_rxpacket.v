////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	rtl/sata/satalnk_rxpacket.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Converts received primitives and data into a (near) AXI Stream.
//		It's only a (near) AXI Stream because we there is _NO_
//	backpressure support.
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
module	satalnk_rxpacket #(
		// {{{
		parameter	[0:0]	OPT_LITTLE_ENDIAN = 0,
		parameter       [32:0]  P_SOF = 33'h1_7cb5_3737,
					P_EOF = 33'h1_7cb5_d5d5,
					P_WTRM= 33'h1_7cb5_5858,
					P_SYNC= 33'h1_7c95_b5b5,
		parameter	[0:0]	OPT_LOWPOWER = 1'b0
		// }}}
	) (
		// {{{
		input	wire		i_clk, i_reset,
		// Configuration
		// {{{
		input	wire		i_cfg_scrambler_en,
		input	wire		i_cfg_crc_en,
		// }}}
		// Incoming (PHY) RX interface
		// {{{
		// Comes directly from an Async FIFO
		input	wire		i_valid,
		input	wire	[32:0]	i_data,
		// No *LAST* cause this is a pure data stream
		input	wire		i_phy_ready,
		// }}}
		// (Internal) Transport interface outgoing stream
		// {{{
		output	wire		m_valid,
		output	wire	[31:0]	m_data,
		output	wire		m_last,
		output	wire		m_abort
		// }}}
		// }}}
	);

	// Local declarations
	// {{{
	wire		df_valid, df_last, df_ready, df_abort;
	wire	[31:0]	df_data;

	wire		ds_valid, ds_last;
	wire	[31:0]	ds_data;
	
	wire	[31:0]	crc_data;
	wire		crc_abort;
	// }}}

	// #1. Pre-RX state machine -- removes framing
	// {{{
	satarx_framer #(
		// {{{
		.P_SOF(P_SOF), .P_EOF(P_EOF), .P_WTRM(P_WTRM), .P_SYNC(P_SYNC),
		.OPT_LOWPOWER(OPT_LOWPOWER)
		// }}}
	) deframer (
		// {{{
		.S_AXI_ACLK(i_clk),
		.S_AXI_ARESETN(!i_reset),
		//
		.S_AXIS_TVALID(i_valid),
		.S_AXIS_TDATA(i_data),
		.S_AXIS_TABORT(!i_phy_ready),
		//
		.M_AXIS_TVALID(df_valid),
		// M_AXIS_TREADY -- unused
		.M_AXIS_TDATA(df_data),
		.M_AXIS_TLAST(df_last),
		.M_AXIS_TABORT(df_abort)
		// }}}
	);
	// }}}

	// #2. Descrambler
	// {{{
	satarx_scrambler #(
		.OPT_LOWPOWER(OPT_LOWPOWER)
	) descrambler (
		// {{{
		.S_AXI_ACLK(i_clk),
		.S_AXI_ARESETN(!i_reset && !df_abort),
		//
		.i_cfg_scrambler_en(i_cfg_scrambler_en),
		//
		.S_AXIS_TVALID(df_valid),
		.S_AXIS_TREADY(df_ready),
		.S_AXIS_TDATA(SWAP_ENDIAN(df_data)),
		.S_AXIS_TLAST(df_last),
		//
		.M_AXIS_TVALID(ds_valid),
		.M_AXIS_TREADY(1'b1),
		.M_AXIS_TDATA(ds_data),
		.M_AXIS_TLAST(ds_last)
		// }}}
	);
	// }}}

	// #3. CRC Check
	// {{{
	satarx_crc #(
		.OPT_LOWPOWER(OPT_LOWPOWER)
	) rx_crc (
		// {{{
		.S_AXI_ACLK(i_clk),
		.S_AXI_ARESETN(!i_reset && !df_abort),
		//
		.i_cfg_crc_en(i_cfg_crc_en),
		//
		.S_AXIS_TVALID(ds_valid),
		// .S_AXIS_TREADY(ds_ready),
		.S_AXIS_TDATA(ds_data),
		.S_AXIS_TLAST(ds_last),
		//
		.M_AXIS_TVALID(m_valid),
		// .M_AXIS_TREADY(m_ready),
		.M_AXIS_TDATA(crc_data),
		.M_AXIS_TLAST(m_last),
		.M_AXIS_TABORT(crc_abort)
		// }}}
	);
	// }}}

	assign	m_data  = SWAP_ENDIAN(crc_data);
	assign	m_abort = crc_abort || df_abort;

	function [31:0] SWAP_ENDIAN(input [31:0] swap_data);
		// {{{
	begin
		if (!OPT_LITTLE_ENDIAN)
			SWAP_ENDIAN = { swap_data[7:0], swap_data[15:8],
					swap_data[23:16], swap_data[31:24] };
		else
			SWAP_ENDIAN = swap_data;
	end endfunction
	// }}}

	// Keep Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, df_ready };
	// Verilator lint_on  UNUSED
	// }}}
endmodule
