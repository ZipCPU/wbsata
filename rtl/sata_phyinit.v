////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./rtl/sata_phyinit.v
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
module	sata_phyinit (
		// {{{
		input	wire		i_clk, i_reset,
		input	wire		i_power_down,
		output	wire		o_pll_reset,
		input	wire		i_pll_locked,
		output	wire		o_gtx_reset,
		input	wire		i_gtx_reset_done,
		input	wire		i_phy_clk,
		output	wire		o_err,
		output	wire		o_user_ready,
		output	wire		o_complete,
		output	reg	[31:0]	o_debug
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[3:0]	FSM_POWER_DOWN   = 4'h0,
				FSM_PLL_RESET    = 4'h1,
				FSM_PLL_WAIT     = 4'h2,
				FSM_GTX_RESET    = 4'h3,
				FSM_USER_READY   = 4'h4,
				FSM_GTX_WAIT     = 4'h5,
				FSM_CDRLOCK_WAIT = 4'h6,
				FSM_READY        = 4'h8;

	reg	[3:0]	fsm_state;
	reg	[6:0]	fsm_counter;
	reg		fsm_zero;

	reg		r_cdr_zerowait;
	reg	[10:0]	r_cdr_wait;
	wire		cdr_lock;

	reg		watchdog_timeout;
	reg	[19:0]	watchdog_timer;

	reg	[4:0]	pll_lock_pipe;
	reg		pll_locked;

	reg	[4:0]	gtx_reset_pipe;
	reg		gtx_reset_done;

	reg		r_pll_reset, r_gtx_reset, r_user_ready, r_complete;

	reg	[2:0]	aux_clk_counter;
	reg		last_phyck_msb, phyck_msb, phyck_msb_xpipe, lost_clock,
			aux_clk;
	reg	[5:0]	lost_clk_counter;
	reg		valid_clock;
	reg	[2:0]	clk_counts;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Condition & synchronize inputs
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// pll_locked
	// {{{
	always @(posedge i_clk)
	if (i_reset || i_power_down || o_pll_reset)
		{ pll_locked, pll_lock_pipe } <= 0;
	else
		{ pll_locked, pll_lock_pipe } <= { pll_lock_pipe,i_pll_locked };
	// }}}

	// gtx_reset_done
	// {{{
	always @(posedge i_clk)
	if (i_reset || i_power_down || o_pll_reset || o_gtx_reset)
		{ gtx_reset_done, gtx_reset_pipe } <= 0;
	else
		{ gtx_reset_done, gtx_reset_pipe }
					<= { gtx_reset_pipe, i_gtx_reset_done };
	// }}}

	// r_cdr_wait: Minimum wait time for the recovered clock to lock
	// {{{
	always @(posedge i_clk)
	if (i_reset || i_power_down || fsm_state < FSM_CDRLOCK_WAIT)
		{ r_cdr_zerowait, r_cdr_wait } <= 0;
	else if (!r_cdr_zerowait)
		{ r_cdr_zerowait, r_cdr_wait } <= r_cdr_wait + 1'b1;
	// }}}

	assign	cdr_lock = r_cdr_zerowait;

	// Detect when/if our clock is available

	initial	{ aux_clk, aux_clk_counter } = 0;
	always @(posedge i_phy_clk)
		{ aux_clk, aux_clk_counter } <= { aux_clk, aux_clk_counter } +1;

	initial	{ phyck_msb, phyck_msb_xpipe } = 0;
	always @(posedge i_clk)
	if (i_reset || i_power_down || r_gtx_reset)
		{ phyck_msb, phyck_msb_xpipe } <= 0;
	else
		{ phyck_msb, phyck_msb_xpipe } <= { phyck_msb_xpipe, aux_clk };

	initial	last_phyck_msb = 0;
	always @(posedge i_clk)
	if (i_reset || i_power_down || r_gtx_reset)
		last_phyck_msb <= 0;
	else
		last_phyck_msb <= phyck_msb;

	initial	{ lost_clock, lost_clk_counter } = -1;
	initial	clk_counts  = 0;
	initial	valid_clock = 1'b0;
	always @(posedge i_clk)
	if (r_gtx_reset)
	begin
		{ lost_clock, lost_clk_counter } <= -1;
		clk_counts <= 0;
		valid_clock <= 0;
	end else if (phyck_msb != last_phyck_msb)
	begin
		{ lost_clock, lost_clk_counter } <= 0;
		if (!valid_clock)
			{ valid_clock, clk_counts } <= clk_counts + 1;
	end else if (!lost_clock)
		{ lost_clock, lost_clk_counter } <= lost_clk_counter + 1;
	else begin
		valid_clock <= 1'b0;
		clk_counts <= 0;
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Master state machine
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//
	initial	r_pll_reset = 1'b1;
	initial	r_gtx_reset = 1'b1;
	initial	r_user_ready = 1'b0;
	initial	r_complete   = 1'b0;
	always @(posedge i_clk)
	if (i_reset || i_power_down)
	begin
		fsm_state   <= FSM_POWER_DOWN;
		fsm_counter <= 100;
		fsm_zero    <= 0;
		//
		r_pll_reset <= 1;
		r_gtx_reset <= 1;
		r_user_ready <= 0;
		r_complete   <= 0;
	end else begin
		if (fsm_counter > 0)
			fsm_counter <= fsm_counter - 1;
		fsm_zero    <= (fsm_counter <= 1);
		r_pll_reset <= 0;
		r_gtx_reset <= 0;
		r_user_ready<= 0;
		r_complete  <= 0;
		case(fsm_state)
		FSM_POWER_DOWN:	begin
			r_pll_reset <= 1;
			r_gtx_reset <= 1;
			if (fsm_zero)
			begin
				fsm_state   <= FSM_PLL_RESET;
				fsm_counter <= 0;
				fsm_zero    <= 1;
			end end
		FSM_PLL_RESET: begin
			r_pll_reset <= 1;
			r_gtx_reset <= 1;
			if (fsm_zero)
			begin
				fsm_state   <= FSM_PLL_WAIT;
				fsm_counter <= 4;
				fsm_zero    <= 0;

				r_pll_reset <= 0;
			end end
		FSM_PLL_WAIT: begin
			r_gtx_reset <= 1;
			if (fsm_zero && pll_locked)
			begin
				fsm_state   <= FSM_GTX_RESET;
				fsm_counter <= 50;	// Guarantee 500ns GTX reset
				fsm_zero    <= 0;
			end end
		FSM_GTX_RESET: begin
			r_gtx_reset <= 1;
			if (fsm_zero && !gtx_reset_done)
			begin
				fsm_state   <= FSM_USER_READY;
				fsm_counter <= 4;
				fsm_zero    <= 0;

				r_gtx_reset <= 0;
			end end
		FSM_USER_READY: if (fsm_zero && valid_clock && !lost_clock)
			begin
			fsm_state   <= FSM_GTX_WAIT;
			fsm_counter <= 4;
			fsm_zero    <= 0;

			r_user_ready <= 1;
			end
		FSM_GTX_WAIT: begin
			r_user_ready <= 1;
			if (fsm_zero && gtx_reset_done)
			begin
				fsm_state   <= FSM_CDRLOCK_WAIT;
				fsm_counter <= 4;
				fsm_zero    <= 0;
			end end
		FSM_CDRLOCK_WAIT: begin
			r_user_ready <= 1;
			if (fsm_zero && cdr_lock)
			begin
				fsm_state   <= FSM_READY;
				fsm_counter <= 4;
				fsm_zero    <= 0;
				r_complete  <= 1'b1;
			end end
		FSM_READY: begin
			r_user_ready <= 1;
			r_complete   <= 1;
			if (fsm_zero)
			begin
				fsm_state   <= FSM_READY;
				fsm_counter <= 0;
				fsm_zero    <= 1;
			end end
		default: begin
			fsm_state   <= FSM_PLL_RESET;
			fsm_counter <= 0;
			fsm_zero    <= 1;
			end
		endcase

		if (!pll_locked && fsm_state > FSM_PLL_WAIT)
		begin
			fsm_state   <= FSM_PLL_RESET;
			fsm_counter <= 4;
			fsm_zero    <= 0;
		end else if (watchdog_timeout && fsm_state > FSM_GTX_RESET)
		begin
			fsm_state   <= FSM_GTX_RESET;
			fsm_counter <= 4;
			fsm_zero    <= 0;
		end
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Watchdog timer
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	always @(posedge i_clk)
	if (i_reset || i_power_down
		|| (watchdog_timeout && fsm_state > FSM_GTX_RESET))
	begin
		watchdog_timer   <= 0;
		watchdog_timeout <= 0;
	end else if (fsm_state == FSM_READY)
	begin
		watchdog_timer <= 0;
		watchdog_timeout <= 0;
	end else if (!watchdog_timeout)
	begin
		{ watchdog_timeout, watchdog_timer }
			<= { watchdog_timeout, watchdog_timer } + 1;
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Output assignments
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	assign	o_err = (watchdog_timeout && fsm_state > FSM_GTX_RESET);
	assign	o_pll_reset = r_pll_reset; // (fsm_state <= FSM_PLL_RESET);
	assign	o_gtx_reset = r_gtx_reset; // (fsm_state <= FSM_GTX_RESET);
	assign	o_user_ready = r_user_ready; // (fsm_state >= FSM_GTX_WAIT);
	assign	o_complete = r_complete;	// (fsm_state >= FSM_READY);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Debug outputs
	// {{{

	always @(posedge i_clk)
	begin
		o_debug <= 0;
		// o_debug[31] <= ({ o_err, o_user_ready, o_complete }
		//		!= o_debug[20:18]);
		o_debug[31] <= valid_clock && lost_clock;

		//
		o_debug[22] <= o_gtx_reset;
		o_debug[21] <= o_pll_reset;
		o_debug[20] <= o_err;
		o_debug[19] <= o_user_ready;
		o_debug[18] <= o_complete;
		o_debug[17] <= fsm_zero;
		o_debug[16] <= watchdog_timeout;
		o_debug[15] <= i_power_down;
		o_debug[14] <= r_cdr_zerowait;	// == cdr_lock
		o_debug[13] <= valid_clock;
		o_debug[12] <= gtx_reset_done;
		o_debug[11] <= pll_locked;
		o_debug[10:4] <= fsm_counter;
		o_debug[3:0] <= fsm_state;
	end
	// }}}
endmodule
