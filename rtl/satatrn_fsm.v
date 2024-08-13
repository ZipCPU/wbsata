////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/satatrn_fsm.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Control the ZipDMA components to enact transfers.
//
// Registers
//	0-3:	Shadow register copy, includes busy bit
//	5:	(My status register)
//	6-7:	External DMA address
//
// TODO:
//	- Proper error handling on i_mm2s_err, i_tran_err, or i_s2mm_err
//	- Can we guarantee that if i_err ever shows up, that the AXI Stream
//	  will also have TLAST set?
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2021-2024, Gisselquist Technology, LLC
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
module	satatrn_fsm #(
		// {{{
		parameter	ADDRESS_WIDTH=32,
		// parameter [0:0]	OPT_LITTLE_ENDIAN = 1'b0,
		parameter	DW=32,
		parameter	LGLENGTH=11,
		parameter [0:0]	OPT_LOWPOWER = 1'b0
		// }}}
	) (
		// {{{
		input	wire			i_clk, i_reset,
		// WB Control interface
		// {{{
		input	wire			i_wb_cyc, i_wb_stb, i_wb_we,
		input	wire	[2:0]		i_wb_addr,
		input	wire	[31:0]		i_wb_data,
		input	wire	[3:0]		i_wb_sel,
		output	wire			o_wb_stall,
		output	reg			o_wb_ack,
		output	reg	[31:0]		o_wb_data,
		// }}}
		output	reg			o_tran_req,
		input	wire			i_tran_busy, i_tran_err,
		output	reg			o_tran_src,
		output	reg	[LGLENGTH:0]	o_tran_len,
		//
		// input	wire			i_link_up,
		// output	reg			o_link_reset,
		//
		// Need to process incoming register FISs here
		// {{{
		input	wire			s_pkt_valid, // implies ready
		input	wire	[31:0]		s_data,
		input	wire			s_last,
		// }}}
		// Need to generate a register FIS with the data we have
		// {{{
		output	reg			m_valid,
		input	wire			m_ready,
		output	reg	[31:0]		m_data,
		output	reg			m_last,
		// }}}
		// S2MM control
		// {{{
		output	reg			o_s2mm_request,
		input	wire			i_s2mm_busy, i_s2mm_err,
		output wire [ADDRESS_WIDTH-1:0]	o_s2mm_addr,
		input	wire			i_s2mm_beat,
		// }}}
		// MM2S control
		// {{{
		output	reg			o_mm2s_request,
		input	wire			i_mm2s_busy, i_mm2s_err,
		output reg [ADDRESS_WIDTH-1:0]	o_mm2s_addr
		//
		// output reg			o_dma_abort
		// }}}
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[0:0]	SRC_REGS = 1'b0,
				SRC_MM2S = 1'b1;
	localparam	[7:0]	FIS_REG_TO_DEV	= 8'h27,
				FIS_REG_TO_HOST	= 8'h34,
				FIS_DMA_ACTIVATE = 8'h39,
				FIS_DMA_SETUP    = 8'h41,
				// FIS_DATA         = 8'h46,
				// FIS_BIST_ACTIVATE= 8'h58,
				FIS_PIO_SETUP    = 8'h5f,
				FIS_SET_DEVBITS  = 8'ha1;
				// FIS_FUTURE1  = 8'ha6;
				// FIS_FUTURE2  = 8'hb8;
				// FIS_FUTURE3  = 8'hbf;
				// FIS_FUTURE4  = 8'hd9;
				// FIS_VENDOR1  = 8'hc7;
				// FIS_VENDOR2  = 8'hd4;
	localparam	[2:0]	CMD_NONDATA	= 0,
				CMD_PIO_READ	= 1,
				CMD_PIO_WRITE	= 2,
				CMD_DMA_READ	= 3,
				CMD_DMA_WRITE	= 4;
	localparam	[3:0]	FSM_IDLE		= 4'h0,
				FSM_COMMAND		= 4'h1,
				FSM_PIO_IN_SETUP	= 4'h2,
				FSM_PIO_RXDATA		= 4'h3,
				FSM_PIO_OUT_SETUP	= 4'h4,
				FSM_PIO_TXDATA		= 4'h5,
				FSM_DMA_IN		= 4'h6,
				FSM_DMA_IN_FINAL	= 4'h7,
				FSM_DMA_OUT_SETUP	= 4'h8,
				FSM_DMA_TXDATA		= 4'h9,
				FSM_WAIT_REG		= 4'ha;
				// FSM_RESET		= 4'h0;

	reg	[2:0]	cmd_type;
	reg		known_cmd;
	reg	[63:0]	wide_address;
	reg	[3:0]	fsm_state;

	reg	[47:0]	r_lba;
	reg	[15:0]	r_features;
	reg	[7:0]	r_command, r_control, r_device, r_icc,
			last_fis;
	reg	[3:0]	r_port;
	reg	[15:0]	r_count;
	reg		r_busy, r_int;
	reg	[ADDRESS_WIDTH-1:0]	r_dma_address;
	reg	[15:0]			dma_length;
	reg		last_rx_fis;

	reg		s_sop, s_active;
	reg	[2:0]	s_posn;

	// Verilator lint_off UNUSED
	wire		SRST, BSY, DRDY, DF, DRQ, ERR;
	// Verilator lint_on  UNUSED

	assign	SRST = r_device[4];	// Or is it 6
	assign	BSY  = r_command[7];
	assign	DRDY = r_command[6];
	assign	DF   = r_command[5];
	assign	DRQ  = r_command[3];
	assign	ERR  = r_command[0];
	// }}}

	// cmd_type, known_cmd
	// {{{
	always @(posedge i_clk)
	begin
		known_cmd <= 1'b0;
		if (!r_busy && i_wb_stb && i_wb_we && !o_wb_stall
			&& i_wb_addr == 0 && i_wb_sel[2])
		begin
			cmd_type  <= CMD_NONDATA;
			known_cmd <= 0;

			case(i_wb_data[23:16])
			8'h00, 8'h0b, 8'h40, 8'h42, 8'h44, 8'h45, 8'h51, 8'h63,
			8'h77, 8'h78, 8'hb0, 8'hb2, 8'hb4,
			8'he0, 8'he1, 8'he2, 8'he3, 8'he5, 8'he6, 8'he7, 8'hea,
			8'hef, 8'hf5: begin // Non-Data
				// {{{
					// NOOP, request sense data
					// Read verify sectors
					// Read verify sectors (EXT)
					// Zero EXT
					// Write uncorrectable EXT
					// Configure stream
					// NCQ data
					// Set date & time,
					// max address configuration
					// SMART, set secto config,
					// sanitize device
					// Standby immediate, idle immediate,
					// standby, idle, check power, sleep
					// Flush cache, flush cache ext
					// Set features, Security freeze lock
				known_cmd <= 1;
				cmd_type  <= CMD_NONDATA;
				end
				// }}}
			8'h20, 8'h24, 8'h2b, 8'h2f,
			8'h5c, 8'hec: begin // PIO Read
				// {{{
					// Read sectors, Read sectors EXT,
					// read stream ext, read log ext,
					// trusted rcv, read buffer,
					// identify device
				known_cmd <= 1;
				cmd_type <= CMD_PIO_READ;
				end
				// }}}
			8'h30, 8'h34, 8'h3b, 8'h3f, 8'h5e, 8'he8,
			8'hf1, 8'hf2, 8'hf4, 8'hf6: begin // PIO Write
				// {{{
					// Write sector(s) (ext),
					// write stream (ext), write log ext,
					// trusted send, write buffer,
					// security set password,
					// security unlock,
					// security erase unit,
					// security disable passwrd
				known_cmd <= 1;
				cmd_type <= CMD_PIO_WRITE; // i.e. PIO OUT
				end
				// }}}
			8'h25, 8'h2a, 8'hc8, 8'he9: begin // DMA read (from device)
				// {{{
					// Read DMA ext, read stream DMA ext,
					// Read DMA, Read buffer DMA
				known_cmd <= 1;
				cmd_type <= CMD_DMA_READ;
				end
				// }}}
			8'h06, 8'h07, 8'h35, 8'h3a, 8'h3d, 8'h57, 8'hca,
			8'heb: begin // DMA write (to device)
				// {{{
					// Data set management,
					// data set mgt DMA,
					// Write DMA ext, write DMA stream Ext,
					// Write DMA FUA EXT, Write DMA,
					// write buffer DMA
				known_cmd <= 1;
				cmd_type <= CMD_DMA_WRITE;
				end
			// }}}
			default: begin
				// 8'h4a?? ZAC management?
				// 8'h5d?? Trusted receive data ? DMA
				// 8'h5f?? Trusted send data ? DMA
				// 8'h92?? Download microcode
				// 8'h93?? Download microcode (DMA)
				// 8'h4f?? ZAC management OUT (?)
				cmd_type <= CMD_NONDATA;
				known_cmd <= 0;
				end
			endcase

			if (i_wb_data[7:0] != FIS_REG_TO_DEV)
				known_cmd <= 0;
		end
	end
	// }}}

	// wide_address
	// {{{
	always @(*)
	begin
		wide_address = 0;
		wide_address[ADDRESS_WIDTH-1:0] = r_dma_address;

		if (i_wb_addr == 6 && i_wb_sel[0] && i_wb_we)
			wide_address[ 7: 0] = i_wb_data[ 7: 0];
		if (i_wb_addr == 6 && i_wb_sel[1] && i_wb_we)
			wide_address[15: 8] = i_wb_data[15: 8];
		if (i_wb_addr == 6 && i_wb_sel[2] && i_wb_we)
			wide_address[23:16] = i_wb_data[23:16];
		if (i_wb_addr == 6 && i_wb_sel[3] && i_wb_we)
			wide_address[31:24] = i_wb_data[31:24];

		if (i_wb_addr == 7 && i_wb_sel[0] && i_wb_we)
			wide_address[39:32] = i_wb_data[ 7: 0];
		if (i_wb_addr == 7 && i_wb_sel[1] && i_wb_we)
			wide_address[47:40] = i_wb_data[15: 8];
		if (i_wb_addr == 7 && i_wb_sel[2] && i_wb_we)
			wide_address[55:48] = i_wb_data[23:16];
		if (i_wb_addr == 7 && i_wb_sel[3] && i_wb_we)
			wide_address[63:56] = i_wb_data[31:24];

		wide_address[63:ADDRESS_WIDTH] = 0;
	end
	// }}}

	// s_pkt_valid (ready is implied)
	// {{{
	always @(posedge i_clk)
	if (i_reset)
		s_sop <= 1'b1;
	else if (s_pkt_valid)
		s_sop <= s_last; // || s_pkt_abort;

	always @(posedge i_clk)
	if (i_reset)
		s_active <= 0;
	else if (s_pkt_valid && s_sop)
		s_active <= (s_data[7:0] == FIS_REG_TO_HOST);

	always @(posedge i_clk)
	if (i_reset)
		s_posn <= 0;
	else if (s_pkt_valid && s_last)
		s_posn <= 0;
	else if (s_pkt_valid && !s_posn[2])	// Saturate at 4
		s_posn <= s_posn + 1;
	// }}}

	// Master FSM
	// {{{
	wire	soft_reset;

	// The following state machine needs to handle exceptional conditions.
	// For now, these are encoded together as "soft_reset", but these
	// conditions may need separate or special handling:
	//
	//	External (i.e. Wishbone) reset request
	//	DMA Bus Error
	//	!i_link_up	Link Down
	//	Protocol Err	(We received something unexpected)
	//	Watchdog Err	(Keep us from getting stuck in any state)
	assign	soft_reset = 1'b0;

	always @(posedge i_clk)
	if (i_reset)
	begin
		// {{{
		fsm_state      <= FSM_IDLE;
		o_s2mm_request <= 1'b0;
		o_s2mm_addr    <= 0;
		//
		o_mm2s_request <= 1'b0;
		o_mm2s_addr    <= 0;
		//
		r_dma_address <= 0;
		r_features <= 0;
		r_command  <= 0;
		r_lba      <= 0;
		r_int      <= 0;
		r_device   <= 0;
		r_count    <= 0;
		r_busy     <= 0;
		r_icc      <= 0;
		r_port     <= 0;
		// }}}
	end else if (soft_reset)
	begin
		// {{{
		fsm_state      <= FSM_IDLE;
		o_s2mm_request <= 1'b0;
		o_s2mm_addr    <= 0;
		//
		o_mm2s_request <= 1'b0;
		o_mm2s_addr    <= 0;
		//
		r_dma_address <= 0;
		r_features <= 0;
		r_command  <= 0;
		r_lba      <= 0;
		r_int      <= 0;
		r_device   <= 0;
		r_count    <= 0;
		r_busy     <= 0;
		r_icc      <= 0;
		r_port     <= 0;
		// }}}
	end else begin

		if (s_pkt_valid && s_sop
				&& ( s_data[7:0] == FIS_REG_TO_HOST
				  || s_data[7:0] == FIS_SET_DEVBITS
				  || s_data[7:0] == FIS_PIO_SETUP))
		begin
			r_features[7:0] <= s_data[31:24];	// ERROR bits
			r_command       <= s_data[23:16];	// STATUS bits
			r_int           <= r_int || s_data[14];
			// The following bits are part of r_command
			// BSY  = s_data[23] = r_command[7]
			// DRDY = s_data[22] = r_command[6]
			// DF   = s_data[21] = r_command[5]
			// DRQ  = s_data[19] = r_command[4]
			// ERR  = s_data[15]
			last_fis <= s_data[7:0];
		end

		if (s_pkt_valid && s_sop && ( s_data[7:0] == FIS_DMA_SETUP))
			r_int           <= r_int || s_data[14];

		if (s_pkt_valid && s_active && s_posn == 1)
			{ r_device, r_lba[23:0] } <= s_data;
		if (s_pkt_valid && s_active && s_posn == 2)
			r_lba[47:24] <= s_data[23:0];
		if (s_pkt_valid && s_active && s_posn == 3)
			r_count <= s_data[15:0];

		case(fsm_state)
		FSM_IDLE: begin
			// {{{
			r_busy <= 1'b0;
			if (i_wb_stb && !o_wb_stall && i_wb_we && !m_valid)
			case(i_wb_addr)
			0: begin
				// {{{
				if (i_wb_sel[1])
				begin
					r_port     <= i_wb_data[11:8];
					r_int      <= r_int && !i_wb_data[14];
				end
				if (i_wb_sel[2])
					r_command  <= i_wb_data[23:16];
				if (i_wb_sel[3])
					r_features[7:0] <= i_wb_data[31:24];
				end
			// }}}
			1: begin
				// {{{
				if (i_wb_sel[0])
					r_lba[7:0] <= i_wb_data[7:0];
				if (i_wb_sel[1])
					r_lba[15:8] <= i_wb_data[15:8];
				if (i_wb_sel[2])
					r_lba[23:16] <= i_wb_data[23:16];
				if (i_wb_sel[3])
					r_device     <= i_wb_data[31:24];
				end
				// }}}
			2: begin
				// {{{
				if (i_wb_sel[0])
					r_lba[31:24] <= i_wb_data[7:0];
				if (i_wb_sel[1])
					r_lba[39:32] <= i_wb_data[15:8];
				if (i_wb_sel[2])
					r_lba[47:40] <= i_wb_data[23:16];
				if (i_wb_sel[3])
					r_features[15:8] <= i_wb_data[31:24];
				end
				// }}}
			3: begin
				// {{{
				if (i_wb_sel[0])
					r_count[7:0]  <= i_wb_data[7:0];
				if (i_wb_sel[1])
					r_count[15:8] <= i_wb_data[15:8];
				if (i_wb_sel[2])
					r_icc         <= i_wb_data[23:16];
				if (i_wb_sel[3])
					r_control     <= i_wb_data[31:24];
				end
				// }}}
			6: begin // r_dma_address
				// {{{
				r_dma_address <= wide_address[ADDRESS_WIDTH-1:0];
				end
				// }}}
			7: begin // r_dma_address
				// {{{
				r_dma_address <= wide_address[ADDRESS_WIDTH-1:0];
				end
				// }}}
			endcase

			if (known_cmd)
			begin
				fsm_state  <= FSM_COMMAND;
				last_fis <= FIS_REG_TO_DEV;

				o_tran_req <= 1;
				o_tran_src <= SRC_REGS;
				o_tran_len <= 20; // register set

				dma_length <= r_count;
				r_busy <= 1'b1;
			end end
			// }}}
		FSM_COMMAND: begin
			// {{{
			// output	reg			o_tran_req,
			// input	wire			i_tran_busy, i_tran_err,
			// output	reg			o_tran_src,
			// output	reg	[11:0]		o_tran_len,
			//
			if (o_tran_req && !i_tran_busy)
			begin
				o_tran_req <= 0;
				case(cmd_type)
				CMD_NONDATA:
					fsm_state <= FSM_WAIT_REG;
				CMD_PIO_READ:
					fsm_state <= FSM_PIO_IN_SETUP;
				CMD_PIO_WRITE:
					fsm_state <= FSM_PIO_OUT_SETUP;
				CMD_DMA_READ: begin
					fsm_state <= FSM_DMA_IN;

					o_s2mm_request     <= 1;
					// o_s2mm_addr      <= cmd_length;
					// S2MM length is given by the stream size
					// o_s2mm_length      <= cmd_length;
					// o_s2mm_transferlen <= (cmd_length < 2048)
					//		? cmd_length : 2048;
					end
				CMD_DMA_WRITE:
					fsm_state <= FSM_DMA_OUT_SETUP;
				default:
					// Will *NEVER* happen
					fsm_state <= FSM_WAIT_REG;
				endcase
			end end
			// }}}
		FSM_PIO_IN_SETUP: begin
			// {{{
			// Receive data via PIO
			last_rx_fis <= 1'b0;
			if (s_pkt_valid && s_sop
					&& s_data[7:0] == FIS_REG_TO_HOST)
				fsm_state <= FSM_IDLE;
			else if (s_pkt_valid && s_sop
					&& s_data[7:0] == FIS_PIO_SETUP)
			begin
				fsm_state <= FSM_PIO_RXDATA;
				last_rx_fis <= s_data[23]; // BSY
			end end
			// }}}
		FSM_PIO_RXDATA: begin
			// {{{
			if (i_s2mm_beat)
			begin
				// cmd_length  <= cmd_length - 4;
				o_s2mm_addr <= o_s2mm_addr   + $clog2(DW/8);
			end
			o_s2mm_request     <= 1;
			if (s_pkt_valid && s_sop
					&& s_data[7:0] == FIS_REG_TO_HOST)
				fsm_state <= (last_rx_fis) ? FSM_IDLE : FSM_PIO_IN_SETUP;
			end
			// }}}
		FSM_PIO_OUT_SETUP: begin
			// {{{
			// Transmit data via PIO
			if (s_pkt_valid && s_sop && s_data[7:0] == FIS_REG_TO_HOST)
				fsm_state <= FSM_IDLE;
			else if (s_pkt_valid && s_sop
					&& s_data[7:0] == FIS_PIO_SETUP)
			begin
				fsm_state <= FSM_PIO_TXDATA;
				o_tran_req <= 1;
				o_tran_src <= SRC_MM2S;
				o_tran_len <= (dma_length >= 2048) ? 2048 : dma_length[LGLENGTH:0]; // DATA_FIS
			end end
			// }}}
		FSM_PIO_TXDATA: begin
			// {{{
			if (o_tran_req && !i_tran_busy)
				o_tran_req <= 0;
			if (!o_tran_req && !i_tran_busy)
				fsm_state <= FSM_PIO_OUT_SETUP;
			end
			// }}}
		FSM_DMA_IN: begin // DMA read from device
			// {{{
			if (o_s2mm_request && !i_s2mm_busy)
				o_s2mm_request <= 1'b0;
			if (i_s2mm_beat)
				o_s2mm_addr <= o_s2mm_addr + 4;
			if (s_pkt_valid && s_sop
					&& s_data[7:0] == FIS_REG_TO_HOST)
				fsm_state <= FSM_DMA_IN_FINAL;
			end
		// }}}
		FSM_DMA_IN_FINAL: begin
			// {{{
			// Wrap up DMA read from device
			if (!i_s2mm_busy)
				fsm_state <= FSM_IDLE;
			end
			// }}}
		FSM_DMA_OUT_SETUP: begin // DMA write to device
			// {{{
			o_mm2s_request <= 0;
			o_tran_src <= SRC_MM2S;
			o_tran_len <= (dma_length > 2048) ? 2048 : dma_length[LGLENGTH:0];
			if (s_pkt_valid && s_sop
					&& s_data[7:0] == FIS_REG_TO_HOST)
				fsm_state <= FSM_IDLE;
			else if (s_pkt_valid && s_sop
					&& s_data[7:0] == FIS_DMA_ACTIVATE)
			begin
				fsm_state <= FSM_DMA_TXDATA;
				o_mm2s_request <= 1;
				o_tran_req <= 1;
			end end
			// }}}
		FSM_DMA_TXDATA: begin // DMA write to device
			// {{{
			if (o_mm2s_request && !i_mm2s_busy)
				o_mm2s_request <= 0;
			if (o_tran_req && !i_tran_busy)
				o_tran_req <= 0;
			if (!o_tran_req && !i_tran_busy
				&& !o_mm2s_request && !i_mm2s_busy)
				fsm_state <= FSM_DMA_OUT_SETUP;
			end
			// }}}
		FSM_WAIT_REG: begin
			// {{{
			if (s_pkt_valid && s_sop
					&& s_data[7:0] == FIS_REG_TO_HOST)
				fsm_state <= FSM_IDLE;
			end
			// }}}
		default: begin
			// {{{
			fsm_state <= FSM_IDLE;
			end
			// }}}
		endcase
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// m_*: Register FIS AXI stream output
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	reg	[1:0]	m_count;

	always @(posedge i_clk)
	if (i_reset || o_tran_req || o_tran_src == SRC_REGS)
		{ m_valid, m_last, m_count } <= 0;
	else if (!m_valid || m_ready)
	begin
		m_valid <= !m_last;
		if (!m_last)
		begin
			m_valid <= 1;
			m_last  <= (m_count >= 3);
			m_count <= m_count + 1;
		end
	end

	always @(posedge i_clk)
	if (!m_valid || m_ready)
	case(m_count + ((m_valid && m_ready) ? 1:0))
	0: m_data <= { FIS_REG_TO_DEV, !SRST,
				3'h0, r_port, r_command, r_features[7:0] };
	1: m_data <= { r_lba[7:0],  r_lba[15:8],  r_lba[23:16],r_device };
	2: m_data <= { r_lba[31:24],r_lba[39:32], r_lba[47:40],r_features[15:8]};
	3: m_data <= { r_count[7:0],r_count[15:8],r_icc,       r_control};
	default: m_data <= 0;
	endcase
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Wishbone returns
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	assign	o_wb_stall = known_cmd;

	initial	o_wb_ack = 1'b0;
	always @(posedge i_clk)
	if (i_reset) // || !i_wb_cyc)
		o_wb_ack <= 1'b0;
	else
		o_wb_ack <= i_wb_stb && !o_wb_stall;

	always @(posedge i_clk)
	if (OPT_LOWPOWER && (i_reset || !i_wb_stb))
		o_wb_data <= 32'b0;
	else begin
		o_wb_data <= 32'h0;
		case(i_wb_addr)
		0: o_wb_data <= { r_features[7:0], r_command,
					r_int, 3'b0, r_port, last_fis };
		1: o_wb_data <= { r_device, r_lba[23:0] };
		2: o_wb_data <= { r_features[15:8], r_lba[47:24] };
		3: o_wb_data <= { r_control, r_icc, r_count };
		// 5: o_wb_data <= { fsm_state, dma_err, i_link_up, o_link_reset }; // ...
		6: o_wb_data <= wide_address[31:0];
		7: o_wb_data <= wide_address[63:32];
		endcase
	end
	// }}}

	// Keep Verilator happy
	// {{{
	// Verilator lint_off UNUSED
	wire	unused;
	assign	unused = &{ 1'b0, i_wb_cyc,
			i_mm2s_err, i_s2mm_err, i_tran_err };
	// Verilator lint_on  UNUSED
	// }}}
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
	reg	f_past_valid;

	initial	f_past_valid <= 1'b0;
	always @(posedge i_clk)
		f_past_valid <= 1'b1;

	always @(*)
	if (!f_past_valid)
		assume(i_reset);

	////////////////////////////////////////////////////////////////////////
	//
	// Wishbone properties
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	fwb_slave #(
		// {{{
		.AW(3), .DW(32), .F_MAX_STALL(2), .F_MAX_ACK_DELAY(2),
		.F_LGDEPTH(2)
		// }}}
	) fwb (
		// {{{
		.i_clk(i_clk), .i_reset(i_reset),
		//
		.i_wb_cyc(i_wb_cyc), .i_wb_stb(i_wb_stb), .i_wb_we(i_wb_we),
		.i_wb_addr(i_wb_addr), .i_wb_data(i_wb_data),
			.i_wb_sel(i_wb_sel),
		//
		.i_wb_stall(o_wb_stall),
		.i_wb_ack(o_wb_ack),
		.i_wb_idata(o_wb_data),
		.i_wb_err(1'b0),
		//
		.f_nreqs(fwb_nreqs), .f_nacks(fwb_nacks),
		.f_outstanding(fwb_outstanding)
		// }}}
	);

	always @(posedge i_clk)
	if (r_busy)
		assert(!o_wb_stall);

	always @(*)
	if (i_wb_cyc)
		assert(fwb_outstanding == (o_wb_ack ? 1:0));

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// TRAN
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
		assert(!o_tran_req);
		assume(!i_tran_busy);
	end else if ($past(o_tran_req && i_tran_busy))
	begin
		assert(o_tran_req);
		assert($stable(o_tran_src));
		assert($stable(o_tran_len));
	end else if ($past(o_tran_req && i_tran_busy))
		assert(o_tran_req);

	always @(posedge i_clk)
	if ($past(o_tran_req && !i_tran_busy))
		assume(i_tran_busy || i_tran_err);

	always @(posedge i_clk)
	if ($past(!o_tran_req && !i_tran_busy))
	begin
		assume(!i_tran_busy);
		assume(!i_tran_err);
	end

	always @(*)
	if (!f_past_valid && !r_busy)
		assume(!o_tran_req);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// MM2S
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
		assert(!o_mm2s_request);
		assume(!i_mm2s_busy);
		assume(!i_mm2s_err);
	end else if ($past(o_mm2s_reqest && i_mm2s_busy))
	begin
		assert(o_mm2s_request);
		assert($stable(o_mm2s_addr));
	end

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && o_mm2s_request)
		assert(!i_mm2s_busy);

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && !$past(o_mm2s_request)
			&& !$past(i_mm2s_busy))
	begin
		assume(!i_mm2s_busy);
		assume(!i_mm2s_err);
	end

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && $past(i_mm2s_err))
		assume(!i_mm2s_busy);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// S2MM
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//


	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
		assert(!o_s2mm_request);
		assume(!i_s2mm_busy);
		assume(!i_s2mm_err);
	end else if ($past(o_s2mm_reqest && i_s2mm_busy))
	begin
		assert(o_s2mm_request);
		assert($stable(o_s2mm_addr));
	end

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && o_s2mm_request)
		assert(!i_s2mm_busy);

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && !$past(o_s2mm_request)
			&& !$past(i_s2mm_busy))
	begin
		assume(!i_s2mm_busy);
		assume(!i_s2mm_err);
	end

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && $past(i_s2mm_err))
		assume(!i_s2mm_busy);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// s_* properties
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// ... what properties are appropriate here?
	
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Master m_* axi stream properties
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
		assert(!m_valid);
	end else if ($past(m_valid && !m_ready))
	begin
		assert(m_valid);
		assert($stable(m_data));
		assert($stable(m_last));
	end else if ($past(m_valid && m_ready && m_last))
		assert(m_valid == !$past(m_last));

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// "Careless" assumptions
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	always @(*)
		assume(!i_tran_err);

	always @(*)
		assume(!i_mm2s_err);

	always @(*)
		assume(!i_s2mm_err);

	// }}}
`endif
// }}}
endmodule
