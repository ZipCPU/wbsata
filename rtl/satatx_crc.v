////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/satatx_crc.v
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
// Copyright (C) 2021-2025, Gisselquist Technology, LLC
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
module	satatx_crc #(
		// {{{
`ifdef	FORMAL
		parameter		LGMX = 16,
`endif
		parameter	[31:0]	POLYNOMIAL = 32'h04c1_1db7,
		parameter	[31:0]	INITIAL_CRC = 32'h5232_5032,
		parameter	[0:0]	OPT_LOWPOWER = 1'b1
		// }}}
	) (
		// {{{
		input	wire	S_AXI_ACLK, S_AXI_ARESETN,
		// input wire	abort,	// ???
		// Incoming data
		input	wire		S_AXIS_TVALID,
		output	wire		S_AXIS_TREADY,
		input	wire	[31:0]	S_AXIS_TDATA,
		input	wire		S_AXIS_TLAST,
		// Outgoing data
		output	reg		M_AXIS_TVALID,
		input	wire		M_AXIS_TREADY,
		output	reg	[31:0]	M_AXIS_TDATA,
		output	reg		M_AXIS_TLAST
`ifdef	FORMAL
		, output wire [31:0]	f_crc
		, output wire [1:0]	f_state
		, output wire [LGMX-1:0] fs_word, fm_word
`endif
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[1:0]	S_IDLE = 2'b00,
				S_DATA = 2'b01,
				S_CRC  = 2'b10;
	reg	[1:0]	state;
	reg	[31:0]	crc;
	// }}}

	assign	S_AXIS_TREADY = (state != S_CRC || M_AXIS_TLAST)
					// && (!M_AXIS_TVALID || !M_AXIS_TLAST)
					&& (!M_AXIS_TVALID || M_AXIS_TREADY);

	// state
	// {{{
	initial	state = S_IDLE;
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
		state <= S_IDLE;
	else if (S_AXIS_TVALID && S_AXIS_TREADY)
	begin
		state <= S_DATA;
		if (S_AXIS_TLAST)
			state <= S_CRC;
	end else if (M_AXIS_TVALID && M_AXIS_TREADY)
	begin
		if (state == S_CRC)
			state <= S_IDLE;
	end
	// }}}

	// crc
	// {{{
	wire	[31:0]	next_crc;

	assign	next_crc = advance_crc(crc, S_AXIS_TDATA);

	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
		crc <= INITIAL_CRC;
	else if (S_AXIS_TVALID && S_AXIS_TREADY)
	begin
		crc <= next_crc;
	// end else if (M_AXIS_TVALID && M_AXIS_TREADY && M_AXIS_TLAST)
	end else if (state == S_CRC && (!M_AXIS_TVALID || M_AXIS_TREADY))
	begin
		crc <= INITIAL_CRC;
	end
	// }}}

	// M_AXIS*
	// {{{
	initial	M_AXIS_TVALID = 1'b0;
	initial	M_AXIS_TDATA  = 0;
	initial	M_AXIS_TLAST  = 1'b0;
	always @(posedge S_AXI_ACLK)
	begin
		if (!M_AXIS_TVALID || M_AXIS_TREADY)
		begin
			M_AXIS_TVALID <= (S_AXIS_TVALID && S_AXIS_TREADY) || (state == S_CRC);
			M_AXIS_TDATA  <= (state == S_CRC) ? crc : S_AXIS_TDATA;
			M_AXIS_TLAST  <= (state == S_CRC) && !M_AXIS_TLAST;

			if (OPT_LOWPOWER && !S_AXIS_TVALID && (state != S_CRC))
				{ M_AXIS_TLAST, M_AXIS_TDATA } <= 0;
		end

		if (!S_AXI_ARESETN)
		begin
			M_AXIS_TVALID <= 0;
			M_AXIS_TLAST  <= 0;
			if (OPT_LOWPOWER)
			begin
				M_AXIS_TDATA  <= 0;
			end
		end
	end
	// }}}

	function [31:0]	advance_crc(input [31:0] prior, input[31:0] dword);
		// {{{
		integer	k;
		reg	[31:0]	sreg;
	begin
		sreg = prior;
		for(k=0; k<32; k=k+1)
		begin
			if (sreg[31] ^ dword[31-k])
				sreg = { sreg [30:0], 1'b0 } ^ POLYNOMIAL;
			else
				sreg = { sreg[30:0], 1'b0 };
		end

		advance_crc = sreg;
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
	reg	f_past_valid;

	initial	f_past_valid = 0;
	always @(posedge S_AXI_ACLK)
		f_past_valid <= 1;

	always @(*)
	if (!f_past_valid)
		assume(!S_AXI_ARESETN);

	always @(*)
	if (S_AXI_ARESETN)
		assert(state != 2'b11);

	always @(*)
	if (S_AXI_ARESETN && state == S_CRC)
		assert(M_AXIS_TVALID);

	always @(*)
	if (S_AXI_ARESETN && state == S_CRC && M_AXIS_TVALID)
		assert(!M_AXIS_TLAST);

	always @(*)
	if (S_AXI_ARESETN && M_AXIS_TLAST)
	begin
		assert(M_AXIS_TVALID);
		assert(crc == INITIAL_CRC);
		assert(state == S_IDLE);
	end

	assign	f_crc = crc;
	assign	f_state = state;
	////////////////////////////////////////////////////////////////////////
	//
	// Stream properties
	// {{{
	always @(posedge S_AXI_ACLK)
	if (!f_past_valid || !$past(S_AXI_ARESETN))
		assume(!S_AXIS_TVALID);
	else if ($past(S_AXIS_TVALID && !S_AXIS_TREADY))
	begin
		assume(S_AXIS_TVALID);
		assume($stable(S_AXIS_TDATA));
		assume($stable(S_AXIS_TLAST));
	end

	always @(posedge S_AXI_ACLK)
	if (!f_past_valid || !$past(S_AXI_ARESETN))
		assert(!M_AXIS_TVALID);
	else if ($past(M_AXIS_TVALID && !M_AXIS_TREADY))
	begin
		assert(M_AXIS_TVALID);
		assert($stable(M_AXIS_TDATA));
		assert($stable(M_AXIS_TLAST));
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Stream position counting
	// {{{

	///////////
	//
	// Slave stream counting

	initial	fs_word = 0;
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
		fs_word <= 0;
	else if (S_AXIS_TVALID && S_AXIS_TREADY)
	begin
		fs_word <= fs_word + 1;
		if (S_AXIS_TLAST)
			fs_word <= 0;
	end

	///////////
	//
	// Make sure the source counter never overflows
	always @(*)
	if (fs_word >= 16'hfffc)
		assume(!S_AXIS_TVALID || S_AXIS_TLAST);

	always @(*)
		assert(fs_word <= 16'hfffc);

	///////////
	//
	// Master stream counting

	initial	fm_word = 0;
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
		fm_word <= 0;
	else if (M_AXIS_TVALID && M_AXIS_TREADY)
	begin
		fm_word <= fm_word + 1;
		if (M_AXIS_TLAST)
			fm_word <= 0;
	end

	///////////
	//
	// Cross stream count correlations

	always @(*)
	if (S_AXI_ARESETN)
	begin
		assert(fm_word <= 16'hfffd);
		if (fm_word == 16'hfffd)
			assert(M_AXIS_TVALID && M_AXIS_TLAST);

		if (state == S_CRC || (M_AXIS_TVALID && M_AXIS_TLAST))
		begin
			assert(fs_word == 0);
		end else begin
			assert(!M_AXIS_TVALID || !M_AXIS_TLAST);
			assert(fs_word == fm_word + (M_AXIS_TVALID ? 1:0));
		end
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Cover checks
	// {{{
	always @(posedge S_AXI_ACLK)
	if (S_AXI_ARESETN)
	begin
		cover(M_AXIS_TVALID && M_AXIS_TREADY && M_AXIS_TLAST && fm_word > 5);
		cover(M_AXIS_TVALID && M_AXIS_TREADY && M_AXIS_TLAST && fm_word > 7);
		cover(M_AXIS_TVALID && M_AXIS_TREADY && M_AXIS_TLAST && fm_word > 8);
	end
	// }}}
`endif
endmodule
