////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./rtl/satarx_crc.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Read packets, and suppress packets with bad CRCs.  Received
//		packets are then forwarded (via async FIFO) to whomever wants
//	them next.  If a packet has a bad CRC, then M_AXIS_TABORT will also be
//	true on the M_AXIS_TVALID && M_AXIS_TLAST beat.
//
//	Question: Do we handle repeat packet transmission requests here?  No.
//
// Design:
//	W/ each message word, we have
//		MSG_new = (MSG_old * 2^32) ^ (DATA_new)
//	We want:
//		CRC = Remainder (  MSG_new / POLYNOMIAL )
//		    = Remainder ( (MSG_old * 2^32) ^ DATA_new / POLYNOMIAL )
//
//	On the last word, if (DATA_new == CRC), then we have a valid packet
//
// Status:
//	Lint check:		Yes
//	Formal check:		NO
//	Simulation check:	NO
//	Hardware check:		NO
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
`default_nettype none
`timescale 1ns/1ps
// }}}
module	satarx_crc #(
		// {{{
		parameter	[31:0]	POLYNOMIAL = 32'h04c1_1db7,
		parameter	[31:0]	INITIAL_CRC = 32'h5232_5032,
		parameter	[0:0]	OPT_LOWPOWER = 1'b1
`ifdef	FORMAL
		// The maximum packet length is really quite arbitrary.
		// We need it, though, to size our register counters
		, parameter	MAX_LENGTH = 1022,
		localparam	MIN_LENGTH = 3,
		localparam	LGMX = $clog2(MAX_LENGTH+1)
`endif
		// }}}
	) (
		// {{{
		input	wire	S_AXI_ACLK, S_AXI_ARESETN,
		// Configuration
		input	wire		i_cfg_crc_en,
		// Incoming data
		// {{{
		input	wire		S_AXIS_TVALID,
		// output	wire		S_AXIS_TREADY,	MUST == 1
		// output	wire		S_AXIS_TFULL,
		input	wire	[31:0]	S_AXIS_TDATA,
		input	wire		S_AXIS_TLAST,	// True on CRC word
		input	wire		S_AXIS_TABORT,
		// }}}
		// Outgoing data
		// {{{
		output	reg		M_AXIS_TVALID,
		// input wire		M_AXIS_TREADY,	MUST == 1
		// input wire		M_AXIS_TFULL,
		output	reg	[31:0]	M_AXIS_TDATA,
		output	reg		M_AXIS_TABORT,
		output	reg		M_AXIS_TLAST
		// }}}
`ifdef	FORMAL
		// {{{
		, output wire	[LGMX-1:0]	fs_word
		, output wire	[31:0]		f_crc
		, output wire			f_valid
		, output wire [31:0]		f_data
		// }}}
`endif
		// }}}
	);

	// Local declarations
	// {{{
	reg	[31:0]	crc;

	reg		r_valid, r_last;
	reg	[31:0]	r_data;
	// }}}

	// crc
	// {{{
	initial	crc = INITIAL_CRC;
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
	begin
		crc <= INITIAL_CRC;
	end else if (S_AXIS_TVALID)
	begin

		if (S_AXIS_TLAST)
		begin
			crc <= INITIAL_CRC;
		end else
			crc <= advance_crc(crc, S_AXIS_TDATA);
	end
	// }}}

	// r_*: Register locally for one cycle
	// {{{
	initial	r_valid = 1'b0;
	initial	r_last  = 1'b0;
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
	begin
		r_valid <= 1'b0;
		r_data  <= 0;
		r_last  <= 1'b0;
	end else begin
		if (S_AXIS_TVALID)
		begin
			r_valid <= (!i_cfg_crc_en || !S_AXIS_TLAST);
			r_data  <= S_AXIS_TDATA;
			r_last  <= S_AXIS_TLAST;
		end else if (!i_cfg_crc_en)
			r_valid <= 1'b0;

		if (S_AXIS_TABORT)
			r_valid <= 0;

	end
	// }}}

	// M_AXIS*
	// {{{
	initial	M_AXIS_TVALID = 1'b0;
	initial	M_AXIS_TABORT = 1'b0;
	always @(posedge S_AXI_ACLK)
	begin
		M_AXIS_TVALID <= 1'b0;
		M_AXIS_TABORT <= (r_valid && S_AXIS_TVALID && S_AXIS_TLAST)
				&& (crc != S_AXIS_TDATA) && i_cfg_crc_en;

		if ((r_valid || !i_cfg_crc_en) && S_AXIS_TABORT)
			M_AXIS_TABORT <= 1'b1;

		if (OPT_LOWPOWER)
		begin
			M_AXIS_TDATA <= 0;
			M_AXIS_TLAST <= 0;
		end

		if (r_valid && (!i_cfg_crc_en || S_AXIS_TVALID))
		begin
			M_AXIS_TVALID <= r_valid;
			M_AXIS_TDATA  <= r_data;
			if (i_cfg_crc_en)
				M_AXIS_TLAST  <= S_AXIS_TLAST;
			else
				M_AXIS_TLAST  <= r_last;
		end

		if (!S_AXI_ARESETN)
		begin
			M_AXIS_TVALID <= 0;
			M_AXIS_TABORT <= 0;
			if (OPT_LOWPOWER)
			begin
				M_AXIS_TDATA <= 0;
				M_AXIS_TLAST <= 0;
			end
		end
	end
	// }}}

	function [31:0]	advance_crc(input [31:0] prior, input[31:0] dword);
		// {{{
		integer	k;
		reg	[31:0]	sreg;
	begin
	// Verilator lint_off BLKSEQ
		sreg = prior;
		for(k=0; k<32; k=k+1)
		begin
			if (sreg[31] ^ dword[31-k])
				sreg = { sreg [30:0], 1'b0 } ^ POLYNOMIAL;
			else
				sreg = { sreg[30:0], 1'b0 };
		end

		advance_crc = sreg;
	// Verilator lint_on  BLKSEQ
	end endfunction
	// }}}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
// Formal properties (for use with CRC wrapper)
// {{{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
`ifdef	FORMAL
	reg		f_past_valid;
	wire	[LGMX-1:0]	fm_word, fsum;
	wire	[12-1:0]	fs_pkts, fm_pkts;
	(* anyconst *)	reg	r_en;

	always @(*)
		assume(i_cfg_crc_en == r_en);

	initial	f_past_valid = 0;
	always @(posedge S_AXI_ACLK)
		f_past_valid <= 1;

	assign	f_crc = crc;
	assign	f_valid = r_valid;
	assign	f_data = r_data;
	////////////////////////////////////////////////////////////////////////
	//
	// AXIN property set(s)
	// {{{
`ifdef	RXCRC
	faxin_slave
`else
	faxin_master
`endif
	#(
		.DATA_WIDTH(32),
		.MIN_LENGTH(MIN_LENGTH+1),
		.MAX_LENGTH(MAX_LENGTH)
	) f_slv (
		// {{{
		.S_AXI_ACLK(S_AXI_ACLK),
		.S_AXI_ARESETN(S_AXI_ARESETN),
		//
		.S_AXIN_VALID(S_AXIS_TVALID),
		.S_AXIN_READY(1'b1),
		.S_AXIN_DATA(S_AXIS_TDATA),
		.S_AXIN_BYTES(0),
		.S_AXIN_LAST(S_AXIS_TLAST),
		.S_AXIN_ABORT(S_AXIS_TABORT),
		//
		.f_stream_word(fs_word),
		.f_packets_rcvd(fs_pkts)
		// }}}
	);

`ifndef	RXCRC
	always @(*)
	if (S_AXI_ARESETN)
		assume(fs_word >= MIN_LENGTH+2 || !S_AXIS_TVALID || !S_AXIS_TLAST);
`endif

	faxin_master #(
		.DATA_WIDTH(32),
		.MAX_LENGTH(MAX_LENGTH),
		.MIN_LENGTH(MIN_LENGTH)
	) f_master (
		// {{{
		.S_AXI_ACLK(S_AXI_ACLK),
		.S_AXI_ARESETN(S_AXI_ARESETN),
		//
		.S_AXIN_VALID(M_AXIS_TVALID),
		.S_AXIN_READY(1'b1),
		.S_AXIN_DATA(M_AXIS_TDATA),
		.S_AXIN_BYTES(0),
		.S_AXIN_LAST(M_AXIS_TLAST),
		.S_AXIN_ABORT(M_AXIS_TABORT),
		//
		.f_stream_word(fm_word),
		.f_packets_rcvd(fm_pkts)
		// }}}
	);
	// }}}

	always @(*)
	if (S_AXI_ARESETN && M_AXIS_TVALID && !M_AXIS_TLAST && r_en)
	begin
		assert(r_valid || M_AXIS_TABORT);
	end

	// always @(*)
	// if (S_AXI_ARESETN && (!M_AXIS_TVALID || !M_AXIS_TLAST))
	// begin
		// assert(!M_AXIS_TABORT);
	// end

	assign	fsum = fm_word + (M_AXIS_TVALID ? 1:0) + (r_valid ? 1:0);
	always @(posedge S_AXI_ACLK)
	if (S_AXI_ARESETN)
	begin
		if (fm_word == MAX_LENGTH-1 && !M_AXIS_TVALID)
			assert(!r_valid || r_last);
		if (fs_word > 0 && r_en)
			assert(r_valid);
		if (r_en)
			assert(!r_valid || !r_last);

		if ((!r_valid || !r_last) && M_AXIS_TVALID && M_AXIS_TLAST)
			assert(fs_word == (r_valid ? 1:0));
		if (r_valid && r_last)
			assert(fs_word == 0);
		if (fs_word == 0 && (r_valid || fm_word != 0) && !M_AXIS_TABORT)
			assert((r_valid && r_last) || (M_AXIS_TVALID && M_AXIS_TLAST));
		if (fs_word > 0 && (!r_valid || !r_last) && (!M_AXIS_TVALID || !M_AXIS_TLAST))
		begin
			assert(fs_word == fsum);
				// fm_word
				// + (M_AXIS_TVALID ? 1:0) + (r_valid ? 1:0));
			assert(!r_last);
		end
	end
	////////////////////////////////////////////////////////////////////////
	//
	// Cover checks
	// {{{
	always @(posedge S_AXI_ACLK)
	if (S_AXI_ARESETN)
	begin
		cover(fm_word > 5 && M_AXIS_TVALID && M_AXIS_TLAST && !M_AXIS_TABORT);
		cover(fm_word > 5 && M_AXIS_TVALID && M_AXIS_TABORT);
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// "Careless" assumptions
	// {{{
	// always @(*) assume(r_en);
	// }}}
`endif
// }}}
endmodule
