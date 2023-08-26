////////////////////////////////////////////////////////////////////////////////
//
// Filename:	satatb_top.v
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
// }}}
module	satatb_top;
	// Local declarations
	// {{{
	parameter	AW = 30, DW = 64;

	reg	wb_clk, wb_reset;

	// Control connections
	// {{{
	wire			wb_ctrl_cyc, wb_ctrl_stb, wb_ctrl_we,
				wb_ctrl_stall, wb_ctrl_ack, wb_ctrl_err;
	wire	[2-1:0]		wb_ctrl_addr;
	wire	[32-1:0]	wb_ctrl_data, wb_ctrl_idata;
	wire	[32/8-1:0]	wb_ctrl_sel;
	// }}}

	// PHY DRP connection
	// {{{
	wire			wb_drp_cyc, wb_drp_stb, wb_drp_we,
				wb_drp_stall, wb_drp_ack, wb_drp_err;
	wire	[10-1:0]	wb_drp_addr;
	wire	[32-1:0]	wb_drp_data, wb_drp_idata;
	wire	[32/8-1:0]	wb_drp_sel;
	// }}}

	// DMA connections
	// {{{
	wire			wb_sata_cyc, wb_sata_stb, wb_sata_we,
				wb_sata_stall, wb_sata_ack, wb_sata_err;
	wire	[AW-1:0]	wb_sata_addr;
	wire	[DW-1:0]	wb_sata_data, wb_sata_idata;
	wire	[DW/8-1:0]	wb_sata_sel;
	// }}}
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
		@(posedge clk);
		@(posedge clk)
			wb_reset <= 1'b0;
	end

	initial	{ wb_drp_cyc,  wb_drp_stb  } = 2'b00;
	initial	{ wb_sata_cyc, wb_sata_stb } = 2'b00;

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// SATA Device Under Test (DUT)
	// {{{

	sata_controller #(
		.OPT_LOWPOWER(1'b1),
		.LGFIFO(12), .AW(AW), .DW(DW)
	) u_controller (
		// {{{
		.i_clk(wb_clk), .i_reset(wb_reset),
		// SOC control
		// {{{
		.i_wb_cyc(wb_ctrl_cyc), .i_wb_stb(wb_ctrl_stb),
			.i_wb_we(wb_ctrl_we), .i_wb_addr(wb_ctrl_addr),
			.i_wb_data(wb_ctrl_data), .i_wb_sel(wb_ctrl_sel),
		.o_wb_stall(wb_ctrl_stall, .o_wb_ack(wb_ctrl_ack),
			.o_wb_data(wb_ctrl_idata),
		// }}}
		// DMA <-> memory
		// {{{
		.o_dma_cyc(wb_sata_cyc), .o_dma_stb(wb_sata_stb),
			.o_dma_we(wb_sata_we), .o_dma_addr(wb_sata_addr),
			.o_dma_data(wb_sata_data), .o_dma_sel(wb_sata_sel),
		.i_dma_stall(wb_sata_stall), .i_dma_ack(wb_sata_ack),
			.i_dma_data(wb_sata_idata),
			.i_dma_err(wb_sata_err),
		// }}}
		// PHY interface
		// {{{
		.i_rxphy_clk(sata_rxphy_clk),
		.i_rxphy_valid(sata_rxphy_valid),.i_rxphy_data(sata_rxphy_data),

		.i_txphy_clk(sata_txphy_clk),
		.o_txphy_primitive(sata_txphy_primitive),
		.o_txphy_data(sata_txphy_data),
		//
		.o_tx_elecidle(		sata_txphy_elecidle),
		.o_tx_cominit(		sata_txphy_cominit),
		.o_tx_comwake(		sata_txphy_comwake),
		.i_tx_comfinish(	sata_txphy_comfinish),
		//
		.o_phy_reset(sata_phy_reset), .i_phy_ready(sata_phy_ready)
		// }}}
		// }}}
	);

	sata_phy #(
	) u_sata_phy (
		// {{{
		.i_wb_clk(wb_clk), .i_reset(wb_reset),
		.i_ref_clk200(ref_clk200),

		.o_ready(sata_phy_ready), .o_init_err(sata_phy_init_err),
		// DRP interface
		// {{{
		.i_wb_cyc(wb_drp_cyc), .i_wb_stb(wb_drp_stb),
			.i_wb_we(wb_drp_we),
		.i_wb_addr(wb_drp_addr), .i_wb_data(wb_drp_data),
			.i_wb_sel(wb_drp_sel),
		.o_wb_stall(wb_drp_stall), .o_wb_ack(wb_drp_ack),
			.o_wb_data(wb_drp_data),
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
		.o_rx_cominit_detect(sata_rxphy_cominit),
		.o_rx_comwake_detect(sata_rxphy_comwake),
		// }}}
		// I/O pad connections
		// {{{
		.o_tx_p(sata_tx_p), .o_tx_n(sata_tx_n),
		.i_tx_p(sata_rx_p), .i_tx_n(sata_rx_n)
		// }}}
		// }}}
	);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// SATA Device Verilog TB model
	// {{{

	satadev #(
	) u_sata_device (
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
		.i_clk(wb_clk), .i_reset(wb_reset),
		.i_wb_cyc(wb_sata_cyc), .i_wb_stb(wb_sata_stb),
			.i_wb_we(wb_sata_we), .i_wb_addr(wb_sata_addr),
			.i_wb_data(wb_sata_data), .i_wb_sel(wb_sata_sel),
		.o_wb_stall(wb_sata_stall),
		.o_wb_ack(wb_sata_ack),
		.o_wb_data(wb_sata_idata)
	);

	assign	wb_sata_err = 1'b0;

	// }}}

endmodule
