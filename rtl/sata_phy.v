////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/sata_phy.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	This is intended to be the "top-level" of the PHY component.
//		It is designed for a Xilinx board with GTX transceivers.
//
//	This component will not be simulated using Verilator.  If/when
//	simulated, it must be simulated under Xilinx Vivado (or other
//	equivalent capability, capable of simulating a GTX transciever ...).
//
// PHY *must* be for both TX and RX, since the same GTXE2_CHANNEL controls
// both
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
module	sata_phy #(
		// {{{
		parameter [0:0]	OPT_LITTLE_ENDIAN = 1'b0,
		parameter [0:0]	OPT_RXBUFFER = 1'b1,
		parameter [0:0]	OPT_TXBUFFER = 1'b1,
		parameter [0:0]	OPT_AUTO_ALIGN = 1'b1,	// Detect & ALIGN_p
		parameter [1:0]	SATA_GEN = 1
		// }}}
	) (
		// {{{
		input	wire		i_wb_clk, i_reset, i_ref_clk200,
		//
		// input	wire		i_sata_ref_p, i_sata_ref_n,
		//
		output	wire		o_ready, o_init_err,
		// Wishbone DRP Control
		// {{{
		input	wire		i_wb_cyc, i_wb_stb, i_wb_we,
		input	wire	[8:0]	i_wb_addr,
		input	wire	[31:0]	i_wb_data,
		input	wire	[3:0]	i_wb_sel,
		output	wire		o_wb_stall,
		output	reg		o_wb_ack,
		output	reg	[31:0]	o_wb_data,
		// }}}
		// Transmitter control
		// {{{
		output	wire		o_tx_clk,
		output	wire		o_tx_ready,
		// Start with OOB and power up requirements
		input	wire		i_tx_elecidle,
		input	wire		i_tx_cominit,
		input	wire		i_tx_comwake,
		output	wire		o_tx_comfinish,
		// Then move on to the actual data
		input	wire		i_tx_primitive,
		input	wire	[31:0]	i_tx_data,
		// }}}
		// Receiver control
		// {{{
		output	wire		o_rx_clk,
		output	wire		o_rx_primitive,
		output	wire	[31:0]	o_rx_data,
		output	wire		o_rx_error, o_syncd,

		output	wire		o_rx_elecidle,
		output	wire		o_rx_cominit_detect,
		output	wire		o_rx_comwake_detect,
		input	wire		i_rx_cdrhold,
		output	wire		o_rx_cdrlock,
		// }}}
		//
		// COMFINISH
		// COMSAS
		// TXDELECIDLEMODE
		// Connections to external pads
		// {{{
		output	wire		o_tx_p, o_tx_n,
		input	wire		i_rx_p, i_rx_n
		// }}}
		// }}}
	);

	// Declarations
	// {{{
	wire	i_realign, syncd, resyncd, rx_polarity, tx_polarity,
		rx_cdr_hold, raw_tx_clk, gtx_refck;
	wire	power_down, qpll_lock, tx_pll_lock;
	wire	ign_cpll_locked, ign_rx_comma;
	reg	pll_reset, gtx_reset;
	wire	[63:0]	raw_rx_data;
	wire	[7:0]	rx_char_is_k, rx_invalid_code, rx_disparity_err;
	reg		qpll_reset;
	reg	[4:0]	qpll_reset_count;

	assign	rx_polarity = 1'b0;
	assign	tx_polarity = 1'b0;	// Normal polarity
	assign	i_realign = 1'b1;	// Always re-align
	assign	power_down = qpll_reset;
	assign	rx_cdr_hold = 1'b0;

	assign	o_syncd = syncd && !resyncd;
	assign	o_rx_error = (|rx_disparity_err[7:0])
			|| (|rx_invalid_code[7:0]) || (|rx_char_is_k[7:1]);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Reset sequence
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// Step 1. Power everything down when told, or until reference clock
	//	edges are detectd
	// Step 2. Assert the CPLLRESET
	// Step 3. Finish the CPLL Reset
	// Step 4. Wait for the CPLL reset to be complete
	// Step 5. Wait 500ns
	// Step 6. Wait 1024 clocks for the clock recovery lock (CDRLOCK)
	// Step 7. On OPT_RXBUFFER && RX, wait on ALIGN via rx_comma
	// Step 8. Wait for a second ALIGN via rx_comma
	// Step 9. Now ready for data

	wire	rx_clk_unbuffered, qpll_clk, qpll_refck;
	wire	rx_pll_reset, rx_gtx_reset, rx_reset_done,
		rx_cdr_lock, rx_aligned, rx_user_ready, rx_watchdog_err,
		rx_ready, rx_align_done;
	reg	last_rx_align_done, rx_align_done_ck, rx_align_done_pipe;
	reg	[1:0]	rx_align_count, rx_align_edges;

	wire	tx_pll_reset, tx_gtx_reset, tx_reset_done,
		tx_user_ready, tx_watchdog_err;

	// First, reset the QPLL
	// {{{
	initial	qpll_reset = 1'b1;
	initial	qpll_reset_count = -1;
	always @(posedge i_wb_clk)
	if (i_reset)
	begin
		qpll_reset <= 1'b1;
		qpll_reset_count <= -1;
	end else begin
		qpll_reset <= (qpll_reset_count > 1);
		if (qpll_reset > 0)
			qpll_reset <= qpll_reset - 1;
	end
	// }}}

	sata_phyinit #(
		.OPT_WAIT_ON_ALIGN(1'b1)
	) rx_init (
		// {{{
		.i_clk(i_wb_clk),
		.i_reset(i_reset || qpll_reset || !qpll_lock),
		.i_power_down(1'b0), // power_down),
		.o_pll_reset(rx_pll_reset),
		.i_pll_locked(qpll_lock),
		.o_gtx_reset(rx_gtx_reset),
		.i_gtx_reset_done(rx_reset_done),
		.i_aligned(rx_aligned),
		.o_err(rx_watchdog_err),
		.o_user_ready(rx_user_ready),
		.o_complete(rx_ready)
		// }}}
	);

	// Generate rx_aligned signal
	// {{{
	always @(posedge i_wb_clk)
	if (rx_gtx_reset)
	begin
		{ last_rx_align_done, rx_align_done_ck,
						rx_align_done_pipe } <= 0;
	end else begin
		{ last_rx_align_done,
		  rx_align_done_ck,
		  rx_align_done_pipe } <= { rx_align_done_ck,
						rx_align_done_pipe,
						rx_align_done };
	end

	always @(posedge i_wb_clk)
	if (rx_gtx_reset)
		rx_align_edges <= 0;
	else if (!rx_align_edges[1] && !last_rx_align_done && rx_align_done_ck)
		rx_align_edges <= rx_align_edges + 1;

	always @(posedge o_rx_clk or posedge rx_gtx_reset)
	if (rx_gtx_reset)
		rx_align_count <= 0;
	else if (o_rx_error)
		rx_align_count <= 0;
	else if (rx_char_is_k[0] && !rx_aligned)
		rx_align_count <= rx_align_count + 1;

	assign	rx_aligned = rx_align_count[1] && rx_align_edges[1];
	// }}}

	sata_phyinit #(
		.OPT_WAIT_ON_ALIGN(1'b0)
	) tx_init (
		// {{{
		.i_clk(i_wb_clk), .i_reset(i_reset || !qpll_lock),
		.i_power_down(1'b0), // power_down),
		.o_pll_reset(tx_pll_reset),
		.i_pll_locked(qpll_lock),
		.o_gtx_reset(tx_gtx_reset),
		.i_gtx_reset_done(tx_reset_done && tx_pll_lock),
		.i_aligned(1'b1),	// We don't wait for TX alignment
		.o_err(tx_watchdog_err),
		.o_user_ready(tx_user_ready),
		.o_complete(o_tx_ready)
		// }}}
	);

	assign	o_init_err = rx_watchdog_err || tx_watchdog_err;
	assign	o_ready = o_tx_ready; // rx_ready && o_tx_ready;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Wishbone to DRP mapping
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//
	wire		i_drp_clk;
	wire		i_drp_enable, i_drp_we;
	wire	[8:0]	i_drp_addr;
	wire	[15:0]	i_drp_data, o_drp_data;
	wire		o_drp_ready;
	reg		pending_wb_ack;

	assign	i_drp_clk    = i_wb_clk;
	assign	i_drp_data   = i_wb_data[15:0];
	assign	i_drp_enable = pending_wb_ack;
	assign	i_drp_we     = i_drp_enable && i_wb_we;
	assign	o_wb_stall   = !pending_wb_ack;
	assign	i_drp_addr   = i_wb_addr[8:0];
	// assign	o_wb_data    = { 16'h0, o_drp_data };
	// assign	o_wb_ack     = o_drp_ready;

	initial	pending_wb_ack = 1'b0;
	always @(posedge i_drp_clk)
	if (i_reset || !i_wb_cyc)
		pending_wb_ack <= 1'b0;
	else if (pending_wb_ack)
		pending_wb_ack <= !o_drp_ready;
	else if (i_wb_stb && !o_wb_stall)
		pending_wb_ack <= (&i_wb_sel[1:0]);

	initial	o_wb_ack = 1'b0;
	always @(posedge i_drp_clk)
	if (i_reset || !i_wb_cyc)
		o_wb_ack <= 1'b0;
	else if (pending_wb_ack)
		o_wb_ack <= o_drp_ready;
	else
		o_wb_ack <= i_wb_stb && (i_wb_sel[1:0] != 2'b11);

	always @(posedge i_drp_clk)
		o_wb_data <= { 16'h0, o_drp_data };
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Instantiate the GTX Channel
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

`ifdef	IVERILOG
	reg	[15:0]	drp_mem	[0:511];

	always @(posedge i_drp_clk)
	if (i_drp_we && o_drp_ready)
		drp_mem[i_drp_addr] <= i_drp_data;

	always @(*)
	begin
		o_drp_data <= 16'h0;
		if (i_drp_enable && o_drp_ready && !i_drp_we)
			o_drp_data <= drp_mem[i_drp_addr];
	end

`else
	reg	sata_ref_ck;
	wire	i_sata_ref_p, i_sata_ref_n;
	localparam realtime	CK_HALFPERIOD_NS = 1000.0 / 150.0 / 2.0;

	initial begin
		forever
			#CK_HALFPERIOD_NS sata_ref_ck = (sata_ref_ck === 1'b0);
	end

	assign	{ i_sata_ref_p, i_sata_ref_n } = { sata_ref_ck, !sata_ref_ck };

	IBUFDS_GTE2
	u_clkbuf (
		.I(i_sata_ref_p), .IB(i_sata_ref_n), .CEB(1'b0),
		.O(gtx_refck)
	);

	// Clock speed notes
	// {{{
	// fPLLClkOut = fPLLClkin * (N / M / 2)
	//	fPLLClkin = 150
	//	fPLLClkOut = 6GHz = (150 * 80 / 2)
	// fLineRate = fPLLClkout * 2 / D = 1500
	//
	//	fPllClkout = (1500 * 8 / 2) MHz == 6GHz (for 1500Mbps)
	//		= 150 * (N/M/2)
	//		=  75 * (N/M) = 75 * 40
	//			N = 40, M=1 (Alternatively, N=80, M=2)
	//
	// *X8B10BEN = 1
	// *X_DATA_WIDTH = 40
	// *_INT_DATAWIDTH = 1
	// FPGA Interface width = 32b
	// Internal width = 40b
	// Fabric clock = 1500 / 40 = 37.5MHz
	//		3000 / 40 = 75MHz, 6000/40 = 150MHz
	// TXCLK
	//	QPLLCLK/(D=(2,4,or ..) 8)/4/5 to achieve 6Gb,3Gb,or 1.5Gb line
	//		To achieve 1/40x line speed
	//
	// 6GHz => Lower frequency band, but still w/in 5.93-8GHz
	//
	// We use the QPLL over the CPLL, because the CPLL tops out at 3.3GHz,
	// and so the QPLL allows us to imagine a 6GHz, SATA v3 connection.
	// }}}
	GTXE2_COMMON #(
		// {{{
		.IS_DRPCLK_INVERTED(1'b0),
		.IS_GTGREFCLK_INVERTED(1'b0),
		.IS_QPLLLOCKDETCLK_INVERTED(1'b0),
		//
		// Clock frequency selection configuration
		// {{{
		.QPLL_REFCLK_DIV(1),		// = M, can be 1,2,3, or 4
		.QPLL_FBDIV(10'h120),		// N = 80
		.QPLL_FBDIV_RATIO(1),
		// }}}
		.QPLL_FBDIV_MONITOR_EN(1'b0),
		.SIM_QPLLREFCLK_SEL(3'b001),
		.SIM_RESET_SPEEDUP("TRUE"),
		// .SIM_VERSION("4.0"),
		//
		.BIAS_CFG			(64'h0000_0400_0000_1000),
		.COMMON_CFG			(32'h0),
		.QPLL_CFG			(27'h06801C1),
		.QPLL_CLKOUT_CFG		(4'b0000),
		.QPLL_COARSE_FREQ_OVRD		(6'b010000),
		.QPLL_COARSE_FREQ_OVRD_EN	(1'b0),
		.QPLL_CP			(10'h1f),
		.QPLL_CP_MONITOR_EN		(1'b0),
		.QPLL_DMONITOR_SEL		(1'b0),
		.QPLL_INIT_CFG			(24'h6),
		.QPLL_LOCK_CFG			(16'h21E8),
		.QPLL_LPF			(4'hf)
		// }}}
	) u_gtxclk (
		// {{{
		.QPLLREFCLKSEL(3'b001),		// GTREFCLK0 selected
		.GTREFCLK0(gtx_refck),
		.GTREFCLK1(gtx_refck),		// Unused
		.QPLLLOCK(qpll_lock),
		.QPLLLOCKDETCLK(i_wb_clk),
		.QPLLLOCKEN(1'b1),
		.QPLLPD(1'b0),	// Powers down the QPLL for pwr savings
		.QPLLRESET(pll_reset),
		//
		.QPLLOUTCLK(qpll_clk),
		.QPLLOUTREFCLK(qpll_refck),
		// DRP
		// {{{
		.DRPCLK(i_wb_clk),
		.DRPEN(1'b0),
		.DRPWE(1'b0),
		.DRPADDR(8'h0),
		.DRPDI(16'h0),
		.DRPDO(),
		.DRPRDY(),
		// }}}
		// Unused
		// {{{
		.QPLLDMONITOR(),
		//
		.REFCLKOUTMONITOR(),
		.GTGREFCLK(1'b0),	// Internal testing pport only
		.GTNORTHREFCLK0(1'b0),
		.GTNORTHREFCLK1(1'b0),
		.GTSOUTHREFCLK0(1'b0),
		.GTSOUTHREFCLK1(1'b0),
		.QPLLREFCLKLOST(),	// Output, indicates reference clk lost
		// Reserved
		.QPLLRSVD1(16'h0),
		.QPLLRSVD2(5'h1f),
		.BGBYPASSB(1'b1),	// Must be set to 1
		.BGMONITORENB(1'b1),	// Must be set to 1
		.BGPDB(1'b1),		// Must be set to 1
		.BGRCALOVRD(5'h1f),	// Must be set to 5'h1f
		.PMARSVD(8'h0),		// Reserved
		.RCALENB(1'b1),		// Reserved, must be set to 1
		.QPLLOUTRESET(1'b0)	// Reserved, must be set to 0
		//
		// }}}
		// }}}
	);

	GTXE2_CHANNEL #(
		// {{{
		// Power down control attributes
		// {{{
		// Settings should come from the transceivers wizard (??)
		.PD_TRANS_TIME_FROM_P2(12'h03C),
		.PD_TRANS_TIME_NONE_P2(8'h3c),
		.PD_TRANS_TIME_TO_P2(8'h64),
		.TRANS_TIME_RATE(8'h0E),
		.RX_CLKMUX_PD(1'b1),
		.TX_CLKMUX_PD(1'b1),
		// }}}
		// Clock configuration
		// {{{
		.CPLL_CFG(24'hBC07DC),
		// fPLLCLKout = fPLLCLKin * (FBDIV_45 * FBDIV) / (REFCLK_DIV)
		//	= fPLLCLKin * (15 / 1)
		//	= 200MHz * 15 = 3GHz
		.CPLL_FBDIV(3),
		.CPLL_FBDIV_45(5),
		.CPLL_INIT_CFG(24'h00001E),
		.CPLL_LOCK_CFG(16'h01E8),
		.CPLL_REFCLK_DIV(1),
		.SIM_CPLLREFCLK_SEL(3'b001),
		.PMA_RSV3(2'b00),
		// }}}
		// GTX Digital monitor
		// {{{
		.DMONITOR_CFG(24'h000A00),	// Ref says set to 24'h008101
		// }}}
		// Receiver configuration
		// {{{
		.RX_DATA_WIDTH(40),		// 32b data word / clk
		.RX_INT_DATAWIDTH(1'b1),	// data_width=32 or 64
		// RX AFE Attributes
		// {{{
		.RX_CM_SEL(2'b11),	// Programmable RX termination
		.RX_CM_TRIM(3'b010),	// 250mV common mode
		.TERM_RCAL_CFG(5'h10),
		.TERM_RCAL_OVRD(1'b0),	// External 100Ohm R not connected
		// }}}
		// RX Initialization and reset attributes
		// {{{
		.RXPMARESET_TIME(5'b00011),
		.RXCDRPHRESET_TIME(5'b00001),
		.RXCDRFREQRESET_TIME(5'b00001),
		.RXDFELPMRESET_TIME(7'h0f),
		.RXISCANRESET_TIME(5'b00001),
		.RXPCSRESET_TIME(5'b00001),
		.RXBUFRESET_TIME(5'b00001),
		// }}}
		// RX OOB Signaling attributes
		// {{{
		.RXOOB_CFG(7'b0000110),
		.SATA_BURST_VAL(3'b100),
		.SATA_EIDLE_VAL(3'b100),
		.SAS_MAX_COM(64),
		.SAS_MIN_COM(36),
		.SATA_MAX_BURST(8),
		.SATA_MAX_INIT(21),
		.SATA_MAX_WAKE(7),
		.SATA_MIN_BURST(4),
		.SATA_MIN_INIT(12),
		.SATA_MIN_WAKE(4),
		// }}}
		// RX Equalizer attributes
		// {{{
		.RX_OS_CFG(13'h0080),
		.RXLPM_LF_CFG(14'h00f0),
		.RXLPM_HF_CFG(14'h00f0),
		.RX_DFE_LPM_CFG(16'h0954),
		.RX_DFE_GAIN_CFG(23'h020fea),
		.RX_DFE_H2_CFG(12'h0),
		.RX_DFE_H3_CFG(12'h040),	// Default value
		.RX_DFE_H4_CFG(11'h0f0),	// Default value
		.RX_DFE_H5_CFG(11'h0e0),	// Default value
		.PMA_RSV(32'h00018480),
		.RX_DFE_LPM_HOLD_DURING_EIDLE(1'b0),
		.RX_DFE_XYD_CFG(13'h0),
		// PMA_RSV2
		// Bit [5] controls eye scan.  Set to zero to keep powered down
		.PMA_RSV2(16'h2050),
		.RX_BIAS_CFG(12'h004),
		.RX_DEBUG_CFG(12'h000),
		.RX_DFE_KL_CFG(13'h00fe),
		.RX_DFE_KL_CFG2(32'h301148AC),
		.RX_DFE_UT_CFG(17'h11e00),
		.RX_DFE_VP_CFG(17'h03f03),
		// }}}
		// RX Clock data recovery
		// {{{
		.RXCDR_CFG((SATA_GEN == 1) ? 72'h03_8000_8bff_4010_0008
			: (SATA_GEN == 2) ? 72'h03_8800_8bff_4020_0008
			: 72'h03_8000_8bff_1020_0010),
		.RXCDR_LOCK_CFG(6'b010101),
		.RXCDR_HOLD_DURING_EIDLE(1'b0),
		.RXCDR_FR_RESET_ON_EIDLE(1'b0),
		.RXCDR_PH_RESET_ON_EIDLE(1'b0),
		// }}}
		// RX Fabric clock output control attributes
		// {{{
		.RXBUF_RESET_ON_RATE_CHANGE("TRUE"),
		// fLineRate = fPLLCLKout * 2 / TXOUT_DIV
		//	Given fPLLClkout = 6GHz, to be in QPLL range, thus...
		//	= 6, 3, or 1.5GHz depending on SATA_GEN below
		.RXOUT_DIV((SATA_GEN <= 1) ? 8 : ((SATA_GEN == 2) ? 4 : 2)),
		// }}}
		// RX Margin Analysis (Eye Scan)
		// {{{
		.ES_VERT_OFFSET(9'h000),
		.ES_HORZ_OFFSET(12'h000),
		.ES_PRESCALE(5'h00),
		.ES_SDATA_MASK(80'h00000000000000000000),
		.ES_QUALIFIER(80'h00000000000000000000),
		.ES_QUAL_MASK(80'h00000000000000000000),
		.ES_EYE_SCAN_EN("TRUE"),
		.ES_ERRDET_EN("FALSE"),
		.ES_CONTROL(6'b000000),
		// }}}
		// RX Pattern checker attributes
		// {{{
		.RXPRBS_ERR_LOOPBACK(1'b0),
		// }}}
		// RX Comma alignment control
		// {{{
		// Although ALIGN primitives come in pairs, we sync on the
		// K byte that is first in the pair.  The next comma byte
		// of the pair will not come for another 3 clock cycles, for
		// this reason we cannot align on pairs of bytes.
		.ALIGN_COMMA_DOUBLE("FALSE"),	// Search for two commas in row
		// Which comma bits should be checked for?
		.ALIGN_COMMA_ENABLE({(10){OPT_AUTO_ALIGN}}),	// Chk all bits
		// Which bytes are allowed to contain the comma?  4=> byte 0
		.ALIGN_COMMA_WORD(4),	// Comma appears on byte zero *ONLY*
		// PCOMMA: The first comma pattern in a potential pair
		.ALIGN_PCOMMA_DET(OPT_AUTO_ALIGN ? "TRUE" : "FALSE"),	// 1st comma in (potential) pair
		.ALIGN_PCOMMA_VALUE(10'b01_0111_1100),	// 1st comma pattern
		// MCOMMA: The second comma pattern in a potential pair
		.ALIGN_MCOMMA_DET(OPT_AUTO_ALIGN ? "TRUE" : "FALSE"),	// 2nd comma in potential pair
		.ALIGN_MCOMMA_VALUE(10'b10_1000_0011),
		//
		.SHOW_REALIGN_COMMA(OPT_AUTO_ALIGN ? "TRUE" : "FALSE"),
		//
		.DEC_MCOMMA_DETECT("TRUE"),
		.DEC_PCOMMA_DETECT("TRUE"),
		.DEC_VALID_COMMA_ONLY("TRUE"),			// !!!!
		//
		// Manual comma alignment controls
		.RXSLIDE_AUTO_WAIT(7),
		.RXSLIDE_MODE(OPT_RXBUFFER ? "OFF" : "PCS"),
		//
		// Reserved value -- should use transceiver wizard value
		.RX_SIG_VALID_DLY(10),
		// }}}
		// RX 8B10B decoder
		// {{{
		.RX_DISPERR_SEQ_MATCH("TRUE"),
		.UCODEER_CLR(1'b0),
		//}}}
		// RX Buffer Bypass
		// {{{
		.RXBUF_EN(OPT_RXBUFFER ? "TRUE" : "FALSE"),
		.RX_XCLK_SEL(OPT_RXBUFFER ? "RXREC" : "RXUSR"),
		.RXPH_CFG(24'h000000),
		.RXPH_MONITOR_SEL(5'b00000),
		.RXPHDLY_CFG(24'h084020),
		.RXDLY_CFG(16'h001F),
		.RXDLY_LCFG(9'h030),
		.RXDLY_TAP_CFG(16'h0000),
		.RX_DDI_SEL(6'b000000),
		// }}}
		// RX Elastic buffer configuration
		// {{{
		.RX_BUFFER_CFG(6'b000000),
		.RX_DEFER_RESET_BUF_EN("TRUE"),
		.RXBUF_ADDR_MODE("FAST"),
		.RXBUF_EIDLE_HI_CNT(4'b1000),
		.RXBUF_EIDLE_LO_CNT(4'b0000),
		.RXBUF_RESET_ON_CB_CHANGE("TRUE"),
		.RXBUF_RESET_ON_COMMAALIGN("FALSE"),
		.RXBUF_RESET_ON_EIDLE("FALSE"),
		.RXBUF_THRESH_OVRD("FALSE"),
		.RXBUF_THRESH_OVFLW(61),
		.RXBUF_THRESH_UNDFLW(4),
		//
		.CBCC_DATA_SOURCE_SEL("DECODED"),
		.CLK_CORRECT_USE("FALSE"),	// Disable clock correction
		.CLK_COR_KEEP_IDLE("FALSE"),	//
		.CLK_COR_MAX_LAT(19),
		.CLK_COR_MIN_LAT(15),
		.CLK_COR_PRECEDENCE("TRUE"),
		.CLK_COR_REPEAT_WAIT(0),
		.CLK_COR_SEQ_LEN(1),
		// The below should be set to match to a single ALIGN
		// directives.  Since it can be used to match 4 bytes,
		// this should be possible -- one for each disparity
		.CLK_COR_SEQ_1_1(10'h100),
		.CLK_COR_SEQ_1_2(10'h000),
		.CLK_COR_SEQ_1_3(10'h000),
		.CLK_COR_SEQ_1_4(10'h000),
		.CLK_COR_SEQ_1_ENABLE(4'b1111),
		// CLK_COR_SEQ_1_USE -- is true by default, so no such param
		.CLK_COR_SEQ_2_1(10'h100),
		.CLK_COR_SEQ_2_2(10'h000),
		.CLK_COR_SEQ_2_3(10'h000),
		.CLK_COR_SEQ_2_4(10'h000),
		.CLK_COR_SEQ_2_ENABLE(4'b1111),
		.CLK_COR_SEQ_2_USE("FALSE"),
		//
		// }}}
		// RX Channel bonding
		// {{{
		// Used for aligning multiple RX channels.  SATA has only
		// a single such channel, so this capability is not needed.
		.CHAN_BOND_MAX_SKEW(1),
		.CHAN_BOND_KEEP_ALIGN("FALSE"),
		.CHAN_BOND_SEQ_1_1(10'h0),
		.CHAN_BOND_SEQ_1_2(10'h0),
		.CHAN_BOND_SEQ_1_3(10'b0),
		.CHAN_BOND_SEQ_1_4(10'b0),
		.CHAN_BOND_SEQ_1_ENABLE(4'b1111),
		//
		.CHAN_BOND_SEQ_2_1(10'b0),
		.CHAN_BOND_SEQ_2_2(10'b0),
		.CHAN_BOND_SEQ_2_3(10'b0),
		.CHAN_BOND_SEQ_2_4(10'b0),
		.CHAN_BOND_SEQ_2_ENABLE(4'b1111),
		.CHAN_BOND_SEQ_2_USE("FALSE"),
		.CHAN_BOND_SEQ_LEN(1),
		//
		.FTS_DESKEW_SEQ_ENABLE(4'b1111),
		.FTS_LANE_DESKEW_CFG(4'b1111),
		.FTS_LANE_DESKEW_EN("FALSE"),
		//
		.PCS_PCIE_EN("FALSE"),
		// }}}
		// RX Gearbox, supporting 64b/66b or 64b/67b decoding
		// {{{
		// }}}
		// RX Gearbox attributes
		// {{{
		.RXGEARBOX_EN("FALSE"),	// Disable the RX gearbox
		.GEARBOX_MODE(3'b000),
		// }}}
		// }}}
		// Transmitter configuration
		// {{{
		// FPGA TX Interface
		// {{{
		.TX_DATA_WIDTH(40),		// 32b data word / clk
		.TX_INT_DATAWIDTH(1'b1),	// data_width=32 or 64
		// }}}
		// TX 8B10B Setup
		// {{{
		// }}}
		// TX Gearbox (unused) Setup
		// {{{
		.TXGEARBOX_EN("FALSE"),
		// }}}
		// TX Buffer
		// {{{
		.TXBUF_EN(OPT_TXBUFFER ? "TRUE" : "FALSE"),
		.TX_XCLK_SEL(OPT_TXBUFFER ? "TXOUT" : "TXUSR"),
		.TXBUF_RESET_ON_RATE_CHANGE("TRUE"),
		// TX Buffer bypass
		.TXPH_CFG(16'h0780),	// Default value
		.TXPH_MONITOR_SEL(5'b00000),
		.TXPHDLY_CFG(24'h084020),	// Default value
		.TXDLY_CFG(16'h001F),		// Default value
		.TXDLY_LCFG(9'h030),		// Default value
		.TXDLY_TAP_CFG(16'h0000),	// Default value
		// }}}
		// TX Pattern Generator (Unused)
		// {{{
		// }}}
		// TX Fabric clock output control
		// {{{
		// fLineRate = fPLLCLKout * 2 / TXOUT_DIV
		//	= 6, 3, or 1.5GHz depending on SATA_GEN below
		.TXOUT_DIV((SATA_GEN == 1) ? 8 : ((SATA_GEN == 2) ? 4 : 2)),
		// }}}
		// TX Configurable Driver
		// {{{
		.TX_DEEMPH0(5'h00),
		.TX_DEEMPH1(5'h00),
		.TX_DRIVE_MODE("DIRECT"),
		.TX_MAINCURSOR_SEL(1'b0),	// Automatically determined
		.TX_MARGIN_FULL_0(7'b100_1110),	// A default value
		.TX_MARGIN_FULL_1(7'b100_1001),	// A default value
		.TX_MARGIN_FULL_2(7'b100_0101),	// A default value
		.TX_MARGIN_FULL_3(7'b100_0010),	// A default value
		.TX_MARGIN_FULL_4(7'b100_0000),	// A default value
		.TX_MARGIN_LOW_0(7'b100_0110),	// A default value
		.TX_MARGIN_LOW_1(7'b100_0100),	// A default value
		.TX_MARGIN_LOW_2(7'b100_0010),	// A default value
		.TX_MARGIN_LOW_3(7'b100_0000),	// A default value
		.TX_MARGIN_LOW_4(7'b100_0000),	// A default value
		.TX_PREDRIVER_MODE(1'b0),	// Restricted.  Leave at 1'b0
		.TX_QPI_STATUS_EN(1'b0),	// Not using QPI
		.TX_EIDLE_ASSERT_DELAY(3'b110),	// Default value
		.TX_EIDLE_DEASSERT_DELAY(3'b100),	// Default value
		.TX_LOOPBACK_DRIVE_HIZ("FALSE"),	// Reserved/default val
		// }}}
		// TX PCIe support (unused)
		// {{{
		.TX_RXDETECT_CFG(14'h1832),	// A default value
		.TX_RXDETECT_REF(3'b100),	// A default value
		// }}}
		// TX Out-of-Band Support (REQUIRED)
		// {{{
		.SATA_CPLL_CFG((SATA_GEN == 1) ? "VCO_750MHZ"
				: (SATA_GEN == 2) ? "VCO_1500MHz"
				: "VCO_3000MHZ"),	// Full rate mode
		.SATA_BURST_SEQ_LEN(4'b0101),	// 16 bursts in COM sequence
		// }}}
		// }}}
		// PCIe Clocking
		// {{{
		.RX_CLK25_DIV(8),	// 200MHz / 8 = 25MHz as required
		.TX_CLK25_DIV(8),
		// }}}
		.ES_PMA_CFG(10'b0000000000),
		.IS_CPLLLOCKDETCLK_INVERTED(1'b0),
		.IS_DRPCLK_INVERTED(1'b0),
		.IS_GTGREFCLK_INVERTED(1'b0),
		.IS_RXUSRCLK2_INVERTED(1'b0),
		.IS_RXUSRCLK_INVERTED(1'b0),
		.IS_TXPHDLYTSTCLK_INVERTED(1'b0),
		.IS_TXUSRCLK2_INVERTED(1'b0),
		.IS_TXUSRCLK_INVERTED(1'b0),
		.OUTREFCLK_SEL_INV(2'b11),
		// ???
		// [8] 1'b0 OOB pwr down when unused, 1'b1 powerd up (SATA)
		// [6:4] to be set to 3'b100
		// [3] 1'b0 selects sysclk, 1'b1 selects port CLKRSVD
		// We match GTX wizard in all but bit 8
		.PCS_RSVD_ATTR(48'h100),		// Reserved	// !!!!
		.PMA_RSV4(32'h00000000),
		.SIM_RECEIVER_DETECT_PASS("TRUE"),
		.SIM_RESET_SPEEDUP("FALSE"),
		.SIM_TX_EIDLE_DRIVE_LEVEL("X"),
		.SIM_VERSION("4.0"),
		// TST_RSV:
		//   [0]: Normal, 1'b1 overrides data delay ins w/ RX_DDI_SEL
		.TST_RSV(32'h00000000),
		.TXPCSRESET_TIME(5'b00001),
		.TXPMARESET_TIME(5'b00001)
		// }}}
	) u_gtx_channel (
		// {{{
		(* invertible_pin = "IS_RXUSRCLK_INVERTED" *)
		.RXUSRCLK(o_rx_clk),
		(* invertible_pin = "IS_RXUSRCLK2_INVERTED" *)
		.RXUSRCLK2(o_rx_clk), // For RX_INT_DATAWIDTH, == USRCLK
		(* invertible_pin = "IS_TXUSRCLK_INVERTED" *)
		.TXUSRCLK(o_tx_clk),
		(* invertible_pin = "IS_TXUSRCLK2_INVERTED" *)
		.TXUSRCLK2(o_tx_clk), // For TX_INT_DATAWIDTH, == USRCLK
		// Reset mode control ports
		// {{{
		.GTRESETSEL(1'b0),	// Sequential reset mode (recommended)
		.RESETOVRD(1'b0),	// Reserved -- set to ground
		// }}}
		// CPLL Reset
		// {{{
		.CPLLRESET(1'b1),
		.CPLLLOCKEN(1'b1),
		.CPLLLOCK(ign_cpll_locked),
		// }}}
		// TX Init and reset ports
		// {{{
		.GTTXRESET(tx_gtx_reset),
		.TXPMARESET(1'b0),
		.TXPCSRESET(1'b0),
		.CFGRESET(1'b0),
		.TXUSERRDY(tx_user_ready),
		.TXRESETDONE(tx_reset_done),
		.PCSRSVDOUT(),	// Open, unconnected, 16b reserved output
		.TXDLYSRESET(tx_user_ready && !tx_reset_done),
		.TXDLYSRESETDONE(),
		// }}}
		// RX Init and reset ports
		// {{{
		.GTRXRESET(rx_gtx_reset),
		.RXPMARESET(1'b0),
		.RXCDRRESET(1'b0),
		.RXCDRFREQRESET(1'b0),
		//
		.EYESCANRESET(1'b0),
		.RXPCSRESET(1'b0),
		.RXBUFRESET(1'b0),
		.RXOOBRESET(1'b0),
		.RXUSERRDY(rx_user_ready),
		.RXRESETDONE(rx_reset_done),	// rx_init.Xxresetdone
		.RXDLYSRESET(1'b0),
		.RXDLYSRESETDONE(),
		// }}}
		//
		(* invertible_pin = "IS_CPLLLOCKDETCLK_INVERTED" *)
		.CPLLLOCKDETCLK(1'b0),	// Reqd only if FBCLKLOST/REFCLKLOST usd
// SELECT ME WHEN DOING CLOCK SELECTION
		.CPLLREFCLKSEL(3'b000),	// Clock comes from GTREFCLK0
		.CPLLFBCLKLOST(),	// No connect
		.CPLLREFCLKLOST(),	// No connect
		//
		.GTREFCLKMONITOR(),
		// TX ouputs to pads
		.GTXTXP(o_tx_p), .GTXTXN(o_tx_n),
		// RX inputs from the pads
		.GTXRXP(i_rx_p), .GTXRXN(i_rx_n),
		// Power-down port control
		// {{{
		.CPLLPD(power_down),	// Keep powered up
		.RXPD(power_down ? 2'b11 : 2'b00),	// Rx power down
		.TXPD(power_down ? 2'b11 : 2'b00),	// Tx power down
		.TXPDELECIDLEMODE(1'b0), // Power down on async input (always 0)
		.RXPHDLYPD(power_down && OPT_RXBUFFER),
		.TXPHDLYPD(power_down && OPT_TXBUFFER),
		// }}}
		// Receive ports
		// {{{
		// RX Analog Front END
		// {{{
		.RXQPISENN(),
		.RXQPISENP(),
		.RXQPIEN(1'b0),
		// }}}
		// RX alignment control
		// {{{
		// inputs
		.RXCOMMADETEN(OPT_AUTO_ALIGN),	// Detect alignment primitives
		// Which commas should we align on?
		.RXMCOMMAALIGNEN(i_realign && OPT_AUTO_ALIGN), // M commas
		.RXPCOMMAALIGNEN(i_realign && OPT_AUTO_ALIGN), // P commas too
		.RXSLIDE(1'b0),	// No manual comma alignment
		// outputs
		.RXCOMMADET(ign_rx_comma),	// Open / unused, doesn't align w/ data
		.RXBYTEISALIGNED(syncd),
		.RXBYTEREALIGN(resyncd),
		// }}}
		// Dynamic Reconfiguration Port (DRP) control
		// {{{
		(* invertible_pin = "IS_DRPCLK_INVERTED" *)
		.DRPCLK(i_drp_clk),
		.DRPRDY(o_drp_ready),
		.DRPADDR(i_drp_addr),
		.DRPDI(i_drp_data[15:0]),
		.DRPEN(i_drp_enable),
		.DRPWE(i_drp_we),
		.DRPDO(o_drp_data),
		// }}}
		// Digital monitor
		// {{{
		.CLKRSVD(4'h0),
		.PCSRSVDIN(16'h0),	// Not really using this
		.DMONITOROUT(),		// Unused, no connect
		// }}}
		// RX Out-of-band Signaling
		// {{{
		.RXELECIDLEMODE(2'b00),			// Required for SATA
		.RXELECIDLE(o_rx_elecidle),
		.RXCOMINITDET(o_rx_cominit_detect),
		.RXCOMSASDET(),				// Open / no connect
		.RXCOMWAKEDET(o_rx_comwake_detect),
		// }}}
		// RX Equalizer ports
		// {{{
		.RXLPMEN(1'b1),		// Use the LPM mode, for less than 11Gb
		.RXDFELPMRESET(1'b0),
		.RXOSHOLD(1'b0),
		.RXOSOVRDEN(1'b0),
		.RXLPMLFHOLD(1'b0),
		.RXLPMLFKLOVRDEN(1'b0),
		.RXLPMHFHOLD(1'b0),
		.RXLPMHFOVRDEN(1'b0),
		.RXDFEAGCHOLD(1'b0),
		.RXDFEAGCOVRDEN(1'b0),
		.RXDFELFHOLD(1'b0),
		.RXDFELFOVRDEN(1'b0),
		.RXDFEUTHOLD(1'b0),
		.RXDFEUTOVRDEN(1'b0),
		.RXDFEVPHOLD(1'b0),
		.RXDFEVPOVRDEN(1'b0),
		.RXDFETAP2HOLD(1'b0),
		.RXDFETAP2OVRDEN(1'b0),
		.RXDFETAP3HOLD(1'b0),
		.RXDFETAP3OVRDEN(1'b0),
		.RXDFETAP4HOLD(1'b0),
		.RXDFETAP4OVRDEN(1'b0),
		.RXDFETAP5HOLD(1'b0),
		.RXDFETAP5OVRDEN(1'b0),
		.RXDFECM1EN(1'b0),
		.RXDFEXYDEN(1'b1),
		.RXDFEXYDOVRDEN(1'b0),
		.RXDFEVSEN(1'b0),
		.RXDFEXYDHOLD(1'b0),
		//
		//
		//
		.RXMONITOROUT(),	// Open / no connect
		// }}}
		// RX Clock data recovery
		// {{{
		.RXCDRHOLD(rx_cdr_hold),
		.RXCDROVRDEN(1'b0),
		.RXCDRRESETRSV(1'b0),
		.RXRATE((SATA_GEN==3) ? 3'd2 : (SATA_GEN==2) ? 3'd3 : 3'd4),
		.RXCDRLOCK(),	// Open / no connect
		// }}}
		// RX Fabric clock output control ports
		// {{{
		.RXOUTCLKSEL(3'b010),	// Use the RXOUTCLKPMA path
		.RXOUTCLKFABRIC(),	// Unused // no connect
		.RXOUTCLK(rx_clk_unbuffered),
		.RXOUTCLKPCS(),
		.RXRATEDONE(),		// Unused, since we never change rates
		.RXDLYBYPASS(OPT_RXBUFFER),
		// }}}
		// RX Margin Analysis (Eye) Ports
		// {{{
		.EYESCANDATAERROR(),
		.EYESCANTRIGGER(1'b0),
		.EYESCANMODE(1'b0),
		// }}}
		// RX Polarity control
		.RXPOLARITY(rx_polarity),
		// RX Pattern checker
		// {{{
		.RXPRBSCNTRESET(1'b0),
		.RXPRBSSEL(3'b0),
		.RXPRBSERR(),
		// }}}
		// RX 8B10B Decoder control
		// {{{
		.RX8B10BEN(1'b1),
		.RXCHARISCOMMA(),		// Unused, unnecessary, no conn
		.RXCHARISK(rx_char_is_k),
		.RXDISPERR(rx_disparity_err),	// 8b
		.RXNOTINTABLE(rx_invalid_code),	// 8b
		.SETERRSTATUS(1'b0),
		// }}}
		// RX Buffer Bypass
		// {{{
		.RXPHDLYRESET(1'b0),
		.RXPHALIGN(1'b0),
		.RXPHALIGNEN(1'b0),
		.RXPHOVRDEN(1'b0),
		.RXDLYEN(1'b0),
		.RXDLYOVRDEN(1'b0),
		.RXDDIEN(!OPT_RXBUFFER),
		.RXPHALIGNDONE(rx_align_done),
		.RXPHMONITOR(),		// Open / unused
		.RXPHSLIPMONITOR(),	// Open / unused
		// }}}
		// RX Elastic Buffer
		// {{{
		.RXBUFSTATUS(),
		// }}}
		// RX Clock correction
		// {{{
		.RXCLKCORCNT(),
		// }}}
		// RX Channel bonding (unused for SATA)
		// {{{
		// Used for aligning multiple RX channels.  SATA has only
		// a single such channel, so this capability is not needed.
		.RXCHANBONDSEQ(),
		.RXCHANISALIGNED(),
		.RXCHANREALIGN(),
		.RXCHBONDO(),
		.RXCHBONDI(5'h0),
		.RXCHBONDLEVEL(3'h0),
		.RXCHBONDMASTER(1'b0),
		.RXCHBONDSLAVE(1'b0),
		.RXCHBONDEN(1'b0),
		// }}}
		// RX Gearbox, supporting 64b/66b or 64b/67b decoding
		// {{{
		.RXDATAVALID(),		// Unused if gearbox is unused
		.RXGEARBOXSLIP(1'b0),
		.RXHEADER(),
		.RXHEADERVALID(),
		// RXSLIDE above
		.RXSTARTOFSEQ(),
		// }}}
		// PCIe Signals
		// {{{
		.RXSTATUS(),		// Unused / noconnect
		.PHYSTATUS(),	// Open / Unused
		// }}}
		// Other RX signals
		// {{{
		.RXDATA(raw_rx_data),
		.RXVALID(),	// Without the gearbox, we don't need this
		// }}}
		// }}}
		// Transmit ports
		// {{{
		// Transmit data
		// {{{
		.TXCHARDISPMODE(8'h0),	// When 8B10B disabled
		.TXCHARDISPVAL(8'h0),	// When 8B10B disabled
		.TXDATA(OPT_LITTLE_ENDIAN ? { 32'h0, i_tx_data }
			: { 32'h0,
			i_tx_data[ 7: 0], i_tx_data[15: 8],
			i_tx_data[23:16], i_tx_data[31:24]
			}),
		// }}}
		// TX 8B10B Encoder ports
		// {{{
		.TX8B10BEN(1'b1),	// Always use 8B10B encoding
		.TX8B10BBYPASS(8'h0),
		.TXCHARISK({ 7'h0, i_tx_primitive }),
		// }}}
		// TX Gearbox (unused), for 64B/66B or 64B/67B encoding
		// {{{
		.TXGEARBOXREADY(),
		.TXHEADER(3'h0),
		.TXSTARTSEQ(1'b0),
		.TXSEQUENCE(7'h0),
		// }}}
		// TX Buffer
		// {{{
		.TXBUFSTATUS(),
		// TX Buffer bypass
		.TXPHDLYRESET(1'b0),
		.TXPHALIGN(1'b0),	// Tied low when using auto alignment
		.TXPHALIGNEN(1'b0),	// Disable manual phase alignment
		.TXPHINIT(1'b0),	// Tie low when using auto alignment
		.TXPHOVRDEN(1'b0),	// Normal operation
		.TXDLYBYPASS(1'b1),	// Must=1 for a normal clock out in SIM
		.TXDLYEN(1'b0),
		.TXDLYHOLD(1'b0),
		.TXDLYOVRDEN(1'b0),
		(* invertible_pin = "IS_TXPHDLYTSTCLK_INVERTED" *)
		.TXPHDLYTSTCLK(1'b0),
		.TXDLYUPDOWN(1'b0),
		.TXPHALIGNDONE(),
		.TXPHINITDONE(),
		// }}}
		// TX Pattern Generator (unused)
		// {{{
		.TXPRBSSEL(3'h0),	// Let's keep this off
		.TXPRBSFORCEERR(1'b0),	// Not running tst mod, no need for errs
		// }}}
		// TX Fabric Clock Output control ports
		// {{{
		.TXOUTCLKSEL(3'b001),
		// Divide by 2, 4, or 8 -- see mapping
		.TXRATE((SATA_GEN==3) ? 3'd2 : (SATA_GEN==2) ? 3'd3 : 3'd4),
		.TXOUTCLKFABRIC(),	// Redundant, used by Xilinx for testing
		// QPLL_REFCK speed (6.6666ns => 150MHz)
		// At ... QPLL_CLK speed (0.1670 =~> 6GHz)
		//		/ 4 (b/c of TX_INT_DATA_WIDTH = 1)
		//		/ 5 (b/c of TX_DATA_WIDTH = 40)
		.TXOUTCLK(raw_tx_clk),	// --> send to BUFG if OPT_TXBUFFER, else MMCM
		.TXOUTCLKPCS(),		// Redundant, use TXOUTCLK instead
		.TXRATEDONE(),
		// }}}
		// TX Configurable driver ports
		// {{{
		.TXDEEMPH(1'b0),
		.TXDIFFCTRL(4'b1000),	// Voltage swing control 0.807 Vppd
		.TXELECIDLE(i_tx_elecidle),	// Creates an electrical idle
		.TXINHIBIT(1'b0),	// Always transmit
		.TXMAINCURSOR(7'h0),	//
		.TXMARGIN(3'h0),
		.TXQPIBIASEN(1'b0),	// No ground bias
		.TXQPISENN(),		// GPInput sensing, unused / no connect
		.TXQPISENP(),		// GPInput sensing, unused / no connect
		.TXQPISTRONGPDOWN(1'b0),	// No pull down
		.TXQPIWEAKPUP(1'b0),		// No pull up
		.TXPOSTCURSOR(5'h0),	// 0.00dB emphasis
		.TXPOSTCURSORINV(1'b0),	// Don't invrt pol of POSTCURSOR coef
		.TXPRECURSOR(5'h0),	// 0.00dB
		.TXPRECURSORINV(1'b0),	// Don't inv pol of PRECURSOR coeff
		.TXSWING(1'b0),		// Full swing
		.TXDIFFPD(1'b0),	// Unused
		.TXPISOPD(1'b0),	// Unused
		// }}}
		// TX PCIe support (unused)
		// {{{
		.TXDETECTRX(1'b0),	// Normal operation
		// }}}
		// TX Out-of-Band signaling
		// {{{
		.TXCOMFINISH(o_tx_comfinish),
		.TXCOMINIT(i_tx_cominit), // Initiate trans of COMINIT seq
		.TXCOMSAS(1'b0),	// (Not used in SATA mode)
		.TXCOMWAKE(i_tx_comwake),	// Initiate trans of COMWAKE seq
		// }}}
		// }}}
		.TSTOUT(),
		(* invertible_pin = "IS_GTGREFCLK_INVERTED" *)
		.GTGREFCLK(1'b0),
		.GTNORTHREFCLK0(1'b0),
		.GTNORTHREFCLK1(1'b0),
		.GTREFCLK0(i_ref_clk200),
		.GTREFCLK1(i_ref_clk200),	// We'll only select GTREFCLK0
		.GTSOUTHREFCLK0(1'b0),
		.GTSOUTHREFCLK1(1'b0),
		.QPLLCLK(qpll_clk),
		.QPLLREFCLK(qpll_refck),
		.TXPOLARITY(tx_polarity),	// 0 = Normal polarity
		.GTRSVD(16'h00),	// From wizard
		.TSTIN(20'hf_ff_ff),
		.RXMONITORSEL(2'b00),
		.RXSYSCLKSEL(2'b11),	// Clock source from QPLL
		.TXSYSCLKSEL(2'b11),	// Clock source from QPLL
		.LOOPBACK(3'b0),	// 0 => No TX->RX Loop back
		.TXBUFDIFFCTRL(3'h4),
		.PCSRSVDIN2(5'h00),
		.PMARSVDIN(5'h00),
		.PMARSVDIN2(5'h00)
		// }}}
	);
`endif

	// }}}

	assign	o_rx_primitive = rx_char_is_k[0];
	assign	o_rx_data = OPT_LITTLE_ENDIAN ? raw_rx_data[31:0]
			: { raw_rx_data[7:0], raw_rx_data[15:8],
				raw_rx_data[23:16], raw_rx_data[31:24] };

`ifdef	IVERILOG
	assign	o_rx_clk = rx_clk_unbuffered;
`else
	BUFG rxbuf ( .I(rx_clk_unbuffered), .O(o_rx_clk));
`endif

	generate if (OPT_TXBUFFER)
	begin : GEN_TXBUF
`ifdef	IVERILOG
		assign	o_tx_clk = raw_tx_clk;
`else
		wire		mmcm_feedback_unbuffered,
				mmcm_feedback, tx_unbuffered;

		// The MMCM
		// {{{
		/*
		PLLE2_BASE #(
			.CLKFBOUT_MULT(32),	// 37.5 * 24 = 900MHz
			.DIVCLK_DIVIDE(1),
			.CLKIN1_PERIOD(26.66),	// 37.5MHz
			.CLKOUT_DIVIDE(1),
			.CLKOUT0_DIVIDE(32)
		) u_txmmcm (
			.CLKIN1(raw_tx_clk),
			//
			.CLKFBOUT(mmcm_feedback_unbuffered),
			.CLKFBIN(mmcm_feedback),
			//
			.CLKOUT0(tx_unbuffered),
			.PWRDWN(1'b0),
			.RST(tx_gtx_reset),
			.LOCKED(tx_pll_lock)
		);
		*/
		assign	tx_pll_lock = qpll_lock;
		assign	tx_unbuffered = raw_tx_clk;
		// }}}

		// mmcm_feedback BUFG
		// {{{
		/*
		BUFG
		feedback(
			.I(mmcm_feedback_unbuffered),
			.O(mmcm_feedback)
		);
		*/
		// }}}

		// Final TX BUFG
		// {{{
		BUFG
		txbuf (
			.I(tx_unbuffered), .O(o_tx_clk));
		// }}}
`endif
	
	end else begin : NO_TXBUF
		// assign	o_tx_clk = raw_tx_clk;
		BUFG txbuf ( .I(raw_tx_clk), .O(o_tx_clk));
/*
		MMCM #(
		) tx_mmcm (
			.CLKIN(raw_tx_clk),
			.CLKOUT1(tx_clk_unbuffered)
		);

		BUFX txbuf (.I(tx_clk_unbuffered), .O(o_tx_clk));
*/

		assign	tx_pll_lock = qpll_lock;
	end endgenerate

endmodule
