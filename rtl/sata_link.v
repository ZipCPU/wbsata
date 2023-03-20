////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	rtl/sata/sata_link.v
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
// Copyright (C) 2021-2023, Gisselquist Technology, LLC
// {{{
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
// }}}
// License:	GPL, v3, as defined and found on www.gnu.org,
// {{{
//		http://www.gnu.org/licenses/gpl.html
//
////////////////////////////////////////////////////////////////////////////////
//
`default_nettype none
// }}}
module	sata_link #(
		// {{{
		parameter	[0:0]	OPT_LITTLE_ENDIAN = 0
		// }}}
	) (
		// {{{
		input	wire		i_tx_clk,
		// Verilator lint_off	SYNCASYNCNET
		input	wire		i_reset,
		// Verilator lint_on	SYNCASYNCNET
		// Configuration controls
		// {{{
		input	wire		i_cfg_continue_en,
		input	wire		i_cfg_scrambler_en,
		input	wire		i_cfg_crc_en,
		// }}}
		// Transport interface: Two abortable AXI streams
		// {{{
		input	wire		s_valid,
		output	wire		s_ready,
		input	wire	[31:0]	s_data,
		input	wire		s_last,
		// input wire		s_abort,	// TX aborts
		output	wire		s_success,	// Pkt rcvd successfully
		output	wire		s_failed,	// Link failed to send
		//
		output	wire		m_valid,
		// input wire		m_ready,
		input	wire		m_full,	// Will take some time to act
		input	wire		m_empty,
		output	wire	[31:0]	m_data,
		output	wire		m_last,
		output	wire		m_abort,
		//
		output	wire		o_link_error,	// On an error condition
		output	wire		o_link_ready, // Err clrd, Syncd, & rdy to go
		// }}}
		// (PHY) RX interface
		// {{{
		input	wire		i_rx_clk,
		input	wire		i_rx_valid,
		// output wire		o_rx_ready,	// *MUST* be true
		input	wire	[32:0]	i_rx_data,
		// No *LAST* cause this is a pure data stream
		// }}}
		// PHY (TX) interface
		// {{{
		output	wire		o_phy_primitive,
		output	wire	[31:0]	o_phy_data,
		output	wire		o_phy_reset,
		input	wire		i_phy_ready
		// }}}
		// }}}
	);

	// Local declarations
	// {{{
`include "sata_primitives.vh"

	wire		rx_valid_rxck;
	wire	[32:0]	rx_data_rxck;

	wire		rx_valid;
	wire	[32:0]	rx_data;

	wire		ign_rxfifo_full, rd_fifo_empty;

	wire		tx_pktvalid, tx_pktready, tx_pktlast;
	wire	[32:0]	tx_pktdata;

	wire		pre_phy_valid, pre_phy_ready;
	wire	[32:0]	pre_phy_data;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// RX Pre-Handling
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	(* ASYNC_REG *)	reg		rx_reset_n;
	(* ASYNC_REG *)	reg	[1:0]	rx_reset_pipe;

	always @(posedge i_rx_clk or posedge i_reset)
	if (i_reset)
		{ rx_reset_n, rx_reset_pipe } <= 3'h0;
	else
		{ rx_reset_n, rx_reset_pipe } <= { rx_reset_pipe, 1'b1 };
	
	// 1. Remove any received continue and align primitives
	// {{{
	satalnk_rmcont #(
		.P_CONT(P_CONT), .P_ALIGN(P_ALIGN)
	) rm_align (
		.i_clk(i_rx_clk), .i_reset(!rx_reset_n),
		//
		.i_valid(i_rx_valid), .i_primitive(i_rx_data[32]),
		.i_data(i_rx_data[31:0]),
		//
		.o_valid(rx_valid_rxck), .o_primitive(rx_data_rxck[32]),
		.o_data(rx_data_rxck[31:0])
	);
	// }}}

	// 2. Cross clock domains
	// {{{
	afifo #(
		.LGFIFO(3), .WIDTH(33)
	) rx_afifo (
		.i_wclk(i_rx_clk), .i_wr_reset_n(rx_reset_n),
		//
		.i_wr(rx_valid_rxck), .i_wr_data(rx_data_rxck),
			.o_wr_full(ign_rxfifo_full),
		//
		//
		.i_rclk(i_tx_clk), .i_rd_reset_n(!i_reset),

		.i_rd(1'b1),
			.o_rd_data(rx_data), .o_rd_empty(rd_fifo_empty)
	);

	assign	rx_valid = !rd_fifo_empty;
	// }}}
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// TX Packet framing
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	satalnk_txpacket #(
		// {{{
		.P_SOF(P_SOF), .P_EOF(P_EOF), .P_HOLD(P_HOLD),
		.OPT_LITTLE_ENDIAN(OPT_LITTLE_ENDIAN)
		// }}}
	) tx_packet (
		// {{{
		.i_clk(i_tx_clk), .i_reset(i_reset),
		//
		.s_valid(s_valid),
		.s_ready(s_ready),
		.s_data(s_data),
		.s_last(s_last),
		//
		.m_valid(tx_pktvalid),
		.m_ready(tx_pktready),
		.m_primitive(tx_pktdata[32]),
		.m_data(tx_pktdata[31:0]),
		.m_last(tx_pktlast)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Link State Machine
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	satalnk_fsm #(
	) link_fsm (
		// {{{
		.i_clk(i_tx_clk), .i_reset(i_reset),
		//
		.s_valid(tx_pktvalid),
		.s_ready(tx_pktready),
		.s_data(tx_pktdata),
		.s_last(tx_pktlast),
		.s_abort(1'b0),
		//
		.s_success(s_success), .s_failed(s_failed),
		//
		// RX channel info
		// .m_valid, .m_ready
		.m_full(m_full), .m_empty(m_empty),
		.m_last(m_last), .m_abort(m_abort),
		//
		.o_error(o_link_error), .o_ready(o_link_ready),
		//
		.i_rx_valid(rx_valid), .i_rx_data(rx_data),
		//
		.m_phy_valid(pre_phy_valid), .m_phy_ready(pre_phy_ready),
		.m_phy_data(pre_phy_data),
		//
		.o_phy_reset(o_phy_reset), .i_phy_ready(i_phy_ready)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Continue primitive generation
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	satalnk_align #(
		.OPT_LITTLE_ENDIAN(OPT_LITTLE_ENDIAN)
	) insert_alignments (
		// {{{
		.i_clk(i_tx_clk), .i_reset(i_reset),
		//
		.i_cfg_continue_en(i_cfg_continue_en),
		//
		// .s_valid(pre_phy_valid),
		.s_ready(pre_phy_ready),
		.s_data(pre_phy_data),
		//
		.o_primitive(o_phy_primitive),
		.o_data(o_phy_data)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// RX Packet generation
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	satalnk_rxpacket #(
		.P_SOF(P_SOF), .P_EOF(P_EOF), .P_WTRM(P_WTRM), .P_SYNC(P_SYNC),
		.OPT_LITTLE_ENDIAN(OPT_LITTLE_ENDIAN)
	) rx_packet (
		.i_clk(i_tx_clk), .i_reset(i_reset),
		//
		.i_cfg_scrambler_en(i_cfg_scrambler_en),
		.i_cfg_crc_en(i_cfg_crc_en),
		//
		.i_valid(rx_valid), .i_data(rx_data),
		.i_phy_ready(i_phy_ready),
		//
		.m_valid(m_valid),
		.m_data(m_data),
		.m_last(m_last),
		.m_abort(m_abort)
	);
	// }}}

	// Keep Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, ign_rxfifo_full, pre_phy_valid };
	// Verilator lint_on  UNUSED
	// }}}
endmodule
