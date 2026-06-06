////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/mdl_srxcomsigs.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	In a test bench setting, detect the COMINIT/COMRESET,
//		and COMWAKE SATA signals.
//
//	How do you tell if the line is idle?  If truly idle, the differential
//	signal is to be at "common mode levels", something that doesn't really
//	exist in a 4-character (0, 1, x, z) Verilog simulation.  Therefore,
//	let's call anything "common mode" that isn't a proper differential
//	signal, such as x, z, or N==P (negative and positive polarity are the
//	same--an invalid condition).  Hence, we'll call a '1' any time i_rx_p
//	is truly a '1' and i_rx_n is truly a '0'.  Further, after a sufficient
//	number of idle signals (signals where i_rx_p is zero), we can declare
//	ourselves to be "idle".
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2022-2026, Gisselquist Technology, LLC
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
module mdl_srxcomsigs #(
		// Verilator lint_off UNUSED
		parameter	OVERSAMPLE = 4,
		// Verilator lint_on   UNUSED
		// The SATA SYMBOL duration is one over the symbol rate, either
		// 1.5GHz, 3.0GHz, or 6GHz, here expressed in ns.
		parameter	realtime	CLOCK_SYM_NS = 1000.0/1500.0
	) (
		input 	wire	i_clk,
		input	wire	i_reset,
		input	wire	i_rx_p, i_rx_n,
		input	wire	i_cominit_det, i_comwake_det,
		output	reg		o_comwake, o_comreset
	);

	// Local declarations
	// {{{
	// localparam realtime	SAMPLE_RATE_NS = CLOCK_SYM_NS / OVERSAMPLE;
	// localparam	TUI = OVERSAMPLE * 10 * SAMPLE_RATE_NS;
	// localparam	T1 = 160 * TUI;
	// localparam	T2 = 480 * TUI;
	localparam	RESET_BURSTS = 6;	// Min # of COMRESET bursts
	localparam	WAKE_BURSTS = 6;	// Min # of COMWAKE bursts
	// Below values are for GAP Detection
	localparam	COM_MIN = $rtoi(104 / CLOCK_SYM_NS),
				COM_MAX = $rtoi(109 / CLOCK_SYM_NS);
	localparam	RESETIDLE_MIN = $rtoi(311 / CLOCK_SYM_NS),
				RESETIDLE_MAX = $rtoi(329 / CLOCK_SYM_NS);
	localparam	WAKEIDLE_MIN = $rtoi(104 / CLOCK_SYM_NS),
				WAKEIDLE_MAX = $rtoi(109 / CLOCK_SYM_NS);

	localparam	[2:0]	POR_RESET    = 0,
				FSM_COMRESET = 1,
				FSM_HOSTINIT = 2,
				FSM_DEVWAKE  = 3,
				FSM_HOSTWAKE = 4,
				FSM_RELEASE  = 5;

	localparam	MSB = $clog2(RESETIDLE_MAX+1);
	localparam	OOBMSB = 4;
	localparam	ALIGN_COUNT = 4;

	localparam [9:0] // D24_3 = { 6'b110011, 4'b0011 },
			K28_5 = { 6'b001111, 4'b1010 }, // Inverts disparity
			D10_2 = { 6'b010101, 4'b0101 },	// Neutral
			D27_3 = { 6'b001001, 4'b1100 }; // Inverts disparity
	localparam [39:0] ALIGN_P = { K28_5, D10_2, D10_2, D27_3 };

	reg		valid_symbol;
	reg	[MSB:0]	idle_timeout, com_timeout;
	reg		w_comwake, w_comreset;
	reg	[OOBMSB:0]	oob_count;
	reg	[39:0]	sreg;
	// reg	[$clog2(OVERSAMPLE)-1:0]	p;
	reg		align_p;
	reg	[2:0]	reset_state;
	reg	[2:0]	align_cnt;
	// }}}

	////////////////////////////////////////////////////////////////////////
	//
	// Detect the out-of-band signals forming COMWAKE and COMRESET
	// {{{
	initial sreg = 0;
	always @(posedge i_clk) begin
		sreg <= { sreg[38:0], (i_rx_p === 1'b1) && (i_rx_n === 1'b0) };
	end

	always @(*)
	begin
		// det_p = (sreg == {(2){  D24_3, ~D24_3 }})	// D24.3
		//	 || (sreg == {(2){ ~D24_3,  D24_3 }});

		align_p = (sreg ==  ALIGN_P) // ALIGN primitive
			   || (sreg == ~ALIGN_P);

		// com_detect = (det_p || align_p);
		valid_symbol = (i_rx_p === 1'b1 && i_rx_n === 1'b0)
					|| (i_rx_p === 1'b0 && i_rx_n === 1'b1);
	end

	initial align_cnt = 0;
	always @(posedge i_clk or posedge i_reset)
	if (i_reset)
		align_cnt <= 0;
	else if (w_comreset || w_comwake)
		align_cnt <= 0;
	else if (align_p && !(&align_cnt))
		align_cnt <= align_cnt + 1;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Measure how long we've been idle/inactive
	// {{{
	initial	idle_timeout = 0;
	always @(posedge i_clk)
	if (!valid_symbol)
		idle_timeout <= idle_timeout + 1;
	else
		idle_timeout <= 0;

	initial	com_timeout = 0;
	always @(posedge i_clk)
	begin
		if (valid_symbol)
			com_timeout <= com_timeout + 1;
		else if (w_comreset || w_comwake)
			com_timeout <= 0;
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Final COMRESET/COMWAKE signal detection
	// {{{
	// Verilator lint_off WIDTH

	// A COMRESET = the comreset sequence, followed by an idle period,
	// followed by a valid symbol of some type.
	// Sometimes we cannot detect all 4 aligns because of sync of tx and 1.5gbps clks.
	// Hence one alignment can be neglated
	always @(*)
		w_comreset = (reset_state == FSM_COMRESET)
			&& (align_cnt >= (ALIGN_COUNT-1))
			&& (com_timeout >= COM_MIN && com_timeout  < COM_MAX)
			&& (idle_timeout >= RESETIDLE_MIN && idle_timeout < RESETIDLE_MAX);

	// A COMWAKE = the same com sequence, followed by an idle period of
	// an appropriate length, followed by a valid symbol of some (any) type.
	// That symbol could be good data, or part of the next valid sequence.
	// Sometimes we cannot detect all 4 aligns because of sync of tx and 1.5gbps clks.
	// Hence one alignment can be neglated
	always @(*)
		w_comwake = (reset_state == FSM_DEVWAKE)
			&& (align_cnt >= (ALIGN_COUNT-1))
			&& (com_timeout  >= COM_MIN && com_timeout  < COM_MAX)
			&& (idle_timeout >= WAKEIDLE_MIN && idle_timeout < WAKEIDLE_MAX);

	// Verilator lint_on  WIDTH
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// COMRESET / COMWAKE : State machine
	// {{{
	always @(posedge i_clk or posedge i_reset)
	if (i_reset)
	begin
		reset_state <= POR_RESET;
		oob_count  <= 0;
		o_comreset <= 0;
		o_comwake  <= 0;
	end else if (w_comreset || w_comwake)
	begin
		if (!oob_count[OOBMSB])
			oob_count <= oob_count + 1;
	end else case(reset_state)
	POR_RESET: begin
			reset_state <= FSM_COMRESET;
			oob_count 	<= 0;
			o_comreset  <= 1'b0;
			o_comwake	<= 1'b0;
		end
	FSM_COMRESET: if (oob_count == RESET_BURSTS)
			begin
				reset_state <= FSM_HOSTINIT;
				oob_count 	<= 0;
				o_comreset  <= 1'b1;
			end
	FSM_HOSTINIT: if (i_cominit_det)
			reset_state <= FSM_DEVWAKE;
	FSM_DEVWAKE: begin
			o_comreset <= 1'b0;
			if (oob_count == WAKE_BURSTS) begin
				reset_state <= FSM_HOSTWAKE;
				oob_count 	<= 0;
				o_comwake   <= 1'b1;
			end
		end
	FSM_HOSTWAKE: if (i_comwake_det)
			reset_state <= FSM_RELEASE;
	FSM_RELEASE: begin
			o_comwake <= 0;
			o_comreset <= 0;
			oob_count  <= 0;
			reset_state <= FSM_RELEASE;
		end
	default: begin
			// Will never get here
			reset_state <= POR_RESET;
			oob_count <= 0;
		end
	endcase
	// }}}
endmodule
