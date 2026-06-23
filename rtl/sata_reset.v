////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./rtl/sata_reset.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Handles the COM* SATA signals, to bring the SATA device out of
//		reset, or handle sudden resets and resynchronizations during
//	operation.
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
`timescale	1ns/1ps
// }}}
module	sata_reset #(
		parameter real	CLOCK_FREQUENCY_HZ = 75e6	// GEN 1
	) (
		// {{{
		input	wire	i_tx_clk,
		// Verilator lint_off UNUSED
		input	wire	i_rx_clk,
		// Verilator lint_on  UNUSED
		// Verilator lint_off SYNCASYNCNET
		input	wire	i_reset_n,	// In TX clock domain
		// Verilator lint_on  SYNCASYNCNET
		input	wire	i_reset_request,
		input	wire	i_phy_ready,
		//
		output	reg		o_tx_elecidle,
		output	reg		o_tx_cominit,
		output	reg		o_tx_comwake,
		input	wire	i_tx_comfinish,
		//
		input	wire	i_rx_elecidle,
		input	wire	i_rx_cominit,
		input	wire	i_rx_comwake,
		output	reg		o_rx_cdrhold,	// Freeze RX clk+data ctrl loop
		//
		input	wire		i_tx_primitive,
		input	wire	[31:0]	i_tx_data,
		output	wire		o_tx_ready,
		//
		output	reg		o_phy_primitive,
		output	reg	[31:0]	o_phy_data,
		//
		input	wire		i_rx_valid,
		input	wire	[32:0]	i_rx_data,
		//
		output	wire	[3:0]	o_oob_status,
		output	reg		o_link_up,
		//
		// o_debug is set to the tx_clk domain
		output	reg	[31:0]	o_debug
		// }}}
	);

	// Local declarations
	// {{{
`include "sata_primitives.vh"

	localparam [3:0]	HR_RESET	= 4'h0,
				HR_ISSUE_COMINIT	= 4'h1,
				HR_AWAIT_RXCOMINIT	= 4'h2,
				HR_AWAIT_ENDOFINIT	= 4'h3,
				HR_CALIBRATE		= 4'h4,
				HR_COMWAKE			= 4'h5,
				HR_AWAIT_RXCOMWAKE	= 4'h6,
				HR_AWAIT_RXCLRWAKE	= 4'h7,
				HR_AWAIT_ALIGN		= 4'h8,
				// HR_SEND_ALIGN	= 4'h9,
				HR_READY		= 4'ha,
				HR_AWAIT_RXCLRINIT	= 4'hb;

	// Watchdog wait time is given in SATA chap 8, OOB and PHY POWER STATES.
	// We need to wait 873.8 us (32768 Gen1 DWORDS) before moving on
	localparam	WATCHDOG_TIMEOUT = $rtoi(873.8e-6 * CLOCK_FREQUENCY_HZ);
	localparam	LGWATCHDOG = $clog2(WATCHDOG_TIMEOUT+1);
	localparam	MIN_ALIGNMENT = $rtoi(116.3e-9 * CLOCK_FREQUENCY_HZ)+4;
	localparam	LGALIGN = $clog2(MIN_ALIGNMENT+1);

	reg		tx_reset;
	reg	[1:0]	tx_pipe_reset;

	wire		rx_elecidle, rx_cominit, rx_comwake;
	reg		last_rx_cominit, last_rx_comwake;
	wire		ck_rx_elecidle, ck_rx_align;
	reg		ck_rx_cominit, ck_rx_comwake,
			ck_phy_ready;

	(* ASYNC_REG="TRUE" *)
	reg		pipe_phy_ready;

	reg	[3:0]	fsm_state, oob_status;
	wire		w_rx_align, rx_align;
	// FIXME--these should be used for ... something
	reg				retry_timeout;
	reg	[LGWATCHDOG-1:0]	watchdog_counter;

	reg	[LGALIGN-1:0]	min_alignment_counter;
	reg			check_alignment;

	reg	[3:0]	pdecode;	// Only used for debug
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Move the RX COM detect signals to the TX clock domain
	// {{{

	always @(posedge i_tx_clk or negedge i_reset_n)
	if (!i_reset_n)
		{ tx_reset, tx_pipe_reset } <= -1;
	else
		{ tx_reset, tx_pipe_reset } <= { tx_pipe_reset, 1'b0 };

	// To extend ... on pulse detection, set counter = 5
	//	count counter down to zero, then release pulse when source is
	//	clear.
	sata_pextend
	u_extend_elecidle (
		.i_clk(i_tx_clk), .i_reset(tx_reset),
		.i_sig(i_rx_elecidle),
		.o_sig(rx_elecidle)
	);

	sata_pextend
	u_extend_cominit (
		.i_clk(i_tx_clk), .i_reset(tx_reset),
		.i_sig(i_rx_cominit),
		.o_sig(rx_cominit)
	);

	sata_pextend
	u_extend_comwake (
		.i_clk(i_tx_clk), .i_reset(tx_reset),
		.i_sig(i_rx_comwake),
		.o_sig(rx_comwake)
	);

	assign	w_rx_align = i_rx_valid && i_rx_data[31:0] == P_ALIGN[31:0];

	sata_pextend
	u_extend_rxalign (
		.i_clk(i_tx_clk), .i_reset(tx_reset),
		.i_sig(w_rx_align),
		.o_sig(rx_align)
	);

	/*
	// {{{
	// Verilator lint_off UNUSED
	wire		w_rx_sync, rx_sync;
	// Verilator lint_on  UNUSED

	assign	w_rx_sync = i_rx_valid && i_rx_data == P_SYNC;

	sata_pextend
	u_extend_rxsync (
		.i_clk(i_tx_clk), .i_reset(tx_reset),
		.i_sig(w_rx_sync),
		.o_sig(rx_sync)
	);
	// }}}
	*/

	assign	ck_rx_elecidle = rx_elecidle;

	always @(posedge i_tx_clk or negedge i_reset_n)
	if (!i_reset_n)
	begin
		{ ck_rx_cominit, last_rx_cominit } <= 0;
		{ ck_rx_comwake, last_rx_comwake } <= 0;
		{ ck_phy_ready,  pipe_phy_ready } <= 0;
	end else begin
		last_rx_cominit <= rx_cominit;
		ck_rx_cominit   <= rx_cominit && !last_rx_cominit;

		last_rx_comwake <= rx_comwake;
		ck_rx_comwake   <= rx_comwake && !last_rx_comwake;

		{ ck_phy_ready, pipe_phy_ready }
					<= { pipe_phy_ready, i_phy_ready };
	end

	assign	ck_rx_align = rx_align;
	// }}}

	// COMINIT/COMRESET/COMWAKE signals last between 103.5 and 109.9ns
	// COMINIT/COMRESET signals have a gap of 320 ns between them
	// COMWAKE signals have a gap of 103.5-109.9 ns between them

	initial	o_tx_cominit  = 1'b0;
	initial	o_tx_comwake  = 1'b0;
	initial	o_tx_elecidle = 1'b1;
	initial	o_link_up     = 1'b0;

	always @(posedge i_tx_clk)
	if (!i_reset_n)
	begin
		fsm_state <= HR_RESET;

		o_tx_cominit   <= 1'b0;
		o_tx_comwake   <= 1'b0;
		o_tx_elecidle  <= 1'b1;
		o_rx_cdrhold   <= 1'b1;

		o_link_up      <= 1'b0;

		{ o_phy_primitive, o_phy_data } <= P_ALIGN;
	end else begin
		o_tx_cominit   <= 1'b0;
		o_tx_comwake   <= 1'b0;
		o_tx_elecidle  <= 1'b1;
		o_rx_cdrhold   <= 1'b1;

		o_link_up      <= 1'b0;
		{ o_phy_primitive, o_phy_data } <= P_ALIGN;

		case(fsm_state)
		HR_RESET:	begin
			o_tx_elecidle <= 1'b1;
			o_rx_cdrhold  <= 1'b1;
			// Wait for the PHY to come out of any reset before
			// continuing
			if (ck_phy_ready)
			begin
				fsm_state <= HR_ISSUE_COMINIT;
				o_tx_cominit  <= 1'b1;
				// o_tx_elecidle <= 1'b0;
			end end
		HR_ISSUE_COMINIT: begin
			// {{{
			// Issue COMRESET, and wait for the PHY (not the device
			// yet) to acknowledge it before continuing.
			o_tx_cominit  <= 1'b0;
			o_tx_elecidle <= 1'b1;
			o_rx_cdrhold  <= 1'b1;

			if (i_tx_comfinish == 1'b1)
				fsm_state <= HR_AWAIT_RXCOMINIT;
		end
			// }}}
		HR_AWAIT_RXCOMINIT: begin
			// {{{
			// Once we're done with the COMRESET, wait for the
			// device to respond with a COMINIT.
			o_tx_elecidle <= 1'b1;
			o_rx_cdrhold  <= 1'b1;
			if (ck_rx_cominit)
				fsm_state <= HR_AWAIT_ENDOFINIT;
			else if (retry_timeout)
				// If the device doesn't respond, start over
				// and try again by sending an additional
				// COMRESET
				fsm_state <= HR_RESET;
			end
			// }}}
		HR_AWAIT_ENDOFINIT: begin	// Also HR_AWAIT_NOCOMINIT
			// {{{
			// Wait for the device to release COMINIT.
			o_tx_elecidle <= 1'b1;
			o_rx_cdrhold  <= 1'b1;
			if (!ck_rx_cominit)
				fsm_state <= HR_CALIBRATE;
			end
			// }}}
		HR_CALIBRATE: begin
			// {{{
			// This is the point in the SATA protocol where we're
			// supposed to "calibrate" the channel.  I don't think
			// GTX supports any type of calibration, so we'll just
			// move on.
			o_tx_elecidle <= 1'b1;
			o_rx_cdrhold  <= 1'b1;
			fsm_state <= HR_COMWAKE;
			o_tx_comwake  <= 1'b1;
			end
			// }}}
		HR_COMWAKE: begin
			// {{{
			// Now, issue a COMWAKE signal and wait for the PHY
			// to acknowledge we've sent it.
			o_tx_elecidle <= 1'b1;
			o_rx_cdrhold  <= 1'b1;
			if (i_tx_comfinish)
				fsm_state <= HR_AWAIT_RXCOMWAKE;
			end
			// }}}
		HR_AWAIT_RXCOMWAKE: begin	// Also HR_AWAIT_COMWAKE
			// {{{
			// We can now clear COMWAKE, and wait for the device
			// to reply with its own COMWAKE.  If it doesn't reply
			// in a timely fashion, we need to timeout and start
			// over.
			o_tx_elecidle <= 1'b1;
			o_rx_cdrhold  <= 1'b1;
			// if (ck_rx_cominit)	// Unsolicited COMINIT
			//	fsm_state <= HR_AWAIT_RXCLRINIT;
			// else
			if (ck_rx_comwake)
				fsm_state <= HR_AWAIT_RXCLRWAKE;
			else if (retry_timeout)
				fsm_state <= HR_RESET;
			end
			// }}}
		HR_AWAIT_RXCLRWAKE: begin	// Also HR_AWAIT_NOCOMWAKE
			if (!ck_rx_comwake)
				fsm_state <= HR_AWAIT_ALIGN;
			end
		HR_AWAIT_ALIGN: begin
			// {{{
			// The last step in the handshake is to lock to an
			// align primitive.  We'll wait here until we lock,
			// before moving on.
			o_rx_cdrhold  <= 1'b0;
			{ o_phy_primitive, o_phy_data } <= D10_2;
			if (!ck_rx_elecidle)
				o_tx_elecidle <= 1'b0;
			if (ck_rx_align && !ck_rx_elecidle && check_alignment)
				fsm_state <= HR_READY;
			if (retry_timeout)	// 870us allowed
				fsm_state <= HR_RESET;
			if (i_reset_request)
				fsm_state <= HR_RESET;
			if (ck_rx_cominit)
				fsm_state <= HR_AWAIT_RXCLRINIT;
			end
			// }}}
		HR_READY: begin
			// {{{
			o_link_up <= 1'b1;
			o_tx_elecidle <= 1'b0;
			o_rx_cdrhold   <= 1'b0;
			{ o_phy_primitive, o_phy_data }
					<= { o_phy_primitive, o_phy_data };
			if (o_tx_ready)
				{ o_phy_primitive, o_phy_data }
					<= { i_tx_primitive, i_tx_data };
			if (ck_rx_cominit)
				fsm_state <= HR_AWAIT_RXCLRINIT;
			if (i_reset_request || ck_rx_elecidle)
				fsm_state <= HR_RESET;
			end
			// }}}
		HR_AWAIT_RXCLRINIT: begin
			// {{{
			// If we receive an unsolicited COMINIT while in
			// operation, wait for it to clear before issuing a
			// COMRESET.
			o_link_up <= 1'b0;
			o_tx_elecidle <= 1'b1;
			o_rx_cdrhold   <= 1'b0;
			if (!ck_rx_cominit)
				fsm_state <= HR_RESET;
			end
			// }}}
		default: fsm_state <= HR_RESET;
		endcase
	end

	assign	o_tx_ready = o_link_up;


	// oob_status[4] = RX READY = LINK-UP
	// oob_status[3] = RX COMWAKE RECEIVED
	// oob_status[2] = TX COMWAKE SENT
	// oob_status[1] = RX COMINIT RECEIVED
	// oob_status[0] = TX COMRESET SENT
	always @(*)
	case(fsm_state)
	HR_RESET:		oob_status = 4'h0;
	HR_ISSUE_COMINIT:	oob_status = 4'h0;
	HR_AWAIT_RXCOMINIT:	oob_status = 4'h1;
	HR_AWAIT_ENDOFINIT:	oob_status = 4'h3;
	HR_CALIBRATE:		oob_status = 4'h3;
	HR_COMWAKE:		oob_status = 4'h3;
	HR_AWAIT_RXCOMWAKE:	oob_status = 4'h7;
	HR_AWAIT_RXCLRWAKE:	oob_status = 4'hf;
	HR_AWAIT_ALIGN:		oob_status = 4'hf;
	HR_READY:		oob_status = 4'hf;
	HR_AWAIT_RXCLRINIT:	oob_status = 4'h4;
	default:		oob_status = 4'h0;
	endcase

	assign	o_oob_status = oob_status;

	////////////////////////////////////////////////////////////////////////
	//
	// Watchdog/retry timeout
	// {{{

	// Reset the watchdog if/when:
	//	1. Reset
	//	2. The PHY isn't ready
	//	3. We are issuing our own COMRESET command
	//	4. The link is up.
	//
	// Otherwise, if we get stuck in this synchronization FSM, then we
	// want to know it, and hence we want to try to sync again from scratch.
	always @(posedge i_tx_clk)
	if (!i_reset_n || fsm_state == HR_RESET
			|| fsm_state == HR_AWAIT_RXCLRWAKE
			|| o_tx_cominit || o_link_up)
	begin
		watchdog_counter <= WATCHDOG_TIMEOUT[LGWATCHDOG-1:0];
		retry_timeout    <= 0;
	end else begin
		if (watchdog_counter != 0)
			watchdog_counter <= watchdog_counter - 1;
		retry_timeout    <= (watchdog_counter <= 1);
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Alignment crosstalk check
	// {{{
	// It's possible, when looking for alignment words, that you'll receive
	// crosstalk before the device properly fires up the interface.  Hence,
	// the SATA spec says we need to wait at least 116.3ns after detecting
	// the release of COMWAKE to start looking for alignment.
	always @(posedge i_tx_clk)
	if (!i_reset_n)
	begin
		min_alignment_counter <= MIN_ALIGNMENT[LGALIGN-1:0];
		check_alignment <= 1'b0;
	end else if (fsm_state != HR_AWAIT_ALIGN)
	begin
		min_alignment_counter <= MIN_ALIGNMENT[LGALIGN-1:0];
		check_alignment <= 1'b0;
	end else if (!check_alignment)
	begin
		min_alignment_counter <= min_alignment_counter - 1;
		check_alignment <= (min_alignment_counter <= 1);
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Generate a debugging output -- in the TX clock domain
	// {{{
	always @(*)
	begin
		pdecode = 0;
		if (i_tx_data == P_ALIGN[31:0])  pdecode = 1;
		if (i_tx_data == P_CONT[31:0])   pdecode = pdecode | 2;
		if (i_tx_data == P_DMAT[31:0])   pdecode = pdecode | 3;
		if (i_tx_data == P_EOF[31:0])    pdecode = pdecode | 4;
		if (i_tx_data == P_HOLD[31:0])   pdecode = pdecode | 5;
		if (i_tx_data == P_HOLDA[31:0])  pdecode = pdecode | 6;
		if (i_tx_data == P_SOF[31:0])    pdecode = pdecode | 7;
		if (i_tx_data == P_SYNC[31:0])   pdecode = pdecode | 8;
		if (i_tx_data == P_R_IP[31:0])   pdecode = pdecode | 9;
		if (i_tx_data == P_R_OK[31:0])   pdecode = pdecode | 10;
		if (i_tx_data == P_R_RDY[31:0])  pdecode = pdecode | 11;
		if (i_tx_data == P_X_RDY[31:0])  pdecode = pdecode | 12;
		if (i_tx_data == P_R_ERR[31:0])  pdecode = pdecode | 13;
		if (i_tx_data == P_WTRM[31:0])   pdecode = pdecode | 14;

		if (!i_tx_primitive || o_tx_elecidle)
			pdecode = 4'hf;
	end

	always @(posedge i_tx_clk)
	begin
		o_debug <= 0; // Default everything to zero

		// Any change in link up is a reason to trigger the scope
		o_debug[31] <= (o_tx_ready != o_debug[16]);

		o_debug[23] <= o_phy_primitive;
		o_debug[22] <= o_link_up;
		o_debug[21:18] <= pdecode;
		o_debug[17] <= i_tx_primitive && !o_tx_elecidle;
		o_debug[16] <= o_tx_ready;
		o_debug[15] <= o_tx_elecidle;
		o_debug[14] <= o_tx_cominit;
		o_debug[13] <= o_tx_comwake;
		o_debug[12] <= i_tx_comfinish;
		o_debug[11] <= ck_rx_elecidle;
		o_debug[10] <= ck_rx_cominit;
		o_debug[9] <= ck_rx_comwake;
		o_debug[8] <= ck_phy_ready;
		o_debug[7] <= ck_rx_align;
		o_debug[6] <= retry_timeout;
		o_debug[5] <= (watchdog_counter < WATCHDOG_TIMEOUT[LGWATCHDOG-1:0]);
		o_debug[4] <= check_alignment;
		// check_alignment
		o_debug[3:0] <= fsm_state;
	end
	// }}}

	// Keep Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, i_rx_data[32] };
	// Verilator lint_on  UNUSED
	// }}}
endmodule
