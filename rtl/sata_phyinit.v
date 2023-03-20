////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	sata_phyinit.v
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
`default_nettype	none
// }}}
module	sata_phyinit #(
		parameter [0:0]	OPT_WAIT_ON_ALIGN = 1'b0
	) (
		// {{{
		input	wire	i_clk, i_reset,
		input	wire	i_power_down,
		output	wire	o_pll_reset,
		input	wire	i_pll_locked,
		output	wire	o_gtx_reset,
		input	wire	i_gtx_reset_done,
		input	wire	i_aligned,
		output	wire	o_err,
		output	wire	o_user_ready,
		output	wire	o_complete
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
				FSM_ALIGN_WAIT   = 4'h7,
				FSM_READY        = 4'h8;

	reg	[3:0]	fsm_state;
	reg	[11:0]	fsm_counter;
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

	wire		aligned;
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

	// aligned
	// {{{
	generate if (OPT_WAIT_ON_ALIGN)
	begin : SYNC_ALIGN

		reg	[3:0]	aligned_pipe;
		reg		sync_align;

		always @(posedge i_clk)
		if (i_reset || i_power_down || o_gtx_reset)
			{ sync_align, aligned_pipe } <= 0;
		else
			{ sync_align, aligned_pipe } <= { aligned_pipe, i_aligned };
		assign	aligned = sync_align;
	end else begin
		assign	aligned = 1'b1;

		// Verilator lint_off UNUSED
		wire	unused_align;
		assign	unused_align = &{ 1'b0, i_aligned };
		// Verilator lint_on  UNUSED
	end endgenerate

	// }}}

	// r_cdr_wait: Minimum wait time for the recovered clock to lock
	// {{{
	always @(posedge i_clk)
	if (i_reset || i_power_down || fsm_state < FSM_CDRLOCK_WAIT)
		{ r_cdr_zerowait, r_cdr_wait } <= 0;
	else if (!r_cdr_zerowait)
		{ r_cdr_zerowait, r_cdr_wait }
			<= { r_cdr_zerowait, r_cdr_wait } + 1'b1;
	// }}}

	assign	cdr_lock = r_cdr_zerowait;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Master state machine
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	always @(posedge i_clk)
	if (i_reset || i_power_down)
	begin
		fsm_state   <= FSM_POWER_DOWN;
		fsm_counter <= 100;
		fsm_zero    <= 0;
	end else begin
		if (fsm_counter > 0)
			fsm_counter <= fsm_counter - 1;
		fsm_zero    <= (fsm_counter <= 1);
		case(fsm_state)
		FSM_POWER_DOWN:	if (fsm_zero)
			begin
			fsm_state   <= FSM_PLL_RESET;
			fsm_counter <= 0;
			fsm_zero    <= 1;
			end
		FSM_PLL_RESET: if (fsm_zero)
			begin
			fsm_state   <= FSM_PLL_WAIT;
			fsm_counter <= 4;
			fsm_zero    <= 0;
			end
		FSM_PLL_WAIT: if (fsm_zero && pll_locked)
			begin
			fsm_state   <= FSM_GTX_RESET;
			fsm_counter <= 4;
			fsm_zero    <= 0;
			end
		FSM_GTX_RESET: if (fsm_zero)
			begin
			fsm_state   <= FSM_USER_READY;
			fsm_counter <= 4;
			fsm_zero    <= 0;
			end
		FSM_USER_READY: if (fsm_zero)
			begin
			fsm_state   <= FSM_GTX_WAIT;
			fsm_counter <= 4;
			fsm_zero    <= 0;
			end
		FSM_GTX_WAIT: if (fsm_zero && gtx_reset_done)
			begin
			fsm_state   <= FSM_CDRLOCK_WAIT;
			fsm_counter <= 4;
			fsm_zero    <= 0;
			end
		FSM_CDRLOCK_WAIT: if (fsm_zero && cdr_lock)
			begin
			fsm_state   <= (OPT_WAIT_ON_ALIGN) ? FSM_ALIGN_WAIT : FSM_READY;
			fsm_counter <= 4;
			fsm_zero    <= 0;
			end
		FSM_ALIGN_WAIT: if (fsm_zero && aligned)
			begin
			fsm_state   <= FSM_READY;
			fsm_counter <= 1;
			fsm_zero    <= 0;
			end
		FSM_READY: if (fsm_zero)
			begin
			fsm_state   <= FSM_READY;
			fsm_counter <= 0;
			fsm_zero    <= 1;
			end
		default: begin
			fsm_state   <= FSM_PLL_RESET;
			fsm_counter <= 0;
			fsm_zero    <= 1;
			end
		endcase

		if (!pll_locked && fsm_state > FSM_POWER_DOWN)
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
	assign	o_pll_reset = (fsm_state == FSM_PLL_RESET);
	assign	o_gtx_reset = (fsm_state == FSM_GTX_RESET
				|| fsm_state == FSM_PLL_RESET
				|| fsm_state == FSM_PLL_WAIT);
	assign	o_user_ready = (fsm_state >= FSM_GTX_WAIT);
	assign	o_complete = (fsm_state >= FSM_READY);
	// }}}
endmodule
