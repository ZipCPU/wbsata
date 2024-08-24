////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/sata_transport.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	
//
//	Registers:
//	0-4:	Shadow register copy, includes BSY bit
//	5:	DMA Write address
//	6:	DMA Read address
//	:	DMA Length (found in the shadow register transfer count)
//	7:	(My status register)
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
module	sata_transport #(
		// {{{
		parameter	DW = 32, AW=30,
		// Verilator lint_off UNUSED
		parameter [0:0]	OPT_LOWPOWER = 1'b0,
				OPT_LITTLE_ENDIAN = 1'b0,
		// Verilator lint_on  UNUSED
		parameter	LGFIFO = 12,
		parameter	LGAFIFO=  4
		// }}}
	) (
		// {{{
		input	wire		i_clk,
		// Verilator lint_off SYNCASYNCNET
		input	wire		i_reset,
		// Verilator lint_on  SYNCASYNCNET
		input	wire		i_phy_clk,
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
		// Wishbone DMA interface
		// {{{
		output	wire		o_dma_cyc, o_dma_stb, o_dma_we,
		output	wire [AW-1:0]	o_dma_addr,
		output	wire [DW-1:0]	o_dma_data,
		output	wire [DW/8-1:0]	o_dma_sel,
		//
		input	wire		i_dma_stall,
		input	wire		i_dma_ack,
		input	wire	[31:0]	i_dma_data,
		input	wire		i_dma_err,
		// }}}
		output	wire		o_int,
		// Link layer interface
		// {{{
		// output	wire		o_cfg_continue_en,
		// output	wire		o_cfg_scrambler_en,
		// output	wire		o_cfg_crc_en,
		output	wire		o_tran_valid,
		input	wire		i_tran_ready,
		output	wire	[31:0]	o_tran_data,
		output	wire		o_tran_last,
		input	wire		i_tran_success,
		input	wire		i_tran_failed,
		//
		input	wire		i_tran_valid,
		output	wire		o_tran_full,
		output	wire		o_tran_empty,
		input	wire	[31:0]	i_tran_data,
		input	wire		i_tran_last,
		// Verilator lint_off SYNCASYNCNET
		input	wire		i_tran_abort,
		// Verilator lint_on  SYNCASYNCNET
		//
		input	wire		i_link_err, i_link_ready
		// }}}
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[0:0]	DMA_INC= 1'b1;
	localparam	[1:0]	SZ_BUS = 2'b00, SZ_32B = 2'b01;
	localparam	ADDRESS_WIDTH=AW+$clog2(DW/8);
	localparam	[$clog2(DW/8):0]	GEAR_32BYTES = 4;
	localparam	LGLENGTH=11;

	reg		phy_reset_n;
	reg	[1:0]	phy_reset_xpipe;
	wire		rxdma_reset, txdma_reset;
	(* ASYNC_REG="TRUE" *)
	reg		rx_reset_phyclk, tx_reset_phyclk;
	(* ASYNC_REG="TRUE" *)
	reg	[1:0]	rx_reset_xpipe,  tx_reset_xpipe;


	wire			s2mm_cyc, s2mm_stb, s2mm_we,
				s2mm_ack, s2mm_stall, s2mm_err;
	wire			mm2s_cyc, mm2s_stb, mm2s_we,
				mm2s_ack, mm2s_stall, mm2s_err;
	wire	[AW-1:0]	s2mm_addr, mm2s_addr;
	wire	[DW-1:0]	ign_s2mm_data, mm2s_bus_data;
	wire	[DW/8-1:0]	s2mm_sel, mm2s_sel;

	wire			s2mm_core_request, s2mm_core_busy,s2mm_core_err;
	wire	[ADDRESS_WIDTH-1:0]	s2mm_core_addr, mm2s_core_addr;
	wire			mm2s_core_request, mm2s_core_busy,mm2s_core_err;

	wire		rxgear_valid, rxgear_ready, rxgear_last,
			ign_rxgear_bytes_msb;
	wire		txgear_valid, txgear_ready, txgear_last;
	wire	[DW-1:0]	rxgear_data,  txgear_data;
	wire [$clog2(DW/8)-1:0]	rxgear_bytes;
	wire [$clog2(DW/8):0]	ign_txgear_bytes;

	wire			rxfifo_full, rx_afifo_empty;
	wire	[1+$clog2(DW/8)+DW-1:0]	rx_afifo_data;
	wire	[LGFIFO:0]	ign_rxfifo_fill;
	wire		rxfifo_valid, rxfifo_ready, rxfifo_last, rxfifo_empty;
	wire	[$clog2(DW/8)-1:0]	rxfifo_bytes;
	wire	[DW-1:0]		rxfifo_data;

	wire			mm2s_valid, mm2s_ready, mm2s_last;
	wire	[DW-1:0]	mm2s_data;
	wire [$clog2(DW/8):0]	mm2s_bytes;

	wire			mm2sgear_valid, mm2sgear_ready, mm2sgear_last,
				ign_mm2sgear_bytes_msb;
	wire	[DW-1:0]	mm2sgear_data;
	wire [$clog2(DW/8)-1:0]	mm2sgear_bytes;

	wire			txfifo_full, txfifo_empty, txfifo_last;
	wire	[DW-1:0]	txfifo_data;
	wire [$clog2(DW/8)-1:0]	txfifo_bytes;
	wire	[LGFIFO:0]	ign_txfifo_fill;

	wire			tx_afifo_full, tx_afifo_rd, tx_afifo_last,
				tx_afifo_empty;
	wire	[DW-1:0]	tx_afifo_data;
	wire [$clog2(DW/8)-1:0]	tx_afifo_bytes;

	wire			fis_valid, fis_last;
	wire	[31:0]		fis_data;

	reg	tx_gate;

	wire		datarx_valid, datarx_last, ign_datarx_ready;
	wire	[31:0]	datarx_data;

	// Verilator lint_off UNUSED
	wire			tran_request, tranreq_src;
	wire	[LGLENGTH:0]	tranreq_len;
	// Verilator lint_on  UNUSED
	wire		regtx_valid, regtx_ready, regtx_last;
	wire	[31:0]	regtx_data;


	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Reset CDC
	// {{{

	always @(posedge i_phy_clk or posedge i_reset)
	if (!i_reset)
		{ phy_reset_n, phy_reset_xpipe } <= -1;
	else
		{ phy_reset_n, phy_reset_xpipe } <= { phy_reset_xpipe,!i_reset};

	assign	rxdma_reset = !(s2mm_core_request || s2mm_core_busy);
	always @(posedge i_phy_clk)
		{ rx_reset_phyclk, rx_reset_xpipe }
					<= { rx_reset_xpipe, rxdma_reset };

	assign	txdma_reset = !(mm2s_core_request || mm2s_core_busy);
	always @(posedge i_phy_clk)
		{ tx_reset_phyclk, tx_reset_xpipe }
					<= { tx_reset_xpipe, txdma_reset };

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// FSM master Controller / sequencer
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	satatrn_rxregfis
	u_rxregfis(
		// {{{
		.i_clk(i_clk), .i_reset(i_reset), .i_phy_clk(i_phy_clk),
			.i_phy_reset_n(phy_reset_n), .i_link_err(i_link_err),
		//
		.i_valid(i_tran_valid),
		.i_data(i_tran_data),
		.i_last(i_tran_last),
		// .i_abort(i_tran_abort),
		//
		.o_reg_valid(fis_valid),
		.o_reg_data(fis_data),
		.o_reg_last(fis_last),
		//
		.o_data_valid(datarx_valid),
		.o_data_data(datarx_data),
		.o_data_last(datarx_last)
		// }}}
	);

	satatrn_fsm #(
		.ADDRESS_WIDTH(ADDRESS_WIDTH), .DW(DW), .LGLENGTH(LGLENGTH)
	) u_fsm (
		.i_clk(i_clk), .i_reset(i_reset),
		// Wishbone control inputs
		// {{{
		.i_wb_cyc(i_wb_cyc),	.i_wb_stb(i_wb_stb),
		.i_wb_we(i_wb_we),	.i_wb_addr(i_wb_addr),
		.i_wb_data(i_wb_data),	.i_wb_sel(i_wb_sel),
		.o_wb_stall(o_wb_stall),.o_wb_ack(o_wb_ack),
		.o_wb_data(o_wb_data),
		// }}}
		// .i_link_up
		// .o_link_reset _request
		//
		.o_tran_req(tran_request),
		.i_tran_busy(tran_request), // tranreq_busy),
		.i_tran_err(1'b0),
		.o_tran_src(tranreq_src),
		.o_tran_len(tranreq_len),
		//
		.o_int(o_int),
		//
		.s_pkt_valid(fis_valid),
		.s_data(fis_data),
		.s_last(fis_last),
		//
		.m_valid(regtx_valid),
		.m_ready(regtx_ready),
		.m_data(regtx_data),
		.m_last(regtx_last),
		// S2MM control signals
		// {{{
		.o_s2mm_request(s2mm_core_request),
		.i_s2mm_busy(s2mm_core_busy),
		.i_s2mm_err(s2mm_core_err),
		.o_s2mm_addr(s2mm_core_addr),
		//
		.i_s2mm_beat(s2mm_stb && !s2mm_stall),
		// }}}
		// MM2S control signals
		// {{{
		.o_mm2s_request(mm2s_core_request),
		.i_mm2s_busy(mm2s_core_busy),
		.i_mm2s_err(mm2s_core_err),
		.o_mm2s_addr(mm2s_core_addr)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// RX (incoming to memory) data path
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// RX Gears, to pack incoming 32b words into bus words

	satadma_rxgears #(
		.BUS_WIDTH(DW), .OPT_LITTLE_ENDIAN(1'b0)
	) u_rxgears (
		// {{{
		.i_clk(i_phy_clk), .i_reset(phy_reset_n),
		.i_soft_reset(rx_reset_phyclk),
		// .o_data_valid(datarx_valid),
		// .o_data_data(datarx_data),
		// .o_data_last(datarx_last)
		// Incoming RX data, minus the FIS word
		// {{{
		.S_VALID(datarx_valid),
		.S_READY(ign_datarx_ready),
		.S_DATA({ datarx_data[ 7: 0], datarx_data[15: 8],
				datarx_data[23:16], datarx_data[31:24],
				{(DW-32){1'b0}} }),
		.S_BYTES(GEAR_32BYTES),
		.S_LAST(datarx_last),
		// }}}
		// Outgoing data--packet to bus word sizes
		// {{{
		.M_VALID(rxgear_valid),
		.M_READY(rxgear_ready),
		.M_DATA( rxgear_data),
		.M_BYTES({ ign_rxgear_bytes_msb, rxgear_bytes }),
		.M_LAST( rxgear_last)
		// }}}
		// }}}
	);

	afifo #(
		// Just need enough of a FIFO to cross clock domains, no more
		.WIDTH(1+$clog2(DW/8)+DW), .LGFIFO(LGAFIFO)
	) u_rx_afifo (
		// {{{
		.i_wclk(i_phy_clk), .i_wr_reset_n(phy_reset_n),
		.i_wr(rxgear_valid), .i_wr_data({
				rxgear_last, rxgear_bytes, rxgear_data }),
			.o_wr_full(o_tran_full),
		//
		.i_rclk(i_clk), .i_rd_reset_n(!i_reset),
		.i_rd(!rxfifo_full), .o_rd_data(rx_afifo_data),
			.o_rd_empty(rx_afifo_empty)
		// }}}
	);

	sfifo #(
		.BW(1+$clog2(DW/8)+DW), .LGFLEN(LGFIFO)
	) rx_fifo (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset || i_tran_abort || rxdma_reset),
		//
		.i_wr(!rx_afifo_empty), .i_data(rx_afifo_data),
			.o_full(rxfifo_full), .o_fill(ign_rxfifo_fill),
		//
		.i_rd(rxfifo_ready), .o_data({ rxfifo_last,
						rxfifo_bytes, rxfifo_data }),
			.o_empty(rxfifo_empty)
		// }}}
	);

	assign	o_tran_empty = rxfifo_empty;
	assign	rxgear_ready = !rxfifo_full;
	assign	rxfifo_valid = !rxfifo_empty;

	satadma_s2mm #(
		.ADDRESS_WIDTH(ADDRESS_WIDTH), .BUS_WIDTH(DW),
		.OPT_LITTLE_ENDIAN(1'b0)
	) u_s2mm (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset || i_tran_abort),
		//
		.i_request(s2mm_core_request),
		.o_busy(s2mm_core_busy),
		.o_err(s2mm_core_err),
		.i_inc(DMA_INC),
		.i_size(SZ_BUS),
		.i_addr(s2mm_core_addr),
		//
		.S_VALID(rxfifo_valid),
		.S_READY(rxfifo_ready),
		.S_DATA( rxfifo_data),
		.S_BYTES({ (rxfifo_bytes==0), rxfifo_bytes }),
		.S_LAST( rxfifo_last),
		//
		.o_wr_cyc(s2mm_cyc), .o_wr_stb(s2mm_stb), .o_wr_we(s2mm_we),
		.o_wr_addr(s2mm_addr), .o_wr_data(ign_s2mm_data),
		.o_wr_sel(s2mm_sel),
		.i_wr_stall(s2mm_stall), .i_wr_ack(s2mm_ack),
			.i_wr_data({(DW){1'b0}}),
		.i_wr_err(s2mm_err)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// TX (memory to link layer) data path
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// MM2S
	satadma_mm2s #(
		.ADDRESS_WIDTH(ADDRESS_WIDTH), .BUS_WIDTH(DW),
		.LGLENGTH(LGLENGTH)
	) u_mm2s (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset || i_tran_abort),
		//
		.i_request(mm2s_core_request),
		.o_busy(mm2s_core_busy), .o_err(mm2s_core_err),
		.i_inc(DMA_INC), .i_size(SZ_BUS),
		.i_transferlen(tranreq_len),
		.i_addr(mm2s_core_addr),
		//
		.o_rd_cyc(mm2s_cyc), .o_rd_stb(mm2s_stb), .o_rd_we(mm2s_we),
		.o_rd_addr(mm2s_addr), .o_rd_data(mm2s_bus_data),
		.o_rd_sel(mm2s_sel),
		.i_rd_stall(mm2s_stall), .i_rd_ack(mm2s_ack),
			.i_rd_data(i_dma_data),
		.i_rd_err(mm2s_err),
		//
		.M_VALID(mm2s_valid),
		.M_READY(1'b1 || mm2s_ready),	// *MUST* be one, no FIFO here
		.M_DATA(mm2s_data),
		.M_BYTES(mm2s_bytes),
		.M_LAST(mm2s_last)
		// }}}
	);

	// TXGEARS: Partial -> BUSDW
	satadma_rxgears #(
		.BUS_WIDTH(DW), .OPT_LITTLE_ENDIAN(1'b0)
	) u_mm2s_gears (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset),
		.i_soft_reset(txdma_reset),
		.S_VALID(mm2s_valid),
		.S_READY(mm2s_ready),
		.S_DATA( mm2s_data),
		.S_BYTES(mm2s_bytes),
		.S_LAST( mm2s_last),
		//
		.M_VALID(mm2sgear_valid),
		.M_READY(mm2sgear_ready),
		.M_DATA( mm2sgear_data),
		.M_BYTES({ ign_mm2sgear_bytes_msb, mm2sgear_bytes }),
		.M_LAST( mm2sgear_last)
		// }}}
	);

	sfifo #(
		.BW(1+$clog2(DW/8)+DW), .LGFLEN(LGFIFO)
	) u_txfifo (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset || i_tran_abort || txdma_reset),
		//
		.i_wr(mm2sgear_valid), .i_data({ mm2sgear_last,
						mm2sgear_bytes, mm2sgear_data }),
			.o_full(txfifo_full), .o_fill(ign_txfifo_fill),
		//
		.i_rd(!tx_afifo_full), .o_data({ txfifo_last,
						txfifo_bytes, txfifo_data }),
			.o_empty(txfifo_empty)
		// }}}
	);

	assign	mm2sgear_ready = !txfifo_full;

	// AFIFO (?)
	afifo #(
		// Just need enough of a FIFO to cross clock domains, no more
		.WIDTH(1+$clog2(DW/8)+DW), .LGFIFO(LGAFIFO)
	) u_tx_afifo (
		// {{{
		.i_wclk(i_phy_clk), .i_wr_reset_n(phy_reset_n),
		.i_wr(!txfifo_empty),
			.i_wr_data({ txfifo_last, txfifo_bytes, txfifo_data }),
			.o_wr_full(tx_afifo_full),
		//
		.i_rclk(i_clk), .i_rd_reset_n(!i_reset),
		.i_rd(tx_afifo_rd), .o_rd_data({
				tx_afifo_last, tx_afifo_bytes, tx_afifo_data }),
			.o_rd_empty(tx_afifo_empty)
		// }}}
	);

	// TXGears: BUSDW -> 32b
	satadma_txgears #(
		.BUS_WIDTH(DW)
	) u_txgears(
		// {{{
		.i_clk(i_phy_clk), .i_reset(!phy_reset_n),
		.i_soft_reset(tx_reset_phyclk),
		.i_size(SZ_32B),
		.S_VALID(!tx_afifo_empty),
		.S_READY(tx_afifo_rd),
		.S_DATA( tx_afifo_data),
		.S_BYTES({ (tx_afifo_bytes == 0), tx_afifo_bytes }),
		.S_LAST( tx_afifo_last),
		//
		.M_VALID(txgear_valid),
		.M_READY(txgear_ready),
		.M_DATA( txgear_data),
		.M_BYTES(ign_txgear_bytes),
		.M_LAST( txgear_last)
		// }}}
	);

	satatrn_txarb
	u_txarb (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset), .i_phy_clk(i_phy_clk),
			.i_phy_reset_n(phy_reset_n),//.i_link_err(i_link_err),
		//
		// Incoming control data for transmission, on i_clk
		// {{{
		.i_reg_valid(regtx_valid),
		.o_reg_ready(regtx_ready),
		.i_reg_data( regtx_data),
		.i_reg_last( regtx_last),
		// }}}
		.i_txgate(tx_gate),	// Full packet is ready
		// Incoming data for transmission, on i_phy_clk
		// {{{
		.i_data_valid(txgear_valid),
		.o_data_ready(txgear_ready),
		.i_data_data({	txgear_data[DW- 1:DW- 8],
				txgear_data[DW- 9:DW-16],
				txgear_data[DW-17:DW-24],
				txgear_data[DW-25:DW-32] }),
		.i_data_last( txgear_last),
		// }}}
		// Outgoing packet data
		// {{{
		.o_valid(o_tran_valid),
		.i_ready(i_tran_ready),
		.o_data(o_tran_data),
		.o_last(o_tran_last)
		// }}}
		// }}}
	);

	// tx_gate
	// {{{
	always @(posedge i_clk)
	if (i_reset || txdma_reset)
		tx_gate <= 1'b0;
	else if (mm2s_valid && mm2s_ready && mm2s_last)
		tx_gate <= 1'b1;
	// }}}

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Wishbone arbiter
	// {{{
	satatrn_wbarbiter #(
		.DW(DW), .AW(AW)
	) u_wbarbiter (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset),
		//
		.i_a_cyc(mm2s_cyc),  .i_a_stb(mm2s_stb),  .i_a_we(mm2s_we),
		.i_a_adr(mm2s_addr), .i_a_dat(mm2s_bus_data), .i_a_sel(mm2s_sel),
		.o_a_stall(mm2s_stall), .o_a_ack(mm2s_ack), .o_a_err(mm2s_err),
		//
		.i_b_cyc(s2mm_cyc),  .i_b_stb(s2mm_stb),  .i_b_we(s2mm_we),
		.i_b_adr(s2mm_addr), .i_b_dat(mm2s_bus_data), .i_b_sel(s2mm_sel),
		.o_b_stall(s2mm_stall), .o_b_ack(s2mm_ack), .o_b_err(s2mm_err),
		//
		.o_cyc(o_dma_cyc),  .o_stb(o_dma_stb),  .o_we(o_dma_we),
		.o_adr(o_dma_addr), .o_dat(o_dma_data), .o_sel(o_dma_sel),
		.i_stall(i_dma_stall), .i_ack(i_dma_ack), .i_err(i_dma_err)
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Wishbone control logic
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// }}}

	// Make Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0,
			// FIX THESE!  These shouldn't be ignored
			i_tran_success, i_tran_failed, i_link_ready,
			//
			// These are expected to be ignored
			ign_datarx_ready, ign_txgear_bytes,
			ign_mm2sgear_bytes_msb, ign_rxgear_bytes_msb,
			ign_txfifo_fill, ign_rxfifo_fill, ign_s2mm_data
			};
	// Verilator lint_on  UNUSED
	// }}}
endmodule
