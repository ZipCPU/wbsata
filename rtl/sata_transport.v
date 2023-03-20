////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	sata/sata_transport.v
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
module	sata_transport #(
		// {{{
		// Verilator lint_off UNUSED
		parameter [0:0]	OPT_LOWPOWER = 1'b0,
				OPT_LITTLE_ENDIAN = 1'b0,
		// Verilator lint_on  UNUSED
		parameter	LGFIFO = 12
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
		output	reg		o_wb_ack,
		output	reg	[31:0]	o_wb_data,
		// }}}
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
	localparam	[2:0]	ADR_CONTROL = 3'h0,
				ADR_TXFIFO  = 3'h6,
				ADR_TXLAST  = 3'h7,
				ADR_RXFIFO  = 3'h6;
	// localparam	[LGFIFO:0]	FILL_THRESHOLD = (1<<LGFIFO)-32;

	reg			tx_active;
	wire			tx_write, tx_read,
				tx_full, tx_empty;
	wire	[4:0]		tx_fill;

	wire			rx_read, rx_empty, rx_full;
	reg			tran_full;
	wire	[4:0]		rx_fill;
	wire	[31:0]		rx_data;

	wire	[31:0]	cfg_word;
	reg		cfg_success, cfg_failed, cfg_link_err;
	reg	[31:0]	shadow_0, shadow_1, shadow_2, shadow_3, shadow_4;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Transmit: Host to device logic
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	reg		txphy_reset_n, tx_reset_n;
	reg	[1:0]	txphy_reset_pipe, tx_reset_pipe;

	reg		tx_request, txphy_request, txphy_request_pipe;
	reg		tx_ack, tx_ack_pipe, txphy_ack;

	wire		tx_fifo_read, sfifo_last;
	wire	[31:0]	tx_fifo_data;
	wire		tx_fifo_empty;

	// tx_request
	// {{{
	always @(posedge i_clk)
	if (i_reset || !tx_reset_n)
		tx_request <= 0;
	else if (tx_write && i_wb_addr == ADR_TXLAST)
		tx_request <= 1;
	else if (tx_ack)
		tx_request <= 0;
	// }}}

	// txphy_request, txphy_request_pipe
	// {{{
	always @(posedge i_phy_clk)
	if (!txphy_reset_n)
		{ txphy_request, txphy_request_pipe } <= 0;
	else
		{ txphy_request, txphy_request_pipe }
					<= { txphy_request_pipe, tx_request };
	// }}}

	// tx_active
	// {{{
	always @(posedge i_phy_clk)
	if (!txphy_reset_n)
		tx_active <= 0;
	else if (o_tran_valid && i_tran_ready && o_tran_last)
		tx_active <= 0;
	else if (txphy_request && !txphy_ack)
		tx_active <= 1;
	// }}}

	// txphy_ack
	// {{{
	always @(posedge i_phy_clk)
	if (!txphy_reset_n)
		txphy_ack <= 0;
	else if (o_tran_valid && i_tran_ready && o_tran_last)
		txphy_ack <= 1;
	else if (!txphy_request)
		txphy_ack <= 0;
	// }}}

	// tx_ack, tx_ack_pipe
	// {{{
	always @(posedge i_clk)
	if (!tx_reset_n)
		{ tx_ack, tx_ack_pipe } <= 0;
	else
		{ tx_ack, tx_ack_pipe } <= { tx_ack_pipe, txphy_ack };
	// }}}

	// txphy_reset_n, txphy_reset_pipe
	// {{{
	always @(posedge i_phy_clk or posedge i_reset)
	if (i_reset)
		{ txphy_reset_n, txphy_reset_pipe } <= 0;
	else if (i_link_err || !i_link_ready)
		{ txphy_reset_n, txphy_reset_pipe } <= 0;
	else
		{ txphy_reset_n, txphy_reset_pipe } <= { txphy_reset_pipe, 1'b1 };
	// }}}

	// tx_reset_n, tx_reset_pipe
	// {{{
	always @(posedge i_clk or negedge txphy_reset_n)
	if (!txphy_reset_n)
		{ tx_reset_n, tx_reset_pipe } <= 0;
	else
		{ tx_reset_n, tx_reset_pipe } <= { tx_reset_pipe, 1'b1 };
	// }}}

	// assign	tx_reset = i_reset || i_link_err || !i_link_ready;
	assign	tx_write = i_wb_stb && i_wb_we && !o_wb_stall
					&& i_wb_addr[2:1] == ADR_TXFIFO[2:1];
	assign	tx_read  = tx_active && i_tran_ready;
	assign	tx_fifo_read = !tx_fifo_empty && !tx_full;

	sfifo #(
		.BW(33), .LGFLEN(4)
	) tx_fifo (
		// {{{
		.i_clk(i_clk), .i_reset(!tx_reset_n),
		//
		.i_wr(tx_write), .i_data({
			i_wb_addr[0],
			i_wb_data[7:0], i_wb_data[15:8],
			i_wb_data[23:16], i_wb_data[31:24] }),
			.o_full(tx_full), .o_fill(tx_fill),
		//
		.i_rd(tx_fifo_read), .o_data({ sfifo_last, tx_fifo_data }),
			.o_empty(tx_fifo_empty)
		// }}}
	);

	afifo #(
		.WIDTH(33), .LGFIFO(LGFIFO)
	) tx_afifo (
		// {{{
		.i_wclk(i_clk), .i_wr_reset_n(tx_reset_n),
		//
		.i_wr(tx_fifo_read), .i_wr_data({ sfifo_last, tx_fifo_data }),
			.o_wr_full(tx_full),
		//
		.i_rclk(i_phy_clk), .i_rd_reset_n(txphy_reset_n),
		.i_rd(tx_read), .o_rd_data({ o_tran_last, o_tran_data }),
			.o_rd_empty(tx_empty)
		// }}}
	);

	assign	o_tran_valid = tx_read;

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Receive: Device to host logic
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//
	reg		rxphy_reset, rx_reset_n;
	reg	[1:0]	rxphy_pipe,  rx_reset_pipe;

	wire		rx_afifo_rd, rx_afifo_empty, ign_wr_full;
	wire	[31:0]	rx_afifo_data;

	reg		rx_full_pipe;

	// rxphy_reset, rxphy_pipe
	// {{{
	initial	{ rxphy_reset, rxphy_pipe } = 0;
	always @(posedge i_phy_clk or posedge i_reset)
	if (i_reset)
		{ rxphy_reset, rxphy_pipe } <= 0;
	else if (i_tran_abort)
		{ rxphy_reset, rxphy_pipe } <= 0;
	else
		{ rxphy_reset, rxphy_pipe } <= { rxphy_pipe, 1'b1 };
	// }}}

	// rx_reset_n, rx_reset_pipe
	// {{{
	initial	{ rx_reset_n, rx_reset_pipe } = 0;
	always @(posedge i_clk or posedge i_tran_abort)
	if (i_tran_abort)
		{ rx_reset_n, rx_reset_pipe } <= 0;
	else if (i_reset)
		{ rx_reset_n, rx_reset_pipe } <= 0;
	else
		{ rx_reset_n, rx_reset_pipe } <= { rx_reset_pipe, 1'b1 };
	// }}}

	assign	rx_read = i_wb_stb && !i_wb_we && !o_wb_stall
					&& i_wb_addr[2:1] == ADR_RXFIFO[2:1];

	afifo #(
		.WIDTH(32), .LGFIFO(LGFIFO)
	) rx_afifo (
		// {{{
		.i_wclk(i_phy_clk), .i_wr_reset_n(rxphy_reset),
		.i_wr(i_tran_valid), .i_wr_data(i_tran_data),
			.o_wr_full(ign_wr_full),
		//
		.i_rclk(i_clk), .i_rd_reset_n(rx_reset_n),
		.i_rd(rx_afifo_rd), .o_rd_data(rx_afifo_data),
			.o_rd_empty(rx_afifo_empty)
		// }}}
	);

	assign	rx_afifo_rd = !rx_afifo_empty && !rx_full;

	sfifo #(
		.BW(32), .LGFLEN(4)
	) rx_fifo (
		// {{{
		.i_clk(i_clk), .i_reset(!rx_reset_n),
		//
		.i_wr(rx_afifo_rd), .i_data(rx_afifo_data),
			.o_full(rx_full), .o_fill(rx_fill),
		//
		.i_rd(rx_read), .o_data(rx_data),
			.o_empty(rx_empty)
		// }}}
	);

	initial	{ tran_full, rx_full_pipe } = 2'b00;
	always @(posedge i_phy_clk)
	if (i_reset || i_tran_abort)
		{ tran_full, rx_full_pipe } <= 0;
	else
		{ tran_full, rx_full_pipe } <= { rx_full_pipe, rx_full };

	assign	o_tran_full  = tran_full;
	assign	o_tran_empty = rx_empty;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Wishbone control logic
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// shadow_*, cfg_*
	// {{{
	always @(posedge i_clk)
	if (i_reset)
	begin
		// {{{
		shadow_0 <= 0;
		shadow_1 <= 0;
		shadow_2 <= 0;
		shadow_3 <= 0;
		shadow_4 <= 0;

		cfg_link_err <= 0;
		cfg_success  <= 0;
		cfg_failed   <= 0;
		// }}}
	end else begin

		if (i_wb_we) case(i_wb_addr)
		ADR_CONTROL: begin
			if (i_wb_sel[0] && i_wb_data[2])
				cfg_success <= 1'b0;
			if (i_wb_sel[0] && i_wb_data[3])
				cfg_failed <= 1'b0;
			if (i_wb_sel[0] && i_wb_data[4])
				cfg_link_err <= 1'b0;
			end
		3'h1: begin
			// {{{
			if (i_wb_sel[0]) shadow_0[ 7: 0] <= i_wb_data[ 7: 0];
			if (i_wb_sel[1]) shadow_0[15: 8] <= i_wb_data[15: 8];
			if (i_wb_sel[2]) shadow_0[23:16] <= i_wb_data[23:16];
			if (i_wb_sel[3]) shadow_0[31:24] <= i_wb_data[31:24];
			end
			// }}}
		3'h2: begin
			// {{{
			if (i_wb_sel[0]) shadow_1[ 7: 0] <= i_wb_data[ 7: 0];
			if (i_wb_sel[1]) shadow_1[15: 8] <= i_wb_data[15: 8];
			if (i_wb_sel[2]) shadow_1[23:16] <= i_wb_data[23:16];
			if (i_wb_sel[3]) shadow_1[31:24] <= i_wb_data[31:24];
			end
			// }}}
		3'h3: begin
			// {{{
			if (i_wb_sel[0]) shadow_2[ 7: 0] <= i_wb_data[ 7: 0];
			if (i_wb_sel[1]) shadow_2[15: 8] <= i_wb_data[15: 8];
			if (i_wb_sel[2]) shadow_2[23:16] <= i_wb_data[23:16];
			if (i_wb_sel[3]) shadow_2[31:24] <= i_wb_data[31:24];
			end
			// }}}
		3'h4: begin
			// {{{
			if (i_wb_sel[0]) shadow_3[ 7: 0] <= i_wb_data[ 7: 0];
			if (i_wb_sel[1]) shadow_3[15: 8] <= i_wb_data[15: 8];
			if (i_wb_sel[2]) shadow_3[23:16] <= i_wb_data[23:16];
			if (i_wb_sel[3]) shadow_3[31:24] <= i_wb_data[31:24];
			end
			// }}}
		3'h5: begin
			// {{{
			if (i_wb_sel[0]) shadow_4[ 7: 0] <= i_wb_data[ 7: 0];
			if (i_wb_sel[1]) shadow_4[15: 8] <= i_wb_data[15: 8];
			if (i_wb_sel[2]) shadow_4[23:16] <= i_wb_data[23:16];
			if (i_wb_sel[3]) shadow_4[31:24] <= i_wb_data[31:24];
			end
			// }}}
		default: begin end
		endcase

		if (i_tran_success)
			cfg_success <= 1'b1;
		if (i_tran_failed)
			cfg_failed <= 1'b0;
		if (i_link_err)
			cfg_link_err <= 1'b1;
		if (i_link_err && tx_active)
			cfg_failed <= 1'b1;
	end
	// }}}

	assign	o_wb_stall = 1'b0;

	// o_wb_ack
	// {{{
	initial	o_wb_ack = 1'b0;
	always @(posedge i_clk)
	if (i_reset || !i_wb_cyc)
		o_wb_ack <= 1'b0;
	else
		o_wb_ack <= i_wb_stb && !o_wb_stall;
	// }}}

	assign	cfg_word = {
			{(12-5){ 1'b0 }}, tx_fill,
			{(12-5){ 1'b0 }}, rx_fill,
			2'h0, i_link_ready, cfg_link_err,
			cfg_failed, cfg_success, 1'b0, tx_active
		};

	// o_wb_data
	// {{{
	always @(posedge i_clk)
	case(i_wb_addr)
	0: o_wb_data <= cfg_word;
	1: o_wb_data <= shadow_0;
	2: o_wb_data <= shadow_1;
	3: o_wb_data <= shadow_2;
	4: o_wb_data <= shadow_3;
	5: o_wb_data <= shadow_4;
	6: o_wb_data <= rx_data;
	7: o_wb_data <= rx_data;
	endcase
	// }}}
	// }}}

	// Make Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, tx_empty, tx_full, i_tran_last, ign_wr_full };
	// Verilator lint_on  UNUSED
	// }}}
endmodule
