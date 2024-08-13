////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/satalnk_fsm.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	SATA State machine, all running on the TX clock
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2022-2024, Gisselquist Technology, LLC
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
module	satalnk_fsm (
		// {{{
		input	wire		i_clk, i_reset,
		// Transport interface: Two abortable AXI streams
		// {{{
		input	wire		s_valid,
		output	wire		s_ready,
		input	wire	[32:0]	s_data,
		input	wire		s_last,
		//
		input	wire		s_abort,	// TX aborts
		output	reg		s_success,	// Link successfuly sent
		output	reg		s_failed,	// Link failed to send
		//
		// input wire		m_valid,
		// input wire		m_ready,
		input	wire		m_full,	// Will take some time to act
		input	wire		m_empty,
		input	wire		m_last,
		input	wire		m_abort,
		//
		output	reg		o_error,	// On an error condition
		output	reg		o_ready, // Err clrd, Syncd, & rdy to go
		// }}}
		// (PHY) RX interface
		// {{{
		// Comes directly from an Async FIFO
		input	wire		i_rx_valid,
		// output wire		o_rx_ready,	// *MUST* be true
		input	wire	[32:0]	i_rx_data,
		// }}}
		// PHY (TX) interface
		// {{{
		output	wire		m_phy_valid,	// *MUST* be true
		input	wire		m_phy_ready,
		output	reg	[32:0]	m_phy_data,
		// }}}
		output	reg		o_phy_reset,
		input	wire		i_phy_ready
		// }}}
	);

`include "sata_primitives.vh"

	// Local declarations
	// {{{
	// Local state declarations
	// {{{
	localparam [4:0]	L_IDLE         = 5'd00,
			L_SYNCESCAPE   = 5'd01,
			L_NOCOMMERR    = 5'd02,
			L_NOCOMM       = 5'd03,
			L_SENDALIGN    = 5'd04,
			L_RESET        = 5'd05,
			L_SENDCHKRDY = 5'd06, // HL_SENDCHKRDY, since this is host
			L_SENDDATA     = 5'd07,
			L_RCVRHOLD     = 5'd08,
			L_WAIT         = 5'd09,
			L_RCVCHKRDY    = 5'd10,
			L_RCVWAITFIFO  = 5'd11,
			L_RCVDATA      = 5'd12,
			L_HOLD         = 5'd13,
			L_RCVHOLD      = 5'd14,
			L_RCVEOF       = 5'd15,
			L_GOODEND      = 5'd16,
			L_BADEND       = 5'd17,
			L_PMDENY       = 5'd18;
			// L_SEND_SOF     = 5'd07,
			// L_SENDHOLD     = 5'd10,	//Hndld in satatx_framer
			// L_SENDCRC      = 5'd11,
			// L_SENDEOF      = 5'd12,
			// L_GOODCRC,
			// L_TPMPARTIAL = 22,
			// L_TPMSLUMBER = 23,
			// L_PMOFF = 24,
			// L_CHKPHYRDY,
			// L_NOCOMMPOWER,
			// L_WAKEUP1,
			// L_WAKEUP2,
			// L_NOPMNAK;
	// }}}

	reg	r_ready;
	// }}}

	// Continue primitives will have been removed on entry

	// Link state machine
	wire		i_rx_primitive;
	reg	[4:0]	link_state;

	assign	i_rx_primitive = i_rx_data[32];

	initial	r_ready = 1'b0;
	initial	o_ready = 1'b0;
	initial	o_error = 1'b0;
	always @(posedge i_clk)
	begin
		o_error     <= 1'b0;
		o_phy_reset <= 1'b0;
		s_failed    <= 1'b0;
		s_success   <= 1'b0;
		r_ready     <= 1'b0;

		case(link_state)
		// Idle states
		// {{{
		L_RESET: begin
			// {{{
			link_state  <= L_NOCOMM;
			o_phy_reset <= 1'b0;
			m_phy_data  <= P_ALIGN;
			o_ready     <= 0;
			end
			// }}}
		L_NOCOMMERR: begin
			// {{{
			link_state <= L_NOCOMM;
			m_phy_data <= P_ALIGN;
			o_ready     <= 0;
			end
			// }}}
		L_NOCOMM: begin
			// {{{
			if (i_phy_ready)
				link_state <= L_SENDALIGN;
			m_phy_data <= P_ALIGN;
			o_ready     <= 0;
			end
			// }}}
		L_SENDALIGN: begin
			// {{{
			if (m_phy_ready)
				link_state <= L_IDLE;
			m_phy_data <= P_ALIGN;
			o_ready     <= 0;
			end
			// }}}
		L_IDLE: begin
			// {{{
			if (i_rx_valid&& i_rx_data == P_X_RDY	
					|| i_rx_data == P_SYNC)
				o_ready <= 1'b1;

			if (m_phy_ready)
			begin
				m_phy_data <= P_SYNC;
				if (i_rx_valid&& i_rx_data == P_X_RDY)
					link_state <= L_RCVWAITFIFO;
				else if (i_rx_valid && (i_rx_data == P_PMREQ_S
						|| i_rx_data == P_PMREQ_P))
					link_state <= L_PMDENY;
				else if (s_valid)
					link_state <= L_SENDCHKRDY;
			end end
			// }}}
		L_SYNCESCAPE: if (m_phy_ready) begin
			// {{{
			m_phy_data <= P_SYNC;
			if (i_rx_valid && (i_rx_data == P_X_RDY
					|| i_rx_data == P_SYNC))
				link_state <= L_IDLE;
			end
			// }}}
		// }}}
		// Transmit states
		// {{{
		L_SENDCHKRDY: begin
			// {{{
			m_phy_data <= P_X_RDY;
			if (i_rx_valid && i_rx_data[32] && m_phy_ready)
			begin
				if (i_rx_data == P_R_RDY)
				begin
					link_state <= L_SENDDATA;
					r_ready <= 1'b1;
				end else if (i_rx_data == P_X_RDY)
					link_state <= L_RCVWAITFIFO;
			end end
			// }}}
		L_SENDDATA: begin
			// {{{
			r_ready <= 1'b1;
			if (m_phy_ready)
			begin
				m_phy_data <= s_data;
				if (i_rx_valid && i_rx_data == P_SYNC)
				begin
					link_state <= L_IDLE;
					s_failed <= 1'b1;
					r_ready  <= 1'b0;
				end else if (s_last)
				begin
					// {{{
					link_state <= L_WAIT;
					m_phy_data <= P_HOLD;
					r_ready  <= 1'b0;
					// }}}
				end else if (i_rx_valid && i_rx_primitive)
				begin
					if (i_rx_data == P_HOLD)
					begin
						link_state <= L_RCVRHOLD;
						r_ready  <= 1'b0;
					end
					// else if (i_rx_data == P_DMAT)
					//	link_state <= L_SENDCRC;
				end
			end

			if (s_abort)
			begin
				// Priority transition
				m_phy_data <= P_SYNC;
				s_failed <= 1'b0;
				link_state <= L_SYNCESCAPE;
				r_ready  <= 1'b0;
			end end
			// }}}
		L_RCVRHOLD: begin
			// {{{
			m_phy_data <= P_HOLDA;

			if (i_rx_valid && i_rx_primitive && m_phy_ready)
			begin
				if (i_rx_data[31:0] == P_SYNC[31:0])
				begin
					link_state <= L_IDLE;
					s_failed <= 1;
				end
				// else if (i_rx_data[31:0] == P_DMAT[31:0])
				//	link_state <= L_SENDCRC;
				else if (i_rx_data[31:0] == P_HOLD[31:0])
					link_state <= L_RCVRHOLD;
				else begin
					link_state <= L_SENDDATA;
					r_ready  <= 1'b1;
				end
			end

			if (s_abort)
				// Priority over all other transitions
				link_state <= L_SYNCESCAPE;
			end
			// }}}
		/* L_SENDHOLD, L_SENDCRC and L_SENDEOF are implemented in
		// satalnk_txpacket
		L_SENDHOLD: begin
			// {{{
			m_phy_data <= P_HOLD;
			if (s_valid)
				link_state <= L_SENDDATA;
			if (i_rx_valid && i_rx_primitive && m_phy_ready)
			begin
				if (i_rx_data[31:0] == P_SYNC[31:0])
				begin
					link_state <= L_IDLE;
					s_failed <= 1;
				end else if (i_rx_data[31:0] == P_HOLD[31:0])
					link_state <= L_RCVRHOLD;
				// else if (i_rx_data[31:0] == P_DMAT[31:0])
				//	link_state <= L_SENDCRC;
			end

			if (s_abort)
				link_state <= L_SYNCESCAPE;
			end
			// }}}
		L_SENDCRC: begin
			// {{{
			m_phy_data <= { 1'b0, crc };
			link_state <= L_SENDEOF;
			if (i_rx_valid && i_rx_primitive && m_phy_ready)
			begin
				if (i_rx_data[31:0] == P_SYNC[31:0])
				begin
					link_state <= L_IDLE;
					s_failed <= 1'b1;
				end
			end end
			// }}}
		L_SENDEOF: begin
			// {{{
			m_phy_data <= P_EOF;
			link_state <= L_WAIT;
			if (i_rx_valid && i_rx_primitive && m_phy_ready)
			begin
				if (i_rx_data[31:0] == P_SYNC[31:0])
				begin
					link_state <= L_IDLE;
					s_failed <= 1'b1;
				end
			end end
			// }}}
		*/
		L_WAIT: begin
			// {{{
			// Wait here for the PHY to acknowledge receipt
			m_phy_data <= P_WTRM;
			link_state <= L_WAIT;
			if (i_rx_valid && i_rx_primitive && m_phy_ready)
			begin
				if (i_rx_data[31:0] == P_SYNC[31:0])
				begin
					link_state <= L_IDLE;
					s_failed <= 1'b1;
				end else if (i_rx_data[31:0] == P_R_OK[31:0])
				begin
					link_state <= L_IDLE;
					s_success <= 1'b1;
				end else if (i_rx_data[31:0] == P_R_ERR[31:0])
				begin
					link_state <= L_IDLE;
					s_failed <= 1'b1;
				end
			end end
			// }}}
		// }}}
		// Receive states
		// {{{
		L_RCVCHKRDY: begin
			// {{{
			m_phy_data <= P_R_RDY;
			if (i_rx_valid && m_phy_ready)
				link_state <= L_IDLE;
			if (i_rx_valid && i_rx_primitive)
			begin
				if (i_rx_data[31:0] == P_SOF[31:0])
				begin
					link_state <= L_RCVDATA;
				end else if (i_rx_data[31:0] == P_X_RDY[31:0])
					link_state <= L_RCVCHKRDY;
			end end
			// }}}
		L_RCVWAITFIFO: begin
			// {{{
			m_phy_data <= P_SYNC;
			if (i_rx_valid && m_phy_ready)
				link_state <= L_IDLE;
			if (i_rx_valid && i_rx_primitive && m_phy_ready)
			begin
				if (i_rx_data[31:0] == P_X_RDY[31:0])
				begin
					if (!m_empty)
						link_state <= L_RCVCHKRDY;
					else
						link_state <= L_RCVWAITFIFO;
				end
			end end
			// }}}
		L_RCVDATA: begin
			// {{{
			m_phy_data <= P_R_IP;
			link_state <= L_RCVDATA;
			if (m_full)
				link_state <= L_HOLD;
			if (i_rx_valid && i_rx_primitive)
			begin
				if (i_rx_data[31:0] == P_HOLDA[31:0])
				begin
					//
				end else if (i_rx_data[31:0] == P_HOLD[31:0])
				begin
					link_state <= L_RCVHOLD;
				end else if (i_rx_data[31:0] == P_EOF[31:0])
				begin
					link_state <= L_RCVEOF;
				end else if (i_rx_data[31:0] == P_WTRM[31:0])
				begin
					link_state <= L_BADEND;
				end else if (i_rx_data[31:0] == P_SYNC[31:0])
				begin
					link_state <= L_IDLE;
				end
			end end
			// }}}
		L_HOLD: begin
			// {{{
			m_phy_data <= P_HOLD;
			link_state <= L_HOLD;
			if (m_empty && m_phy_ready)
				link_state <= L_RCVDATA;
			if (i_rx_valid && i_rx_primitive)
			begin
				if (i_rx_data[31:0] == P_HOLD[31:0])
				begin
					link_state <= L_RCVHOLD;
				end else if (i_rx_data[31:0] == P_EOF[31:0])
				begin
					link_state <= L_RCVEOF;
				end else if (i_rx_data[31:0] == P_SYNC[31:0])
				begin
					link_state <= L_IDLE;
				end
			end end
			// }}}
		L_RCVHOLD: begin
			// {{{
			m_phy_data <= P_HOLDA;
			if (i_rx_valid)
			begin
				if (i_rx_data == P_HOLD)
				begin
					link_state <= L_RCVHOLD;
				end else if (i_rx_data == P_EOF)
				begin
					link_state <= L_RCVEOF;
				end else if (i_rx_data == P_SYNC)
				begin
					link_state <= L_IDLE;
				end else
					link_state <= L_RCVDATA;
			end end
			// }}}
		L_RCVEOF: begin
			// {{{
			m_phy_data <= P_R_IP;
			if (m_last)
				link_state <= L_GOODEND;
			if (m_abort)
				link_state <= L_BADEND;
			end
			// }}}
		// L_GOODCRC:
		//	Since we have no knowledge of transport layer errors
		//	here, we won't wait at L_GOODCRC to know if the
		//	transport layer received something it wanted (or didn't)
		L_GOODEND: begin
			// {{{
			m_phy_data <= P_R_OK;
			if (i_rx_valid && i_rx_primitive)
			begin
				if (i_rx_data[31:0] == P_SYNC[31:0])
					link_state <= L_IDLE;
			end end
			// }}}
		L_BADEND: begin
			// {{{
			m_phy_data <= P_R_ERR;
			if (i_rx_valid && i_rx_primitive)
			begin
				if (i_rx_data[31:0] == P_SYNC[31:0])
					link_state <= L_IDLE;
			end end
			// }}}
		// }}}
		// Power management states
		// {{{
		// We're not implementing power management, so we shouldn't need
		// these states
		// L_TPMPARTIAL:
		// L_TPMSLUMBER:
		L_PMDENY: begin
			m_phy_data <= P_PMNAK;
			if (!i_rx_primitive)
				link_state <= L_IDLE;
			else if (i_rx_data == P_PMREQ_P
					|| i_rx_data == P_PMREQ_S)
				link_state <= L_PMDENY;

			if (!i_rx_valid)
				link_state <= L_PMDENY;
			end
		// L_CHKRDY:
		// L_NOCOMMPOWER:
		// L_WAKEUP1:
		// L_WAKEUP2:
		// L_NOPMNAK:
		// }}}
		default:
			link_state <= L_IDLE;
		endcase

		// Aborts and resets
		// {{{
		if (!i_phy_ready && (link_state != L_RESET
					&& link_state != L_NOCOMMERR
					&& link_state != L_NOCOMM))
		begin
			link_state <= L_NOCOMMERR;
			o_error <= 1'b1;
			o_ready     <= 0;
		end

		if (i_reset)
		begin
			link_state <= L_RESET;
			o_phy_reset <= 1'b1;
			o_ready     <= 0;
		end
		// }}}
	end

	assign	s_ready = r_ready && m_phy_ready;
	assign	m_phy_valid = 1;
endmodule
