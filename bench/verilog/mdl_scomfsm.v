////////////////////////////////////////////////////////////////////////////////
//
// Filename:	mdl_scomfsm.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Implements the SATA COM handshake, from the perspective of
//		the device.
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
`default_nettype	none
`timescale 1ns / 1ps
// }}}
module	mdl_scomfsm #(
		parameter realtime	CLOCK_SYM_NS = 1000.0 / 1500.0
	) (
		// {{{
		input	wire	i_txclk, i_reset,
		output	reg	o_reset,
		input	wire	i_rx_p, i_rx_n,
		input	wire	i_tx,
		output	wire	o_tx_p, o_tx_n
		// }}}
	);

	// Local decalarations
	// {{{
	localparam [9:0]	D24_3 = { 6'b110011, 4'b0011 };
	localparam [39:0] COM_SEQ = { D24_3, ~D24_3, D24_3, ~D24_3 };
	localparam	NUM_COMINIT = 3,
			NUM_COMWAKE = 6;
	localparam	COMINIT_IDLES = $rtoi(320   / CLOCK_SYM_NS),
			COMWAKE_IDLES = $rtoi(106.7 / CLOCK_SYM_NS);
	localparam	IDLE_WIDTH = $clog2(COMINIT_IDLES+1);

	localparam	[2:0]	CLEAR_RESET = 3'h0,
				SEND_INIT = 3'h1,
				WAIT_WAKE = 3'h2,
				SEND_WAKE = 3'h3,
				ACTIVE    = 3'h4;

	reg	[2:0]	fsm_state;
	reg		r_tx;
	reg	[5:0]	seq_count;
	reg	[39:0]	sreg;
	reg	[$clog2(NUM_COMWAKE)-1:0]	burst_count;
	reg	[1:0]	subburst_count;
	reg	[IDLE_WIDTH-1:0] idle_count;
	wire		w_comwake, w_comreset;
	reg	[2:0]	pipe_comreset, pipe_comwake;
	reg		ck_comreset, ck_comwake;
	// }}}

	mdl_srxcomsigs #(
		.OVERSAMPLE(4), .CLOCK_SYM_NS(CLOCK_SYM_NS)
	) u_comdet (
		.i_reset(i_reset),
		.i_rx_p(i_rx_p), .i_rx_n(i_rx_n),
		.o_comwake(w_comwake), .o_comreset(w_comreset)
	);

	always @(posedge i_txclk)
		{ ck_comreset, pipe_comreset } <= { pipe_comreset, w_comreset };

	always @(posedge i_txclk)
		{ ck_comwake, pipe_comwake } <= { pipe_comwake, w_comwake };

	initial begin
		fsm_state = CLEAR_RESET;
		r_tx = 1'b0;
		seq_count = 40;
		sreg = COM_SEQ;
		subburst_count = 0;
		burst_count = 0;
		idle_count = COMINIT_IDLES[IDLE_WIDTH-1:0];
	end

	always @(posedge i_txclk)
	if (i_reset || ck_comreset)
	begin
		fsm_state <= CLEAR_RESET;
		r_tx <= 1'b0;
		sreg <= COM_SEQ;
		subburst_count <= 0;
		burst_count <= 0;
		idle_count <= COMINIT_IDLES[IDLE_WIDTH-1:0];
		o_reset <= 1'b1;
	end else case(fsm_state)
	CLEAR_RESET: begin
		// {{{
		r_tx <= 0;
		r_idle <= 1;
		sreg <= COM_SEQ;
		seq_count <= 0;	// Start in idle
		subburst_count <= 0;
		burst_count <= 0;
		o_reset <= 1'b1;
		// if (!ck_comreset)
			fsm_state <= SEND_INIT;
		end
		// }}}
	SEND_INIT: begin
		// {{{
		o_reset <= 1'b1;
		if (seq_count > 0)
		begin
			seq_count <= seq_count - 1;
			r_tx <= sreg[39];
			r_idle <= 1'b0;
			sreg <= { sreg[38:0], 1'b0 };
			idle_count <= COMINIT_IDLES[IDLE_WIDTH-1:0];

			if (seq_count == 1)
			begin
				subburst_count <= subburst_count + 1;
				sreg <= COM_SEQ;
				if (subburst_count < 3)
					seq_count <= 40;
				else begin
					burst_count <= burst_count + 1;
					if (burst_count >= NUM_COMINIT-1)
						fsm_state <= WAIT_WAKE;
				end
			end
		end else begin
			r_idle <= 1;
			seq_count <= 0;
			sreg <= COM_SEQ;
			r_tx <= 1'b0;
			if (idle_count > 0)
				idle_count <= idle_count - 1;
			else
				seq_count <= 40;
		end end
		// }}}
	WAIT_WAKE: begin
		// {{{
		o_reset <= 1'b1;
		r_tx <= 0;
		r_idle <= 1;
		idle_count <= COMWAKE_IDLES[IDLE_WIDTH-1:0];
		seq_count  <= 0;
		subburst_count <= 0;
		burst_count<= 0;
		if (ck_comwake)
			fsm_state <= SEND_WAKE;
		end
		// }}}
	SEND_WAKE: begin
		// {{{
		o_reset <= 1'b1;

		if (ck_comwake)
		begin
			r_tx <= 0;
			r_idle <= 1'b1;
			idle_count <= COMWAKE_IDLES[IDLE_WIDTH-1:0];
			seq_count  <= 0;
			subburst_count <= 0;
			burst_count<= 0;
		end else if (seq_count > 0)
		begin
			seq_count <= seq_count - 1;
			r_tx <= sreg[39];
			r_idle <= 1'b0;
			sreg <= { sreg[38:0], 1'b0 };
			idle_count <= COMWAKE_IDLES[IDLE_WIDTH-1:0];

			if (seq_count == 1)
			begin
				subburst_count <= subburst_count + 1;
				sreg <= COM_SEQ;
				if (subburst_count < 3)
					seq_count <= 40;
				else begin
					burst_count <= burst_count + 1;
					if (burst_count >= NUM_COMWAKE-1)
					begin
						fsm_state <= ACTIVE;
						o_reset <= 1'b0;
					end
				end
			end
		end else begin
			seq_count <= 0;
			sreg <= COM_SEQ;
			r_tx <= 1'b0;
			r_idle <= 1'b1;
			if (idle_count > 0)
				idle_count <= idle_count - 1;
			else
				seq_count <= 40;
		end end
		// }}}
	ACTIVE: begin
		o_reset <= 1'b1;
		r_tx <= i_tx;
		r_idle <= 1'b0;
		end
	default: begin end
	endcase

	assign	o_tx_p = (r_idle) ? 1'bz :  r_tx;
	assign	o_tx_n = (r_idle) ? 1'bz : !r_tx;
endmodule
