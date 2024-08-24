////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/sata_controller.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	This is the "top level" host SATA controller.  All other parts
//		and pieces fall in line below here--save for the PHY.  The PHY
//	is saved for a top-level component.
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
`default_nettype none
`timescale	1ns/1ps
// }}}
module	sata_controller #(
		// {{{
		// Verilator lint_off UNUSED
		parameter [0:0]	OPT_LOWPOWER = 1'b0,
				OPT_LITTLE_ENDIAN = 1'b0,
		// Verilator lint_on  UNUSED
		parameter	LGFIFO = 12,
		parameter	DW = 32,	// Wishbone width
				AW = 30		// Wishbone address width
		// }}}
	) (
		// {{{
		input	wire		i_clk, i_reset,
		// Wishbone SOC interface
		// {{{
		input	wire		i_wb_cyc, i_wb_stb, i_wb_we,
		input	wire	[2:0]	i_wb_addr,
		input	wire	[31:0]	i_wb_data,
		input	wire	[3:0]	i_wb_sel,
		//
		output	wire		o_wb_stall,
		output	wire		o_wb_ack,
		output	wire	[31:0]	o_wb_data,
		// }}}
		// Wishbone DMA <-> memory interface
		// {{{
		output	wire		o_dma_cyc, o_dma_stb, o_dma_we,
		output	wire [AW-1:0]	o_dma_addr,
		output	wire [DW-1:0]	o_dma_data,
		output	wire [DW/8-1:0]	o_dma_sel,
		//
		input	wire		i_dma_stall,
		input	wire		i_dma_ack,
		input	wire [DW-1:0]	i_dma_data,
		input	wire		i_dma_err,
		// }}}
		output	wire		o_int,		// Interrupt
		// Link <-> PHY interface
		// {{{
		input	wire		i_rxphy_clk,
		input	wire		i_txphy_clk,
		//
		input	wire		i_rxphy_valid,
		input	wire	[32:0]	i_rxphy_data,
		//
		input	wire		i_txphy_ready,
		output	wire		o_txphy_primitive,
		output	wire	[31:0]	o_txphy_data,
		//
		output	wire		o_txphy_elecidle,
		output	wire		o_txphy_cominit,
		output	wire		o_txphy_comwake,
		input	wire		i_txphy_comfinish,
		//
		input	wire		i_rxphy_elecidle,
		input	wire		i_rxphy_cominit,
		input	wire		i_rxphy_comwake,
		output	wire		o_rxphy_cdrhold,
		input	wire		i_rxphy_cdrlock,
		//
		output	wire		o_phy_reset,
		input	wire		i_phy_ready
		// }}}
		// }}}
	);

	// Local declarations
	// {{{
	wire	link_error, link_ready, comlink_up, tx_link_ready;
	wire	cfg_continue_en, cfg_scrambler_en, cfg_crc_en;

	// h2d, d2h
	// {{{
	wire		h2d_tran_valid, h2d_tran_ready, h2d_tran_last,
			h2d_tran_success, h2d_tran_failed;
	wire	[31:0]	h2d_tran_data;
	wire		d2h_tran_valid, d2h_tran_full, d2h_tran_empty,
			d2h_tran_last, d2h_tran_abort;
	wire	[31:0]	d2h_tran_data;
	// }}}

	reg		tx_link_reset;
	reg	[1:0]	tx_reset_pipe;

	wire		tx_link_primitive;
	wire	[31:0]	tx_link_data;
	wire		link_reset_request;
	// }}}

	assign	cfg_continue_en  = 1'b1;
	assign	cfg_scrambler_en = 1'b1;
	assign	cfg_crc_en       = 1'b1;
	assign	o_phy_reset	= i_reset;
	////////////////////////////////////////////////////////////////////////
	//
	// Transport layer
	// {{{
	sata_transport #(
		.LGFIFO(LGFIFO), .AW(AW), .DW(DW)
	) u_transport (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset),
		.i_phy_clk(i_txphy_clk),
		// Wishbone SOC interface
		// {{{
		.i_wb_cyc(i_wb_cyc), .i_wb_stb(i_wb_stb), .i_wb_we(i_wb_we),
		.i_wb_addr(i_wb_addr),
		.i_wb_data(i_wb_data), .i_wb_sel(i_wb_sel),
		//
		.o_wb_stall(o_wb_stall),
		.o_wb_ack(o_wb_ack), .o_wb_data(o_wb_data),
		// }}}
		// Wishbone DMA interface
		// {{{
		.o_dma_cyc(o_dma_cyc), .o_dma_stb(o_dma_stb),
			.o_dma_we(o_dma_we),
		.o_dma_addr(o_dma_addr),
		.o_dma_data(o_dma_data), .o_dma_sel(o_dma_sel),
		//
		.i_dma_stall(i_dma_stall),
		.i_dma_ack(i_dma_ack), .i_dma_data(i_dma_data),
		.i_dma_err(i_dma_err),
		// }}}
		.o_int(o_int),	// Interrupt
		// Link layer interface
		// {{{
		// h2d == host (fpga)   to device (disk)
		.o_tran_valid(h2d_tran_valid),
		.i_tran_ready(h2d_tran_ready),
		.o_tran_data(h2d_tran_data),
		.o_tran_last(h2d_tran_last),
		.i_tran_success(h2d_tran_success),
		.i_tran_failed(h2d_tran_failed),
		//
		// d2h == device (disk) to host (fpga)
		.i_tran_valid(d2h_tran_valid),
		.o_tran_full(d2h_tran_full),
		.o_tran_empty(d2h_tran_empty),
		.i_tran_data(d2h_tran_data),
		.i_tran_last(d2h_tran_last),
		.i_tran_abort(d2h_tran_abort),
		//
		.i_link_err(link_error),
		.i_link_ready(link_ready && comlink_up)
		// }}}
		// }}}
	);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Link layer
	// {{{
	initial	{ tx_link_reset, tx_reset_pipe } = -1;
	always @(posedge i_txphy_clk or negedge i_phy_ready)
	if (!i_phy_ready)
		{ tx_link_reset, tx_reset_pipe } <= -1;
	else
		{ tx_link_reset, tx_reset_pipe } <= { tx_reset_pipe, 1'b0 };

	sata_link
	u_link (
		// {{{
		.i_tx_clk(i_txphy_clk), .i_reset(tx_link_reset),
		//
		.i_cfg_continue_en(cfg_continue_en),
		.i_cfg_scrambler_en(cfg_scrambler_en),
		.i_cfg_crc_en(cfg_crc_en),
		// Transport interface
		// {{{
		.s_valid(  h2d_tran_valid),
		.s_ready(  h2d_tran_ready),
		.s_data(   h2d_tran_data),
		.s_last(   h2d_tran_last),
		.s_success(h2d_tran_success),
		.s_failed( h2d_tran_failed),
		//
		.m_valid(d2h_tran_valid),
		.m_full( d2h_tran_full),
		.m_empty(d2h_tran_empty),
		.m_data( d2h_tran_data),
		.m_last( d2h_tran_last),
		.m_abort(d2h_tran_abort),
		//
		.o_link_error(link_error),
		.o_link_ready(link_ready),
		// }}}
		// PHY interface
		// {{{
		.i_rx_clk(i_rxphy_clk),
		.i_rx_valid(i_rxphy_valid && comlink_up),
		.i_rx_data(i_rxphy_data),
		//
		.o_phy_primitive(tx_link_primitive),
		.o_phy_data(tx_link_data),
		.o_phy_reset(link_reset_request),
		.i_phy_ready(tx_link_ready)
		// }}}
		// }}}
	);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Reset (COMRESET, COMWAKE, etc.) controller
	// {{{
	//

	sata_reset
	u_reset (
		.i_tx_clk(i_txphy_clk),
		.i_rx_clk(i_rxphy_clk),
		.i_reset_n(!tx_link_reset),	// TX clock domain
		//
		.i_reset_request(link_reset_request),
		//
		// .i_link_err(link_err),
		// OOB signaling
		// {{{
		// TX clock signals
		.o_tx_elecidle(o_txphy_elecidle),
		.o_tx_cominit(o_txphy_cominit),
		.o_tx_comwake(o_txphy_comwake),
		.i_tx_comfinish(i_txphy_comfinish),
		.o_rx_cdrhold(o_rxphy_cdrhold),			// Async
		//
		// RX clock domain
		.i_rx_elecidle(i_rxphy_elecidle),
		.i_rx_cominit(i_rxphy_cominit),
		.i_rx_comwake(i_rxphy_comwake),
		.i_rx_cdrlock(i_rxphy_cdrlock),
		// }}}
		// Data
		// {{{
		// Need to look for RX align primitives
		.i_rx_valid(i_rxphy_valid),		// Look for align
		.i_rx_data(i_rxphy_data),
		//
		// TX path, goes through RESET primitive
		.o_tx_ready(tx_link_ready),
		.i_tx_primitive(tx_link_primitive),
		.i_tx_data(tx_link_data),
		//
		.o_phy_primitive(o_txphy_primitive),
		.o_phy_data(o_txphy_data),
		.i_phy_ready(i_txphy_ready),
		// }}}
		//
		.o_link_up(comlink_up)		// TX clock domain
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// PHY layer
	// {{{
	//
	// The PHY layer is maintained elsewhere, so it can be included from
	// the top level.  (Main and below are intended to be hardware
	// indeepndent and simulable with Verilator, other top level components
	// are not designed with this intention.)
	// }}}
endmodule
