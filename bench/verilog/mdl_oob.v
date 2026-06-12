////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/mdl_oob.v
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
// Copyright (C) 2025-2026, Gisselquist Technology, LLC
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
`timescale 1ns / 1ps
`default_nettype none
// }}}
module mdl_oob (
		// {{{
		input	wire		i_clk,
		input	wire		i_reset,
		//
		input	wire		i_rx,
		input	wire	[39:0]	i_data_word,
		output	reg		o_done,
		output	wire		o_tx_p, o_tx_n
		// }}}
	);

`include "../../rtl/sata_primitives.vh"

	// Local declarations
	// {{{
	// Parts of ALIGNP
	localparam		OVERSAMPLE = 4;
	localparam realtime	CLOCK_PERIOD = 0.667; // 1.5GHz = 667ps = 0.667ns
	localparam realtime	OPENCK_PERIOD = CLOCK_PERIOD / OVERSAMPLE;

	localparam P_BITS = 40;
	localparam [(P_BITS/4)-1:0] D21_4P= 10'b10_1010_1101,
				D21_4N    = 10'b10_1010_0010;
	localparam [(P_BITS/4)-1:0] K28_3P= 10'b00_1111_0011,
				K28_3N    = 10'b11_0000_1100;
	localparam [(P_BITS/4)-1:0] D21_5 = 10'b10_1010_1010;
	localparam [(P_BITS/4)-1:0] K28_5P= 10'b00_1111_1010,
				K28_5N    = 10'b11_0000_0101;
	// We call it D10_2w to avoid a conflict with D10_2, which is defined
	// already in sata_primitives.vh.
	localparam [(P_BITS/4)-1:0] D10_2w = 10'b01_0101_0101;  // (Neutral)
	localparam [(P_BITS/4)-1:0] D27_3P= 10'b11_0110_0011,
				D27_3N    = 10'b00_1001_1100;

	// SYNC_P = 40'b0011_1100_11:10_1010_1101__1010_1010_1010_1010_1010
	//	= 40'h3cead_aaaaa
	localparam [P_BITS-1:0] SYNC_P = { K28_3P, D21_4N, D21_5, D21_5 };
	// ALIGN_P = 40'b0011_1110_10:01_0101_0101__0101_0101_01:00_1001_1100
	//	= 40'h3e_9555_549c
	localparam [P_BITS-1:0] ALIGN_P = { K28_5P, D10_2w, D10_2w, D27_3N };

	// Parameters
	localparam realtime T1_NS = 160.7;
	localparam realtime T2_NS = 320.0;
	localparam T1_CK   = $rtoi(      T1_NS / CLOCK_PERIOD + 0.5);
	localparam T1_MIN  = $rtoi( 35.0 / CLOCK_PERIOD + 0.5);
	localparam T1_MAX  = $rtoi(175.0 / CLOCK_PERIOD + 0.5);
	localparam T2_CK   = $rtoi(      T2_NS / CLOCK_PERIOD + 0.5);
	localparam T2_MIN  = $rtoi(0.9 * T2_NS / CLOCK_PERIOD + 0.5);
	localparam T2_MAX  = $rtoi(1.1 * T2_NS / CLOCK_PERIOD + 0.5);
	localparam T1_OVCK = $rtoi(T1_NS * OVERSAMPLE / CLOCK_PERIOD + 0.5);
	localparam T2_OVCK = $rtoi(T2_NS * OVERSAMPLE / CLOCK_PERIOD + 0.5);
	localparam N_COMRESET_BURST = 6;    // Number of COMRESET Burst
	// localparam N_COMWAKE_BURST = 6;    // Number of COMRESET Burst

	// Test timing ve burst/idle periods
	localparam	COMINIT_BURST_DURATION = T1_CK;  // Burst timing
	localparam	COMINIT_IDLE_DURATION  = T2_CK;  // Idle timing
	localparam	COMWAKE_DURATION = T1_CK;  // Burst-Idle timing

	// State machine
	localparam	[2:0]	SEND_COMINIT = 0,
				WAIT_COMINIT = 1,
				SEND_COMWAKE = 2,
				WAIT_COMWAKE = 3,
				COMWAKE_DET = 4,
				SEND_ALIGN = 5,
				SEND_SYNC = 6;
	integer				ik;
	reg				openck;
	reg	[P_BITS*OVERSAMPLE-1:0]	open_sreg;
	reg	[P_BITS-1:0]		sampld_sreg;
	wire				sync_det, align_det, cominit_det,
					comwake_det,
					t1_idle, t2_idle, elec_idle;
	reg	align_active, past_sync_det, past_align_det;
	reg [$clog2((T1_CK+T2_CK)*N_COMRESET_BURST+1):0]   detected_idle_time,
					last_idle_time;

	reg	[2:0]	fsm_state;

	// Testbench signals
	reg		send_cominit, send_comwake, send_align, send_sync;
	reg [P_BITS-1:0] data_word;
	reg		tx_elec_idle;
	reg	[12:0]	burst_cnt;
	reg [$clog2($rtoi(COMINIT_BURST_DURATION + 0.5)):0]  burst_timeout;
	reg [$clog2($rtoi(COMINIT_IDLE_DURATION + 0.5)):0]   idle_timeout;
	reg	[3:0]	comwake_count, cominit_count, align_count;
	// }}}

	// OpenCK is an open loop clock.  By Nyquist, it must be greater than
	// {{{
	// 2x faster than the actual clock.  Here, we'll allow it to be
	// OVERSAMPLE times faster.
	initial	openck = 1'b0;
	always
		#(OPENCK_PERIOD/2) openck = !openck;
	// }}}

	// open_sreg is a shift register based upon this oversampled open loop
	// {{{
	// clock.  sampld_sreg is the same register, downsampled to one sample
	// per bit.  It's not locked, but we should be guaranteed that at least
	// one of the four bit phases should have valid data in it.
	always @(posedge openck)
		open_sreg <= { open_sreg[P_BITS * OVERSAMPLE-2:0], (i_rx===1'b1) };

	always @(*)
	begin
		for(ik=0; ik<P_BITS; ik=ik+1)
			sampld_sreg[ik] = open_sreg[(ik*OVERSAMPLE)+(OVERSAMPLE-1)];
	end
	// }}}

	assign	sync_det  = (sampld_sreg == SYNC_P);
	assign	align_det = (sampld_sreg == ALIGN_P);
	assign	elec_idle = (i_rx !== 1'b1) && (i_rx !== 1'b0);

	always @(posedge i_clk)
	if (i_reset)
	begin
		detected_idle_time <= 0;
		last_idle_time <= 0;
	end else if (elec_idle)
	begin
		if (!(&detected_idle_time))
			detected_idle_time <= detected_idle_time + 1;
		if (!(&last_idle_time) && last_idle_time <= detected_idle_time)
			last_idle_time <= detected_idle_time + 1;
	end else begin
		if (detected_idle_time > 0)
			last_idle_time <= detected_idle_time;
		detected_idle_time <= 0;
	end

	always @(posedge openck)
		past_sync_det <= sync_det;

	// align_active -- have we seen the start of a burst of P_ALIGNs already
	// {{{
	// Each T1 burst consists of many align primitives.  We only want to
	// notice the first of these many primitives.
	initial	align_active = 0;
	always @(posedge openck)
	if (align_det && !past_align_det)
	begin
		align_active <= 1'b1;
		// Verilator lint_off WIDTH
	end else if (detected_idle_time > T2_CK/4)
		// Verilator lint_on  WIDTH
		align_active <= 0;
	// }}}

	// Verilator lint_off WIDTH
	assign	t1_idle = (last_idle_time > T1_MIN) && (last_idle_time < T1_MAX);
	assign	t2_idle = (last_idle_time > T2_MIN) && (last_idle_time < T2_MAX);
	// Verilator lint_on  WIDTH

	// cominit_count, comwake_count
	// {{{
	always @(posedge openck)
	if (i_reset)
	begin
		cominit_count <= 0;
		comwake_count  <= 0;
	end else if (align_det && !past_align_det && !align_active)
	begin
		if (t2_idle)
		begin
			if (!(&cominit_count))
				cominit_count <= cominit_count + 1;
			comwake_count <= 0;
		end else if (t1_idle)
		begin
			if (!(&comwake_count))
				comwake_count <= comwake_count + 1;
			cominit_count <= 0;
		end else begin
			cominit_count <= 0;
			comwake_count  <= 0;
		end
		// Verilator lint_off WIDTH
	end else if (detected_idle_time > 2 * T2_CK)
		// Verilator lint_on  WIDTH
	begin
		cominit_count <= 0;
		comwake_count  <= 0;
	end
	// }}}

	// align_count
	// {{{
	always @(posedge openck)
		past_align_det <= align_det;

	always @(posedge openck)
	if (i_reset)
		align_count <= 0;
	else if (align_det && !past_align_det)
	begin
		if (!(&align_count))
			align_count <= align_count + 1;
	end else if (elec_idle)
		align_count <= 0;
	// }}}

	// Verilator lint_off WIDTH
	assign	cominit_det = (cominit_count >= 4 && detected_idle_time >= T2_MAX);
	assign	comwake_det = (comwake_count >= 4 && detected_idle_time >= T1_MAX);
	// assign	align_det = (align_count > 4);
	// Verilator lint_on  WIDTH
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Drive 40 bits out the transmitter
	// {{{
	mdl_alignp_transmit
	alignp_inst (
		.i_clk(i_clk),
		.i_reset(i_reset),
		.i_elec_idle(tx_elec_idle),
		.i_data_p(data_word),
		.o_tx_p(o_tx_p),
		.o_tx_n(o_tx_n)
	);
	// }}}

	always @(*)
	if (!o_done)
	begin
		if (send_sync)
			data_word = SYNC_P;
		else
			data_word = ALIGN_P;
	end else
		data_word = i_data_word;

	// OOB Test Sequence for COMRESET, COMINIT and COMWAKE
	initial send_cominit = 1'b0;
	initial send_comwake = 1'b0;
	initial send_align = 1'b0;
	initial send_sync = 1'b0;
	initial	o_done = 1'b0;
	always @(posedge i_clk or posedge i_reset)
	if (i_reset)
	begin
		// {{{
		fsm_state    <= SEND_COMINIT;
		send_cominit <= 1'b0;
		send_comwake <= 1'b0;
		send_align   <= 1'b0;
		send_sync    <= 1'b0;
		o_done       <= 1'b0;
		// }}}
	end else case(fsm_state)
	SEND_COMINIT: begin
			// {{{
			send_cominit <= 1'b0;
			send_comwake <= 1'b0;
			send_align   <= 1'b0;
			send_sync    <= 1'b0;
			o_done       <= 1'b0;
			if (cominit_det)
			begin
				$display("Model detects COMRESET");
				$display("Starting COMINIT Sequence");
				fsm_state    <= WAIT_COMINIT;
				send_cominit <= 1'b1;
			end end
			// }}}
	WAIT_COMINIT: begin
			// {{{
			send_cominit <= 1'b1;
			send_comwake <= 1'b0;
			send_align   <= 1'b0;
			send_sync    <= 1'b0;
			o_done       <= 1'b0;
			if (burst_cnt >= N_COMRESET_BURST && send_cominit)
			begin
				fsm_state    <= SEND_COMWAKE;
				send_cominit <= 1'b0;
			end end
			// }}}
	SEND_COMWAKE: begin
			// {{{
			send_cominit <= 1'b0;
			send_comwake <= 1'b0;
			send_align   <= 1'b0;
			send_sync    <= 1'b0;
			o_done       <= 1'b0;
			if (comwake_det)
			begin
				$display("Starting COMWAKE Sequence");
				fsm_state    <= WAIT_COMWAKE;
				send_comwake <= 1'b1;
			end end
			// }}}
	WAIT_COMWAKE: begin
			// {{{
			send_cominit <= 1'b0;
			send_comwake <= 1'b1;
			send_align   <= 1'b0;
			send_sync    <= 1'b0;
			o_done       <= 1'b0;
			if (burst_cnt == N_COMRESET_BURST && send_comwake)
			begin
				fsm_state    <= SEND_ALIGN;
				send_comwake <= 1'b0;
				send_align   <= 1'b1;
			end end
			// }}}
	COMWAKE_DET: begin
			// {{{
			send_cominit <= 1'b0;
			send_comwake <= 1'b0;
			send_align   <= 1'b0;
			send_sync    <= 1'b0;
			o_done       <= 1'b0;
			if (align_count > 4 && detected_idle_time == 0)
			begin
				fsm_state <= SEND_ALIGN;
				send_align <= 1'b1;
				o_done <= 1'b1;
			end end
			// }}}
	SEND_ALIGN: begin
			// {{{
			send_cominit <= 1'b0;
			send_comwake <= 1'b0;
			send_align   <= 1'b1;
			send_sync    <= 1'b0;
			o_done       <= 1'b1;
			// if (burst_cnt == 2048) begin    // magic number (2048)
			if (o_done) begin
				send_align <= 1'b0;
				fsm_state  <= SEND_SYNC;
				send_sync <= 1'b1;
				$display("Starting SYNC Sequence");
			end end
			// }}}
	SEND_SYNC: begin
			// {{{
			send_cominit <= 1'b0;
			send_comwake <= 1'b0;
			send_align   <= 1'b0;
			send_sync    <= 1'b1;
			o_done       <= 1'b1;
			end
			// }}}
	default: begin // Will never happen, so ... just reset everything
		// {{{
			fsm_state    <= SEND_COMINIT;
			send_cominit <= 1'b0;
			send_comwake <= 1'b0;
			send_align   <= 1'b0;
			send_sync    <= 1'b0;
			o_done       <= 1'b0;
		end
		// }}}
	endcase

	// Control burst and idle timeouts
	// {{{
	// Verilator lint_off WIDTH
	initial burst_timeout = 0;
	initial idle_timeout = 0;
	always @(posedge i_clk or posedge i_reset)
	if (i_reset)
	begin
		burst_timeout <= 0;
		idle_timeout <= 0;
	end else if (send_cominit)
	begin
		if (!tx_elec_idle)
		begin
			// Send a burst until burst_timeout
			burst_timeout <= burst_timeout + 1;
			if (burst_timeout >= COMINIT_BURST_DURATION-1)
				idle_timeout <= idle_timeout + 1;
			else
				// Then switch to idle
				idle_timeout <= 0;
		end else begin
			// Hold our idle for the idle duration
			burst_timeout <= 0;
			if (idle_timeout == COMINIT_IDLE_DURATION-1)
				idle_timeout <= 0;
			else
				idle_timeout <= idle_timeout + 1;
		end
	end else if (send_comwake)
	begin
		if (!tx_elec_idle) begin
			burst_timeout <= burst_timeout + 1;
			if (burst_timeout == COMWAKE_DURATION-1)
				idle_timeout <= idle_timeout + 1;
			else
				idle_timeout <= 0;
		end else begin
			burst_timeout <= 0;
			if (idle_timeout == COMWAKE_DURATION-1)
				idle_timeout <= 0;
			else
				idle_timeout <= idle_timeout + 1;
		end
	end else if (send_align)
	begin
		if (!tx_elec_idle)
		begin
			if (burst_timeout == (P_BITS-1))
				burst_timeout <= 0;
			else
				burst_timeout <= burst_timeout + 1;
			idle_timeout <= 0;
		end
	end else if (send_sync)
	begin
		if (!tx_elec_idle)
		begin
			if (burst_timeout >= (P_BITS-1))
				burst_timeout <= 0;
			else if (burst_timeout > 0)
				burst_timeout <= burst_timeout + 1;
			idle_timeout  <= 0;
		end
	end else begin
		burst_timeout <= 0;
		idle_timeout  <= 0;
	end
	// Verilator lint_on  WIDTH
	// }}}

	// Control the electrical idle signal
	// {{{
	// Verilator lint_off WIDTH
	initial tx_elec_idle = 1;
	initial burst_cnt = 0;
	always @(posedge i_clk or posedge i_reset)
	if (i_reset)
	begin
		tx_elec_idle  <= 1'b1;
		burst_cnt <= 0;
	end else if (send_cominit || send_comwake)
	begin
		if (burst_timeout == (T1_CK-1))
		begin
			// Wait for the end of the burst ...
			tx_elec_idle  <= 1'b1;

			// We've just completed a burst.  Increment our burst
			// count.
			burst_cnt <= burst_cnt + 1;
		end else if (idle_timeout == 0)
		begin
			tx_elec_idle <= 1'b0;
		end
	// after this stage tx_elec_idle should be always '0'
	end else if (send_align)
	begin
		tx_elec_idle <= 1'b0;
		if (burst_timeout == 0)
			burst_cnt <= burst_cnt + 1;
	end else if (send_sync)
	begin
		tx_elec_idle <= 1'b0;
		burst_cnt <= 0;
	end else begin
		tx_elec_idle <= 1'b1;
		burst_cnt <= 0;
	end
	// Verilator lint_on  WIDTH
	// }}}
endmodule
