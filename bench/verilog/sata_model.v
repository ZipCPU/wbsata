////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/sata_model.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	This is the top level of our Verilog SATA model.  It's designed
//		to act *like* a SATA device enough that we can simulate through
//	(and understand) the GTX transceivers used within the SATA PHY.
//
// State machine:
//	COMRESET: Fig 183, p313
//		Host issues COMRESET
//		  6. data bursts, including inter-burst spacing
//		  Sustained as long as reset is asserted
//		  Started during hardware reset, ened following
//		  Each burst is 160 Gen1 UI's long (106.7ns)
//		  Each interburst idle shall be 480 GEN1 UI's long (320ns)
//		COMRESET detector looks for four consecutive bursts with 320ns
//		  spacing (nominal)
//		Spacing of less than 175ns or greater than 525ns shall
//		  invalidate COMRESET
//		COMRESET is negated by 525ns (or more) silence on the channel
//	COMINIT: Device replies with COMINIT after detecting the release of
//		COMRESET
//	COMWAKE: Host replies with COMWAKE
//		COMWAKE = six bursts of data separated by a bus idle condition
//		Each burst is 160 Gen1 UI long, each interburst idle shall be
//		  160 GEN1 UI's long (106.7ns).  The detector looks for four
//		  consecutive bursts with 106.7ns spacing (nominal)
//		Spacing less than 35ns or greater than 172ns shall invalidate
//		  COMWAKE detector
//	Device sends COMWAKE
//	- Device sends continuous stream of ALIGN at highest supported spead
//		After 54.6us, w/o response, it moves down to the next supported
//		speed
//	- Host responds to device COMWAKE with ...
//		- D10.2 characters at the lowest supported speed.
//		- When it detects ALIGN, it replies with ALIGN at the same speed
//		  Must be able to acquire lock w/in 54.6us (2048 Gen1 DWORD tim)
//		- Host waits for at least 873.8 us (32768 Gen1 DWORD times)
//		  after detecting COMWAKE to receive first ALIGN.  If no ALIGN
//		  is received, the host restarts the power-on sequence
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2023-2026, Gisselquist Technology, LLC
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
`timescale 1ns/1ps
// }}}
module	sata_model (
		// {{{
		// input	wire		i_phy_ready,
		// input	wire		i_comfinish,
		// input	wire		i_cominit_det, i_comwake_det,
		input	wire		i_rx_p, i_rx_n,
		output	wire		o_tx_p, o_tx_n
		// }}}
	);

	// Local parameters
	// {{{
	// 1500Mb/s -- could also be 3000Mb/s or 6000Mb/s
	localparam	realtime	TXCLK_PERIOD	= 1.0/1.5;	// ns
	localparam	realtime	RXCLK_PERIOD	= 1.0/1.5;
	localparam	realtime	SYSCLK_PERIOD	= 16.667;
	localparam	realtime	DCLK_PERIOD	= 16.667;

	// OOB timings (check page 209-210 in SATA doc.)
	localparam	realtime	T_COMRESET_BURST = 107;	// 106.7 ns (Nominal)
	localparam	realtime	T_COMRESET_GAP   = 320;	// 320.0 ns (Nominal)
	localparam 	realtime	T_COMCALIBRATE 	 = 150;
	localparam	realtime	T_COMWAKE_BURST  = 107;	// 106.7 ns (Nominal)
	localparam	realtime	T_COMWAKE_GAP    = 107;	// 106.7 ns (Nominal)
	localparam 	realtime	T_COMINIT_MIN	 = 100;	// COMINIT için minimum yüksek süre
	localparam 	realtime	T_COMINIT_MAX	 = 110;	// COMINIT için maksimum yüksek süre
	localparam 	realtime	T_COMWAKE_MIN	 = 100;	// COMWAKE için minimum yüksek süre
	localparam 	realtime	T_COMWAKE_MAX	 = 110;	// COMWAKE için maksimum yüksek süre

	reg [31:0]  counter;
	wire     rx_p, rx_n;

	reg		mdl_reset, txclk;
	wire		mdl_reset_request, mdl_phy_down;
	wire		rxclk;
	wire	[39:0]	tx_word;
	wire		rx_valid, rx_ctrl;
	wire	[31:0]	rx_data;

	wire		txwclk;
	reg	[5:0]	tx_word_count;

	wire	mdl_link_ready, mdl_link_err;

	wire	linktx_valid, linktx_ready, linktx_ctrl;
	wire	[31:0]	linktx_data;

	wire		rxaxin_valid, rxaxin_full, rxaxin_empty,
			rxaxin_last, rxaxin_abort;
	wire	[31:0]	rxaxin_data;

	wire		txaxin_valid, txaxin_ready, txaxin_last,
			txaxin_success, txaxin_failed;
	wire	[31:0]	txaxin_data;

	reg		clk_sync;
	reg		[8:0] idle_cnt;

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Reset, tx clock, and setup
	// {{{
	initial txclk = 1'b0;
	always
		// Verilator lint_off BLKSEQ
		#(TXCLK_PERIOD/2) txclk = !txclk;
		// Verilator lint_on  BLKSEQ

	initial begin
		mdl_reset <= 1'b1;
		#15;
		@(posedge txclk)
			mdl_reset <= 1'b0;
	end

	initial tx_word_count = 0;
	always @(posedge txclk)
	if (tx_word_count >= 39)
		tx_word_count <= 0;
	else
		tx_word_count <= tx_word_count + 1;

	assign	txwclk = (tx_word_count > 19);

	// COMWAKE, COMRESET, COMINIT, etc.
	mdl_scomfsm
		// Uses: mdl_srxcomsigs
	u_comfsm (
		// {{{
		.i_txclk(txclk),
		.i_reset(mdl_reset),
		.o_reset(mdl_phy_down),
		.i_rx_p(i_rx_p), .i_rx_n(i_rx_n),
		.i_tx_word(tx_word),
		.o_tx_p(o_tx_p), .o_tx_n(o_tx_n)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// RX Chain
	// {{{

	// Recover the RX Clock from the bit stream
	mdl_sbitsync
	u_bitsync (
		.i_reset(mdl_reset),
		.i_rx_data((i_rx_p === 1'b1) && (i_rx_n === 1'b0)),
		.o_rxclk(rxclk)
	);

	mdl_salign
		// Uses:
		// mdl_s10b8bw which uses mdl_s10b8b
	u_rxalign (
		// {{{
		.i_clk(rxclk),
		.i_reset(mdl_reset),
		.i_rx_p((i_rx_p === 1'b1) && (i_rx_n === 1'b0)),
		.o_valid(rx_valid),
		.o_keyword(rx_ctrl),
		.o_data(rx_data)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// TX Chain
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	mdl_txword
	u_txword (
		// {{{
		.i_clk(txwclk),
		.i_reset(mdl_reset || mdl_phy_down),
		.S_VALID(linktx_valid),
		.S_READY(linktx_ready),
		.S_CTRL( linktx_ctrl),
		.S_DATA( linktx_data),
		//
		.o_tx_word(tx_word)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Link Layer
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	sata_link
	u_mdllink (
		.i_tx_clk(txwclk),
		.i_reset(mdl_reset || mdl_phy_down),
		.i_cfg_continue_en(1'b1),
		.i_cfg_scrambler_en(1'b1),
		.i_cfg_crc_en(1'b1),
		//
		.s_valid(  txaxin_valid),
		.s_ready(  txaxin_ready),
		.s_data(   txaxin_data),
		.s_last(   txaxin_last),
		.s_success(txaxin_success),
		.s_failed( txaxin_failed),
		//
		.m_valid(rxaxin_valid),
		// .m_ready(  rxaxin_ready),
		.m_full( rxaxin_full),
		.m_empty(rxaxin_empty),
		.m_data( rxaxin_data),
		.m_last( rxaxin_last),
		.m_abort(rxaxin_abort),
		//
		.o_link_error(mdl_link_err),
		.o_link_ready(mdl_link_ready),
		//
		.i_rx_clk(rxclk),
		.i_rx_valid(rx_valid),
		.i_rx_data({ rx_ctrl, rx_data }),
		//
		.o_phy_primitive(linktx_ctrl),
		.o_phy_data(linktx_data),
		.o_phy_reset(mdl_reset_request),
		.i_phy_ready(!mdl_phy_down)
	);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// SATA Command processor
	// {{{

	mdl_satacmd 
	u_mdl_satacmd (
		// {{{
		.i_tx_clk(txwclk), .i_phy_clk(rxclk),
		.i_reset(mdl_reset || mdl_phy_down), .i_phy_reset(mdl_reset_request),
		.s_valid(rxaxin_valid),
		// .s_ready,
		.s_full(rxaxin_full),
		.s_empty(rxaxin_empty),
		.s_data(rxaxin_data),
		.s_last(rxaxin_last),
		.s_abort(rxaxin_abort),
		//
		.m_valid(txaxin_valid),
		.m_ready(txaxin_ready),
		.m_data(txaxin_data),
		.m_last(txaxin_last)
		// .m_abort	// TX aborts
		// }}}
	);
	// }}}

	// initial begin
	// 	$dumpfile("waveform.vcd");
	// 	$dumpvars(0, sata_model);
	// end

	assign	linktx_valid = 1'b1;

	// Keep Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, mdl_link_ready, mdl_link_err, linktx_ready,
				txaxin_success, txaxin_failed };
	// Verilator lint_on  UNUSED
	// }}}
endmodule
