////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./rtl/sata_drp.v
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
// Copyright (C) 2021-2026, Gisselquist Technology, LLC
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
module	sata_drp #(
`ifdef	FORMAL
		parameter	LGWATCHDOG = 3
`else
		parameter	LGWATCHDOG = 6
`endif
	) (
		// {{{
		input	wire		i_clk, i_reset,
					i_soft_reset, // Resets DRP, not WB
		// Wishbone DRP Control
		// {{{
		input	wire		i_wb_cyc, i_wb_stb, i_wb_we,
		input	wire	[9:0]	i_wb_addr,
		input	wire	[31:0]	i_wb_data,
		input	wire	[3:0]	i_wb_sel,
		//
		output	wire		o_wb_stall,
		output	reg		o_wb_ack,
		output	reg	[31:0]	o_wb_data,
		output	reg		o_wb_err,
		// }}}
		output	wire	[1:0]	o_drp_enable,
		output	wire		o_drp_we,
		output	wire	[9:0]	o_drp_addr,
		output	wire	[15:0]	o_drp_data,
		input	wire	[1:0]	i_drp_ready,
		input	wire	[31:0]	i_drp_data,
		output	wire	[31:0]	o_debug
		// }}}
	);

	// Declarations
	// {{{
	wire		drp_enable, gtx_drp_enable, pll_drp_enable;
	wire	[15:0]	pll_drp_data, gtx_drp_data;
	wire		gtx_drp_ready, pll_drp_ready;

	reg		pending_ack, drop_wb_ack;
	reg	[LGWATCHDOG-1:0]	r_watchdog;
	reg	[31:0]	drp_debug;
	// }}}

	assign	drp_enable = (i_wb_stb && !o_wb_stall && (&i_wb_sel[1:0]))
				&& !i_reset;
	assign	o_drp_we     = drp_enable && i_wb_we;
	assign	o_drp_data   = i_wb_data[15:0];
	assign	o_wb_stall   = pending_ack;
	assign	o_drp_addr   = i_wb_addr[8:0];

	assign	pll_drp_enable = drp_enable && !i_wb_addr[9];
	assign	gtx_drp_enable = drp_enable &&  i_wb_addr[9];
	assign	o_drp_enable = { gtx_drp_enable, pll_drp_enable };
	assign	{ gtx_drp_ready, pll_drp_ready } = i_drp_ready;
	assign	{ gtx_drp_data, pll_drp_data } = i_drp_data;

	initial	pending_ack = 1'b0;
	always @(posedge i_clk)
	if (i_reset || i_soft_reset)
		pending_ack <= 1'b0;
	else if (pending_ack)
		pending_ack <= !pll_drp_ready && !gtx_drp_ready && (r_watchdog > 1);
	else if (i_wb_stb && !o_wb_stall)
		pending_ack <= (&i_wb_sel[1:0]);

	always @(posedge i_clk)
	if (i_reset || i_soft_reset || o_wb_ack || o_wb_err)
		r_watchdog <= 0;
	else if (i_wb_cyc && !o_wb_stall)
		r_watchdog <= -1;
	else if (r_watchdog != 0)
		r_watchdog <= r_watchdog - 1;

	initial	drop_wb_ack = 1'b0;
	always @(posedge i_clk)
	if (i_reset || i_soft_reset)
		drop_wb_ack <= 1'b0;
	else if (pll_drp_ready || gtx_drp_ready || (r_watchdog <= 1))
		drop_wb_ack <= 1'b0;
	else if (pending_ack && !i_wb_cyc)
		drop_wb_ack <= 1'b1;
	else if (!pending_ack)
		drop_wb_ack <= 1'b0;

	initial	o_wb_ack = 1'b0;
	always @(posedge i_clk)
	if (i_reset || !i_wb_cyc)
		o_wb_ack <= 1'b0;
	// else if (pending_ack && i_soft_reset)
	//	o_wb_ack <= 1'b1;
	else if (pending_ack)
		o_wb_ack <= (pll_drp_ready || gtx_drp_ready) && !drop_wb_ack;
	else
		o_wb_ack <= 1'b0;

	initial	o_wb_err = 1'b0;
	always @(posedge i_clk)
	if (i_reset || !i_wb_cyc)
		o_wb_err <= 1'b0;
	else if (i_wb_stb && !o_wb_stall
				&& (i_soft_reset || i_wb_sel[1:0] != 2'b11))
		o_wb_err <= 1'b1;
	else if (pll_drp_ready || gtx_drp_ready)
		o_wb_err <= 1'b0;
	else if (pending_ack && !drop_wb_ack && (i_soft_reset || (r_watchdog <= 1)))
		o_wb_err <= 1'b1;
	else
		o_wb_err <= 1'b0;

	always @(posedge i_clk)
	begin
		o_wb_data <= 32'h0;
		if (gtx_drp_ready)
			o_wb_data <= { 16'h0, gtx_drp_data };
		if (pll_drp_ready)
			o_wb_data <= { 16'h0, pll_drp_data };
	end

	always @(*)
	begin
		drp_debug = 32'h0;
		drp_debug[31]   = i_wb_cyc && i_wb_stb;
		drp_debug[30]   = i_wb_cyc;
		drp_debug[29]   = i_wb_stb;
		drp_debug[28]   = i_wb_we;
		drp_debug[27]   = o_wb_stall;	// = !pending_ack
		drp_debug[26]   = o_wb_ack;

		drp_debug[25]   = pll_drp_enable;
		drp_debug[24]   = gtx_drp_enable;
		drp_debug[23]   = drop_wb_ack;
		drp_debug[22]   = pll_drp_ready;
		drp_debug[21]   = gtx_drp_ready;

		if (gtx_drp_ready)
			drp_debug[15:0] = gtx_drp_data;
		else if (pll_drp_ready)
			drp_debug[15:0] = pll_drp_data;
		else if (o_drp_enable)
			drp_debug[9:0]  = o_drp_addr;
		else
			drp_debug[15:0] = o_drp_data;
	end

	assign	o_debug = drp_debug;
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
// Formal properties
// {{{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
`ifdef	FORMAL
	localparam	F_LGDEPTH = 4;
	reg	f_past_valid;
	wire	[F_LGDEPTH-1:0]	fwb_nreqs, fwb_nacks, fwb_outs;

	initial	f_past_valid = 0;
	always @(posedge i_clk)
		f_past_valid <= 1;

	always @(*)
	if (!f_past_valid)
		assume(i_reset);

	fwb_slave #(
		.AW(9), .F_MAX_STALL(1<<LGWATCHDOG),
		.F_MAX_ACK_DELAY(1<<LGWATCHDOG),
		.F_LGDEPTH(F_LGDEPTH)
	) fwb (
		.i_clk(i_clk), .i_reset(i_reset),
		.i_wb_cyc(i_wb_cyc), .i_wb_stb(i_wb_stb),
		.i_wb_addr(i_wb_addr), .i_wb_data(i_wb_data),
		.i_wb_sel(i_wb_sel), .i_wb_stall(o_wb_stall),
		.i_wb_ack(o_wb_ack),
		.i_wb_data(o_wb_data),
		.i_wb_err(o_wb_err),
		//
		.f_nreqs(fwb_nreqs),
		.f_nacks(fwb_nacks),
		.f_outstanding(fwb_outs)
	);

	always @(*)
	if (!i_reset && (pending_ack || drop_wb_ack))
		assert(!o_wb_ack && !o_wb_err);

	always @(*)
		assume(!i_drp_ready[1] || !i_drp_ready[0]);

	always @(*)
	if (!pending_ack)
		assume(i_drp_ready == 0);

	always @(*)
	if (!i_reset)
	begin
		if (i_wb_cyc && (o_wb_err || o_wb_ack))
		begin
			assert(fwb_outs == 1);
			assert(!pending_ack);
		end else if (i_wb_cyc)
		begin
			assert(fwb_outs == ((pending_ack && !drop_wb_ack) ? 1:0));
		end
	end

	always @(posedge i_clk)
	if (!i_reset && i_wb_cyc)
	begin
		cover(o_wb_ack);
		cover(o_wb_err);
	end
`endif
// }}}
endmodule
