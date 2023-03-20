////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	sata/sata_controller.v
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
module	sata_controller #(
		// {{{
		// Verilator lint_off UNUSED
		parameter [0:0]	OPT_LOWPOWER = 1'b0,
				OPT_LITTLE_ENDIAN = 1'b0,
		// Verilator lint_on  UNUSED
		parameter	LGFIFO = 12
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
		output	reg		o_wb_ack,
		output	reg	[31:0]	o_wb_data,
		// }}}
		// Link <-> PHY interface
		// {{{
		input	wire		i_rxphy_clk,
		input	wire		i_txphy_clk,
		//
		input	wire		i_rxphy_valid,
		input	wire	[32:0]	i_rxphy_data,
		//
		output	wire		o_txphy_primitive,
		output	wire	[31:0]	o_txphy_data,
		output	wire		o_phy_reset,
		input	wire		i_phy_ready
		// }}}
		// }}}
	);

	// Local declarations
	// {{{
	wire	link_error, link_ready;

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
	// }}}

	assign	cfg_continue_en  = 1'b1;
	assign	cfg_scrambler_en = 1'b1;
	assign	cfg_crc_en       = 1'b1;
	////////////////////////////////////////////////////////////////////////
	//
	// Transport layer
	// {{{
	sata_transport #(
		.LGFIFO(LGFIFO)
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
		// Link layer interface
		// {{{
		.o_tran_valid(h2d_tran_valid),
		.i_tran_ready(h2d_tran_ready),
		.o_tran_data(h2d_tran_data),
		.o_tran_last(h2d_tran_last),
		.i_tran_success(h2d_tran_success),
		.i_tran_failed(h2d_tran_failed),
		//
		.i_tran_valid(d2h_tran_valid),
		.o_tran_full(d2h_tran_full),
		.o_tran_empty(d2h_tran_empty),
		.i_tran_data(d2h_tran_data),
		.i_tran_last(d2h_tran_last),
		.i_tran_abort(d2h_tran_abort),
		//
		.i_link_err(link_error),
		.i_link_ready(link_ready)
		// }}}
		// }}}
	);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Link layer
	// {{{
	reg		tx_link_reset;
	reg	[1:0]	tx_reset_pipe;

	initial	{ tx_link_reset, tx_reset_pipe } = -1;
	always @(posedge i_txphy_clk or posedge i_reset)
	if (i_reset)
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
		.i_rx_valid(i_rxphy_valid),
		.i_rx_data(i_rxphy_data),
		//
		.o_phy_primitive(o_txphy_primitive),
		.o_phy_data(o_txphy_data),
		.o_phy_reset(o_phy_reset),
		.i_phy_ready(i_phy_ready)
		// }}}
		// }}}
	);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// PHY layer
	// {{{
	//
	// The PHY layer is maintained elsewhere, so it can be included from
	// the top level.  (Main and below are simulable with Verilator, other
	// top level components are not.)
	// }}}
endmodule
