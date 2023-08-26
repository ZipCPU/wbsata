////////////////////////////////////////////////////////////////////////////////
//
// Filename:	satatb_comdet.v
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
`default_nettype none
`timescale 1ns/1ps
// }}}
module satatb_comdet #(
		parameter	OVERSAMPLE = 4,
		// The SATA SYMBOL duration is one over the symbol rate, either
		// 1.5GHz, 3.0GHz, or 6GHz, here expressed in ns.
		parameter	realtime	CLOCK_SYM_NS = 1000.0/1500.0
	) (
		input	wire	i_reset,
		input	wire	i_rx_p, i_rx_n,
		output	reg	o_comwake, o_comreset
	);

	// Local declarations
	// {{{
	localparam realtime	SAMPLE_RATE_NS = CLOCK_SYM_NS / OVERSAMPLE;
	// localparam	TUI = OVERSAMPLE * 10 * SAMPLE_RATE_NS;
	// localparam	T1 = 160 * TUI;
	// localparam	T2 = 480 * TUI;
	localparam	RESET_BURSTS = 6;	// Min # of COMRESET bursts
	localparam	COMWAKE_MIN = $rtoi(35 / SAMPLE_RATE_NS), //  35ns in ticks
			COMWAKE_MAX = $rtoi(175 / SAMPLE_RATE_NS); // 175ns in ticks
	localparam	COMRESET_MIN = $rtoi(175 / SAMPLE_RATE_NS), // 175ns in ticks
			COMRESET_MAX = $rtoi(525 / SAMPLE_RATE_NS); // 525ns in ticks

	localparam	[2:0]	POR_RESET    = 0,
				FSM_COMRESET = 1,
				FSM_DEVINIT  = 2,
				FSM_DEVWAKE  = 3,
				FSM_RELEASE  = 4;

	localparam	MSB = $clog2(COMRESET_MAX+1);
	localparam	OOBMSB = 4;

	localparam [9:0] D24_3 = { 6'b110011, 4'b0011 },
			K28_5 = { 6'b001111, 4'b1010 }, // Inverts disparity
			D10_2 = { 6'b010101, 4'b0101 },	// Neutral
			D27_3 = { 6'b110110, 4'b0011 }; // Inverts disparity
	localparam [39:0] ALIGN_P = { K28_5, D10_2, D10_2, D27_3 };

	integer		ip;

	reg		sclk;
	reg		valid_symbol, idle, last_rx;
	reg	[MSB:0]	idle_timeout, com_timeout;
	reg		w_comwake, w_comreset;
	reg	[OOBMSB:0]	oob_count;
	reg	[39:0]	sreg	[0:OVERSAMPLE-1];
	reg	[$clog2(OVERSAMPLE)-1:0]	p;
	reg		det_p, align_p;
	reg		com_detect;
	reg	[2:0]	reset_state;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Generate a sample clock
	// {{{
	initial	begin
		sclk = 0;
		forever
			#(SAMPLE_RATE_NS/2) sclk = !sclk;
	end

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Detect the out-of-band signals forming COMWAKE and COMRESET
	// {{{
	initial begin
		for(ip=0; ip<OVERSAMPLE; ip=ip+1)
			sreg[ip] = 0;
		p = 0;
	end

	always @(posedge sclk)
	begin
		sreg[p] <= { sreg[p][38:0],
				(i_rx_p === 1'b1) && (i_rx_n === 1'b0) };
		p <= p + 1;
	end

	always @(*)
	begin
		det_p = (sreg[p] == {(2){  D24_3, ~D24_3 }})	// D24.3
			|| (sreg[p] == {(2){ ~D24_3,  D24_3 }});

		align_p = (sreg[p] ==  ALIGN_P) // ALIGN primitive
			|| (sreg[p] == ~ALIGN_P);

		com_detect = (det_p || align_p);
		valid_symbol = (i_rx_p === 1'b1 && i_rx_n === 1'b0)
				||(i_rx_n === 1'b0 && i_rx_n === 1'b1);
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Measure how long we've been idle/inactive
	// {{{
	initial	last_rx = 0;
	always @(posedge sclk)
		last_rx <= (i_rx_p === 1'b1) && (i_rx_n === 1'b0);

	initial	idle_timeout = 0;
	always @(posedge sclk)
	if (valid_symbol && i_rx_p !== last_rx)
		idle_timeout <= 0;
	else if (!idle_timeout[MSB])
		idle_timeout <= idle_timeout + 1;

	always @(*)
		idle = idle_timeout >= 40 * OVERSAMPLE;

	initial	com_timeout = -1;
	always @(posedge sclk)
	begin
		if (com_detect)
			com_timeout <= 0;
		else if (!com_timeout[MSB])
			com_timeout <= com_timeout + 1;
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Final COMRESET/COMWAKE signal detection
	// {{{
	// Verilator lint_off WIDTH

	// A COMRESET = the comreset sequence, followed by an idle period,
	// followed by a valid symbol of some type.
	always @(*)
		w_comreset = (com_timeout >= COMWAKE_MIN) && !com_timeout[MSB]
			&& (idle_timeout >= COMRESET_MIN
						&& idle_timeout < COMRESET_MAX);

	// A COMWAKE = the same com sequence, followed by an idle period of
	// an appropriate length, followed by a valid symbol of some (any) type.
	// That symbol could be good data, or part of the next valid sequence.
	always @(*)
		w_comwake = valid_symbol && i_rx_p != last_rx
			&& (com_timeout  >= COMWAKE_MIN) && !com_timeout[MSB]
			&& (idle_timeout >= COMWAKE_MIN && idle_timeout < COMWAKE_MAX);

	// Verilator lint_on  WIDTH
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// COMRESET / COMWAKE : State machine
	// {{{
	always @(posedge sclk)
	if (i_reset)
	begin
		reset_state <= POR_RESET;
		oob_count  <= 0;
		o_comreset <= 0;
		o_comwake  <= 0;
	end else if (w_comreset)
	begin
		reset_state <= FSM_COMRESET;
		if (!oob_count[OOBMSB])
			oob_count <= oob_count + 1;
		o_comreset <= (oob_count >= RESET_BURSTS);
		o_comwake  <= 0;
	end else case(reset_state)
	POR_RESET: oob_count <= 0;	// Wait for comreset
	FSM_COMRESET: begin
		// Verilator lint_off WIDTH
		if (idle_timeout >= COMRESET_MIN)
		begin
			// Verilator lint_on  WIDTH
			reset_state <= FSM_DEVINIT;
			oob_count   <= 0;
			o_comreset  <= 1'b0;
			o_comwake   <= 0;
		end end
	FSM_DEVINIT: if (w_comwake)
		begin
			if (!oob_count[OOBMSB])
				oob_count <= oob_count + 1;
			if (oob_count >= 3)
			begin
				o_comwake <= 1;
				reset_state <= FSM_DEVWAKE;
			end
		end
	FSM_DEVWAKE: begin
		o_comreset <= 0;
		o_comwake  <= 1;
		if (w_comwake && !oob_count[OOBMSB])
			oob_count <= oob_count + 1;
		// Verilator lint_off WIDTH
		if (valid_symbol && !idle && (idle_timeout < COMWAKE_MIN
				|| idle_timeout >= COMWAKE_MAX))
			// Verilator lint_on  WIDTH
		begin
			reset_state <= FSM_RELEASE;
			o_comwake   <= 0;
		end end
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
