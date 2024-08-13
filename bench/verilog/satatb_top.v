////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/verilog/satatb_top.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	A top-level simulation environment for use when testing this
//		SATA controller.  It's not designed to be an end-all
//	environment, but just enough to get us to where a proper Verilog
//	simulation of the GTX PHY can be built.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2022-2024, Gisselquist Technology, LLC
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
module	satatb_top;
	// Local declarations
	// {{{
	parameter	ADDRESS_WIDTH = 27;	// Byte address width
	parameter	DW = 64;		// Width of the main (wide) bus
	parameter	AW = ADDRESS_WIDTH-$clog2(DW/8); // Relevant addr bits
	parameter [0:0]	OPT_CPU = 1'b0;

	localparam	BFM_DW = 32,
			BFM_AW = ADDRESS_WIDTH-$clog2(BFM_DW/8);

	// Address map
	// {{{
	localparam [ADDRESS_WIDTH-1:0]
			MEM_ADDR  = { 1'b1,   {(ADDRESS_WIDTH-1){1'b0}} },
			ZDBG_ADDR = { 4'b0100, {(ADDRESS_WIDTH-4){1'b0}} },
			CONS_ADDR = { 4'b0011, {(ADDRESS_WIDTH-4){1'b0}} },
			CTRL_ADDR = { 4'b0010, {(ADDRESS_WIDTH-4){1'b0}} },
			DRP_ADDR  = { 4'b0001, {(ADDRESS_WIDTH-4){1'b0}} };
	localparam [ADDRESS_WIDTH:0]
			MEM_MASK  = { 2'b01,    {(ADDRESS_WIDTH-1){1'b0}} },
			ZDBG_MASK = { 5'b11111, {(ADDRESS_WIDTH-4){1'b0}} },
			CONS_MASK = { 5'b11111, {(ADDRESS_WIDTH-4){1'b0}} },
			CTRL_MASK = { 5'b11111, {(ADDRESS_WIDTH-4){1'b0}} },
			DRP_MASK  = { 5'b11111, {(ADDRESS_WIDTH-4){1'b0}} };
	// }}}
	reg	wb_clk, wb_reset;
	reg	ref_clk200;

	// BFM Bus Connections
	// {{{
	wire			bfm_cyc, bfm_stb, bfm_we,
				bfm_stall, bfm_ack, bfm_err;
	wire	[BFM_AW-1:0]	bfm_addr;
	wire	[BFM_DW-1:0]	bfm_data, bfm_idata;
	wire	[BFM_DW/8-1:0]	bfm_sel;

	wire			bfmw_cyc, bfmw_stb, bfmw_we,
				bfmw_stall, bfmw_ack, bfmw_err;
	wire	[AW:0]		bfmw_addr;
	wire	[BFM_DW-1:0]	bfmw_data, bfmw_idata;
	wire	[BFM_DW/8-1:0]	bfmw_sel;
	// }}}

	// CPU connections
	// {{{
	localparam	ZDBG_AW = ($clog2(DW/8) > 7) ? 1 : (7 - $clog2(DW/8)),
			ZDBG_ADDRESS_WIDTH = ZDBG_AW + $clog2(DW/8);

	wire			zdbgw_cyc,   zdbgw_stb, zdbgw_we,
				zdbgw_stall, zdbgw_ack, zdbgw_err;
	wire	[AW-1:0]	zdbgw_addr;
	wire	[DW-1:0]	zdbgw_data,  zdbgw_idata;
	wire	[DW/8-1:0]	zdbgw_sel;

	wire			zip_cyc, zip_stb, zip_we,
				zip_stall, zip_ack, zip_err;
	wire	[AW-1:0]	zip_addr;
	wire	[DW-1:0]	zip_data, zip_idata;
	wire	[DW/8-1:0]	zip_sel;
	// }}}

	// Control connections
	// {{{
	localparam	CTRL_AW = ($clog2(DW/8) > 5) ? 1 : (5 - $clog2(DW/8)),
			CTRL_ADDRESS_WIDTH = CTRL_AW + $clog2(DW/8);

	wire			sata_ctrlw_cyc, sata_ctrlw_stb, sata_ctrlw_we,
				sata_ctrlw_stall, sata_ctrlw_ack,sata_ctrlw_err;
	wire	[AW:0]		sata_ctrlw_addr;
	wire	[DW-1:0]	sata_ctrlw_data, sata_ctrlw_idata;
	wire	[DW/8-1:0]	sata_ctrlw_sel;

	wire			sata_ctrl_cyc, sata_ctrl_stb, sata_ctrl_we,
				sata_ctrl_stall, sata_ctrl_ack, sata_ctrl_err;
	wire	[CTRL_ADDRESS_WIDTH-3:0]	sata_ctrl_addr;
	wire	[32-1:0]	sata_ctrl_data, sata_ctrl_idata;
	wire	[32/8-1:0]	sata_ctrl_sel;

	wire			sata_int;
	// }}}

	// PHY DRP connection
	// {{{
	wire			drpw_cyc,  drpw_stb;
	wire			drpw_we,   drpw_stall, drpw_ack, drpw_err;
	wire	[AW:0]		drpw_addr;
	wire	[DW-1:0]	drpw_data, drpw_idata;
	wire	[DW/8-1:0]	drpw_sel;

	wire			drp_cyc,  drp_stb;
	wire			drp_we,   drp_stall, drp_ack, drp_err;
	wire	[9-1:0]		drp_addr;
	wire	[32-1:0]	drp_data, drp_idata;
	wire	[32/8-1:0]	drp_sel;
	// }}}

	// DMA connections
	// {{{
	wire			sata_dma_cyc, sata_dma_stb, sata_dma_we,
				sata_dma_stall, sata_dma_ack, sata_dma_err;
	wire	[AW-1:0]	sata_dma_addr;
	wire	[DW-1:0]	sata_dma_data, sata_dma_idata;
	wire	[DW/8-1:0]	sata_dma_sel;
	// }}}

	// Memory control
	// {{{
	wire			mem_cyc, mem_stb, mem_we,
				mem_stall, mem_ack, mem_err;
	wire	[AW:0]		mem_addr;
	wire	[DW-1:0]	mem_data, mem_idata;
	wire	[DW/8-1:0]	mem_sel;
	// }}}

	// Console
	// {{{
	wire			conw_cyc, conw_stb, conw_we,
				conw_stall, conw_ack, conw_err;
	wire	[AW-1:0]	conw_addr;
	wire	[DW-1:0]	conw_data, conw_idata;
	wire	[DW/8-1:0]	conw_sel;

	wire			con_cyc,   con_stb, con_we,
				con_stall, con_ack, con_err;
	wire	[CTRL_ADDRESS_WIDTH-$clog2(DW/8)-1:0]	con_addr;
	wire	[DW-1:0]	con_data,  con_idata;
	wire	[DW/8-1:0]	con_sel;

	wire		con_access;
	reg		con_write_en;
	reg	[7:0]	con_write_byte;
	integer		sim_console;
	// }}}

	wire			sata_rx_p, sata_rx_n,
				sata_tx_p, sata_tx_n;
	wire		sata_txphy_clk, sata_txphy_ready,
			sata_txphy_comwake, sata_txphy_comfinish,
			sata_txphy_elecidle, sata_txphy_cominit,
			sata_txphy_primitive;
	wire		sata_phy_reset, sata_phy_ready, sata_phy_init_err;
	wire	[31:0]	sata_txphy_data;
	wire		sata_rxphy_elecidle, sata_rxphy_cominit,
			sata_rxphy_comwake, sata_rxphy_cdrhold,
			sata_rxphy_cdrlock;

	wire		sata_rxphy_clk, sata_rxphy_valid;
	wire	[31:0]	sata_rxphy_data;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Clock and reset generation
	// {{{
	initial begin
		wb_clk = 1'b0;
		forever
			#5 wb_clk = !wb_clk;
	end

	initial	begin
		ref_clk200 = 1'b0;
		forever
			#2.5 ref_clk200 = !ref_clk200;
	end

	initial	begin
		wb_reset <= 1'b1;
		@(posedge wb_clk);
		@(posedge wb_clk)
			wb_reset <= 1'b0;
	end

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Wishbone BFM
	// {{{

	wb_bfm #(
		.AW(BFM_AW), .DW(BFM_DW), .LGFIFO(4)
	) u_bfm (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		//
		.o_wb_cyc(bfm_cyc), .o_wb_stb(bfm_stb), .o_wb_we(bfm_we),
		.o_wb_addr(bfm_addr), .o_wb_data(bfm_data), .o_wb_sel(bfm_sel),
		.i_wb_stall(bfm_stall), .i_wb_ack(bfm_ack),
			.i_wb_data(bfm_idata), .i_wb_err(bfm_err)
		// }}}
	);

	// Upsize to the full bus width
	wbupsz #(
		.ADDRESS_WIDTH(ADDRESS_WIDTH),
		.SMALL_DW(BFM_DW), .WIDE_DW(DW)
	) u_bfm_upsz (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		//
		.i_scyc(bfm_cyc), .i_sstb(bfm_stb), .i_swe(bfm_we),
		.i_saddr(bfm_addr), .i_sdata(bfm_data), .i_ssel(bfm_sel),
		.o_sstall(bfm_stall), .o_sack(bfm_ack),
			.o_sdata(bfm_idata), .o_serr(bfm_err),
		//
		.o_wcyc(bfmw_cyc), .o_wstb(bfmw_stb), .o_wwe(bfmw_we),
		.o_waddr(bfmw_addr), .o_wdata(bfmw_data), .o_wsel(bfmw_sel),
		.i_wstall(bfmw_stall), .i_wack(bfmw_ack),
			.i_wdata(bfmw_idata), .i_werr(bfmw_err)
		// }}}
	);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// (Optional) CPU control
	// {{{

	generate if (OPT_CPU)
	begin : GEN_CPU
		// {{{
		// Local declarations
		// {{{
		wire	[31:0]			zip_debug;
		wire				zip_prof_stb;
		wire	[ADDRESS_WIDTH-1:0]	zip_prof_addr;
		wire	[31:0]			zip_prof_ticks;
		//
		wire		zdbg_cyc, zdbg_stb, zdbg_we,
				zdbg_stall, zdbg_ack, zdbg_err;
		wire	[6:0]	zdbg_addr;
		wire	[31:0]	zdbg_data, zdbg_idata;
		wire	[3:0]	zdbg_sel;
		// }}}

		wbdown #(
			.ADDRESS_WIDTH(CTRL_ADDRESS_WIDTH),
			.WIDE_DW(DW), .SMALL_DW(32)
		) u_zipdbg_down (
			// {{{
			.i_clk(wb_clk), .i_reset(wb_reset),
			//
			.i_wcyc(zdbgw_cyc), .i_wstb(zdbgw_stb), .i_wwe(zdbgw_we),
			.i_waddr(zdbgw_addr[CTRL_AW-1:0]),
			.i_wdata(zdbgw_data), .i_wsel(zdbgw_sel),
			.o_wstall(zdbgw_stall),
				.o_wack(zdbgw_ack), .o_wdata(zdbgw_idata),
				.o_werr(zdbgw_err),
			//
			.o_scyc(zdbg_cyc), .o_sstb(zdbg_stb), .o_swe(zdbg_we),
			.o_saddr(zdbg_addr[ZDBG_ADDRESS_WIDTH-$clog2(32/8)-1:0]),
				.o_sdata(zdbg_data), .o_ssel(zdbg_sel),
			.i_sstall(zdbg_stall),
				.i_sack(zdbg_ack), .i_sdata(zdbg_idata),
				.i_serr(zdbg_err)
			// }}}
		);

		
		zipsystem #(
			// {{{
			.ADDRESS_WIDTH(ADDRESS_WIDTH),
			.RESET_ADDRESS(MEM_ADDR),
			.BUS_WIDTH(DW),
			.START_HALTED(0),
			.OPT_TRACE_PORT(1'b0),
			.OPT_SIM(1'b1), .OPT_CLKGATE(1'b1)
			// }}}
		) u_cpu (
			// {{{
			.i_clk(wb_clk), .i_reset(wb_reset),
			// WB Master
			// {{{
			.o_wb_cyc(zip_cyc), .o_wb_stb(zip_stb),
			.o_wb_we(zip_we),   .o_wb_addr(zip_addr),
			.o_wb_data(zip_data),.o_wb_sel(zip_sel),
			.i_wb_stall(zip_stall), .i_wb_ack(zip_ack),
			.i_wb_data(zip_idata), .i_wb_err(zip_err),
			// }}}
			.i_ext_int(sata_int),
			//
			.o_ext_int(zip_halted),
			// WB Slave -- debug port
			// {{{
			.i_dbg_cyc( zdbg_cyc),
			.i_dbg_stb( zdbg_stb),
			.i_dbg_we(  zdbg_we),
			.i_dbg_addr(zdbg_addr),
			.i_dbg_data(zdbg_data),
			.i_dbg_sel( zdbg_sel),
			//
			.o_dbg_stall(zdbg_stall),
			.o_dbg_ack(  zdbg_ack),
			.o_dbg_data( zdbg_idata),
			// }}}
			.o_cpu_debug(zip_debug),
			//
			.o_prof_stb(zip_prof_stb),
			.o_prof_addr(zip_prof_addr),
			.o_prof_ticks(zip_prof_ticks)
			// }}}
		);

		assign	zdbg_err = 1'b0;
		// }}}
	end else begin : NO_CPU
		assign	zip_cyc  = 1'b0;
		assign	zip_stb  = 1'b0;
		assign	zip_we   = 1'b0;
		assign	zip_addr = {(AW){1'b0}};
		assign	zip_data = {(DW){1'b0}};
		assign	zip_sel  = {(DW/8){1'b0}};

		assign	zdbgw_stall = 1'b0;
		assign	zdbgw_ack   = zdbgw_stb && !zdbgw_stall;
		assign	zdbgw_idata = {(DW){1'b0}};
	end endgenerate

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Crossbar(s) & control downsizer(s)
	// {{{

	wbxbar #(
		// {{{
		.NM(3), .NS(5), .DW(DW), .AW(AW+1),
		.SLAVE_ADDR({
			{ 1'b1, ZDBG_ADDR[ADDRESS_WIDTH-1:$clog2(DW/8)] },
			{ 1'b1, CONS_ADDR[ADDRESS_WIDTH-1:$clog2(DW/8)] },
			{ 1'b1, CTRL_ADDR[ADDRESS_WIDTH-1:$clog2(DW/8)] },
			{ 1'b1, DRP_ADDR[ADDRESS_WIDTH-1:$clog2(DW/8)] },
			{ 1'b0, MEM_ADDR[ADDRESS_WIDTH-1:$clog2(DW/8)] } }),
		.SLAVE_MASK({
			{ ZDBG_MASK[ADDRESS_WIDTH:$clog2(DW/8)] },
			{ CONS_MASK[ADDRESS_WIDTH:$clog2(DW/8)] },
			{ CTRL_MASK[ADDRESS_WIDTH:$clog2(DW/8)] },
			{ DRP_MASK[ADDRESS_WIDTH:$clog2(DW/8)] },
			{ MEM_MASK[ADDRESS_WIDTH:$clog2(DW/8)] } })
		// }}}
	) u_wbwide (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		//
		.i_mcyc({   bfmw_cyc,   zip_cyc, sata_dma_cyc   }),
		.i_mstb({   bfmw_stb,   zip_stb, sata_dma_stb   }),
		.i_mwe({    bfmw_we,    zip_we,  sata_dma_we    }),
		.i_maddr({ { 1'b1, bfmw_addr },  { 1'b1, zip_addr }, { 1'b0, sata_dma_addr } }),
		.i_mdata({  bfmw_data,  zip_data,  sata_dma_data }),
		.i_msel({   bfmw_sel,   zip_sel,   sata_dma_sel  }),
		.o_mstall({ bfmw_stall, zip_stall, sata_dma_stall }),
		.o_mack({   bfmw_ack,   zip_ack,   sata_dma_ack }),
		.o_mdata({  bfmw_idata, zip_idata, sata_dma_idata  }),
		.o_merr({   bfmw_err,   zip_err,   sata_dma_err  }),
		//
		.o_scyc({   zdbgw_cyc,   conw_cyc,   sata_ctrlw_cyc,   drpw_cyc,   mem_cyc   }),
		.o_sstb({   zdbgw_stb,   conw_stb,   sata_ctrlw_stb,   drpw_stb,   mem_stb   }),
		.o_swe({    zdbgw_we,    conw_we,    sata_ctrlw_we,    drpw_we,    mem_we    }),
		.o_saddr({  zdbgw_addr,  conw_addr,  sata_ctrlw_addr,  drpw_addr,  mem_addr  }),
		.o_sdata({  zdbgw_data,  conw_data,  sata_ctrlw_data,  drpw_data,  mem_data  }),
		.o_ssel({   zdbgw_sel,   conw_sel,   sata_ctrlw_sel,   drpw_sel,   mem_sel   }),
		.i_sstall({ zdbgw_stall, conw_stall, sata_ctrlw_stall, drpw_stall, mem_stall }),
		.i_sack({   zdbgw_ack,   conw_ack,   sata_ctrlw_ack,   drpw_ack,   mem_ack   }),
		.i_sdata({  zdbgw_idata, conw_idata, sata_ctrlw_idata, drpw_idata, mem_idata }),
		.i_serr({   zdbgw_err,   conw_err,   sata_ctrlw_err,   drpw_err,   mem_err   })
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// SATA Device Under Test (DUT)
	// {{{

	wbdown #(
		.ADDRESS_WIDTH(CTRL_ADDRESS_WIDTH),
		.WIDE_DW(DW), .SMALL_DW(32)
	) u_sata_ctrl_down (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		//
		.i_wcyc(sata_ctrlw_cyc), .i_wstb(sata_ctrlw_stb), .i_wwe(sata_ctrlw_we),
		.i_waddr(sata_ctrlw_addr[CTRL_AW-1:0]),
		.i_wdata(sata_ctrlw_data), .i_wsel(sata_ctrlw_sel),
		.o_wstall(sata_ctrlw_stall),
			.o_wack(sata_ctrlw_ack), .o_wdata(sata_ctrlw_idata),
			.o_werr(sata_ctrlw_err),
		//
		.o_scyc(sata_ctrl_cyc), .o_sstb(sata_ctrl_stb), .o_swe(sata_ctrl_we),
		.o_saddr(sata_ctrl_addr[CTRL_ADDRESS_WIDTH-$clog2(32/8)-1:0]),
			.o_sdata(sata_ctrl_data), .o_ssel(sata_ctrl_sel),
		.i_sstall(sata_ctrl_stall),
			.i_sack(sata_ctrl_ack), .i_sdata(sata_ctrl_idata),
			.i_serr(1'b0)
		// }}}
	);

	sata_controller #(
		.OPT_LOWPOWER(1'b1),
		.LGFIFO(12), .AW(AW), .DW(DW)
	) u_controller (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		// SOC control
		// {{{
		.i_wb_cyc(sata_ctrl_cyc), .i_wb_stb(sata_ctrl_stb),
			.i_wb_we(sata_ctrl_we), .i_wb_addr(sata_ctrl_addr[2:0]),
			.i_wb_data(sata_ctrl_data), .i_wb_sel(sata_ctrl_sel),
		.o_wb_stall(sata_ctrl_stall), .o_wb_ack(sata_ctrl_ack),
			.o_wb_data(sata_ctrl_idata),
		// }}}
		// DMA <-> memory
		// {{{
		.o_dma_cyc(sata_dma_cyc), .o_dma_stb(sata_dma_stb),
			.o_dma_we(sata_dma_we), .o_dma_addr(sata_dma_addr),
			.o_dma_data(sata_dma_data), .o_dma_sel(sata_dma_sel),
		.i_dma_stall(sata_dma_stall), .i_dma_ack(sata_dma_ack),
			.i_dma_data(sata_dma_idata),
			.i_dma_err(sata_dma_err),
		// }}}
		// PHY interface
		// {{{
		.i_rxphy_clk(sata_rxphy_clk),
		.i_rxphy_valid(sata_rxphy_valid),
		.i_rxphy_data(sata_rxphy_data),

		.i_txphy_clk(sata_txphy_clk),
		.o_txphy_primitive(sata_txphy_primitive),
		.o_txphy_data(sata_txphy_data),
		//
		.o_txphy_elecidle(	sata_txphy_elecidle),
		.o_txphy_cominit(	sata_txphy_cominit),
		.o_txphy_comwake(	sata_txphy_comwake),
		.i_txphy_comfinish(	sata_txphy_comfinish),
		//
		.o_phy_reset(sata_phy_reset), .i_phy_ready(sata_phy_ready),
		// }}}
		.i_rxphy_elecidle(	sata_rxphy_elecidle),
		.i_rxphy_cominit(	sata_rxphy_cominit),
		.i_rxphy_comwake(	sata_rxphy_comwake),
		.o_rxphy_cdrhold(	sata_rxphy_cdrhold),
		.i_rxphy_cdrlock(	sata_rxphy_cdrlock)
		// }}}
	);

	assign	sata_int = 1'b0;	// This needs to be set ... somewhere

	wbdown #(
		.ADDRESS_WIDTH(11),
		.WIDE_DW(DW), .SMALL_DW(32)
	) u_drp_down (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		//
		.i_wcyc(drpw_cyc), .i_wstb(drpw_stb), .i_wwe(drpw_we),
		.i_waddr(drpw_addr[12-$clog2(DW/8)-1:0]),
		.i_wdata(drpw_data), .i_wsel(drpw_sel),
		.o_wstall(drpw_stall),
			.o_wack(drpw_ack), .o_wdata(drpw_idata),
			.o_werr(drpw_err),
		//
		.o_scyc(drp_cyc), .o_sstb(drp_stb), .o_swe(drp_we),
		.o_saddr(drp_addr), .o_sdata(drp_data), .o_ssel(drp_sel),
		.i_sstall(drp_stall),
			.i_sack(drp_ack), .i_sdata(drp_idata),
			.i_serr(1'b0)
		// }}}
	);

	sata_phy
	u_sata_phy (
		// {{{
		.i_wb_clk(wb_clk), .i_reset(wb_reset),
		.i_ref_clk200(ref_clk200),

		.o_ready(sata_phy_ready), .o_init_err(sata_phy_init_err),
		// DRP interface
		// {{{
		.i_wb_cyc(drp_cyc), .i_wb_stb(drp_stb),
			.i_wb_we(drp_we),
		.i_wb_addr(drp_addr), .i_wb_data(drp_data),
			.i_wb_sel(drp_sel),
		.o_wb_stall(drp_stall), .o_wb_ack(drp_ack),
			.o_wb_data(drp_data),
		// }}}
		// Transmitter control
		// {{{
		.o_tx_clk(		sata_txphy_clk),
		.o_tx_ready(		sata_txphy_ready),
		.i_tx_elecidle(		sata_txphy_elecidle),
		.i_tx_cominit(		sata_txphy_cominit),
		.i_tx_comwake(		sata_txphy_comwake),
		.o_tx_comfinish(	sata_txphy_comfinish),
		// and for the data itself ...
		.i_tx_primitive(	sata_txphy_primitive),
		.i_tx_data(		sata_txphy_data),
		// }}}
		// Receiver control
		// {{{
		.o_rx_clk(		sata_rxphy_clk),
		.o_rx_primitive(	sata_rxphy_valid),
		.o_rx_data(		sata_rxphy_data),
		//
		.o_rx_elecidle(		sata_rxphy_elecidle),
		.o_rx_cominit_detect(	sata_rxphy_cominit),
		.o_rx_comwake_detect(	sata_rxphy_comwake),
		.i_rx_cdrhold(		sata_rxphy_cdrhold),
		.o_rx_cdrlock(		sata_rxphy_cdrlock),
		// }}}
		// I/O pad connections
		// {{{
		.o_tx_p(sata_tx_p), .o_tx_n(sata_tx_n),
		.i_rx_p(sata_rx_p), .i_rx_n(sata_rx_n)
		// }}}
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// SATA Device Verilog TB model
	// {{{

	sata_model
	u_sata_model (
		.i_rx_p(sata_tx_p), .i_rx_n(sata_tx_n),
		.o_tx_p(sata_rx_p), .o_tx_n(sata_rx_n)
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Wishbone RAM model
	// {{{

	memdev #(
		.LGMEMSZ(AW + $clog2(DW/8)), .DW(DW)
	) u_ram (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		//
		.i_wb_cyc(mem_cyc), .i_wb_stb(mem_stb),
			.i_wb_we(mem_we), .i_wb_addr(mem_addr),
			.i_wb_data(mem_data), .i_wb_sel(mem_sel),
		.o_wb_stall(mem_stall),
		.o_wb_ack(mem_ack),
		.o_wb_data(mem_idata)
		// }}}
	);

	assign	mem_err = 1'b0;

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Console (for the CPU)
	// {{{

	wbdown #(
		.ADDRESS_WIDTH(CTRL_ADDRESS_WIDTH),
		.WIDE_DW(DW), .SMALL_DW(32)
	) u_con_down (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		//
		.i_wcyc(conw_cyc), .i_wstb(conw_stb), .i_wwe(conw_we),
		.i_waddr(conw_addr[CTRL_ADDRESS_WIDTH-$clog2(DW/8)-1:0]),
		.i_wdata(conw_data), .i_wsel(conw_sel),
		.o_wstall(conw_stall),
			.o_wack(conw_ack), .o_wdata(conw_idata),
			.o_werr(conw_err),
		//
		.o_scyc(con_cyc), .o_sstb(con_stb), .o_swe(con_we),
		.o_saddr(con_addr), .o_sdata(con_data), .o_ssel(con_sel),
		.i_sstall(con_stall),
			.i_sack(con_ack), .i_sdata(con_idata),
			.i_serr(con_err)
		// }}}
	);


	// Console bus returns
	// {{{
	assign	con_stall = 1'b0;
	assign	con_err = 1'b0;

	initial	r_con_ack = 1'b0;
	always @(posedge wb_clk)
		r_con_ack <= !wb_reset && con_stb && !con_stall;
	assign	con_ack = r_con_ack;
	assign	con_idata = 32'h0;
	// }}}

	// Console implementation
	// {{{
	initial	begin
		sim_console = $fopen(CONSOLE_FILE);
	end

	assign	con_access = con_stb && !con_stall && con_we
				&& con_addr[1:0] == 2'b11 && con_sel[0];

	initial	con_write_en = 1'b0;
	always @(posedge wb_clk)
	if (wb_reset)
		con_write_en <= 1'b0;
	else if (con_stb && con_we && con_addr[1:0] == 2'b11 && con_sel[0])
		con_write_en <= 1'b1;
	else
		con_write_en <= 1'b0;

	initial	con_write_byte <= 8'h0;
	always @(posedge wb_clk)
	if (con_stb && con_we && con_addr[1:0] == 2'b11 && con_sel[0])
		con_write_byte <= con_data[7:0];

	always @(posedge i_clk)
	if (!wb_reset && con_write_en)
	begin
		$fwrite(sim_console, "%1s", con_write_byte);
		$write("%1s", con_write_byte);
	end
	// }}}

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Test-Bench driver
	// {{{
// `include SCRIPT
	// }}}
endmodule
