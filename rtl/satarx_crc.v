////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	sata/satarx_crc.v
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
// Copyright (C) 2021-2023, Gisselquist Technology, LLC
// {{{
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
// }}}
// License:	GPL, v3, as defined and found on www.gnu.org,
// {{{
//		http://www.gnu.org/licenses/gpl.html
//
////////////////////////////////////////////////////////////////////////////////
`default_nettype none
// }}}
module	satarx_crc #(
		// {{{
		parameter	[31:0]	POLYNOMIAL = 32'h04c1_1db7,
		parameter	[31:0]	INITIAL_CRC = 32'h5232_5032,
		parameter	[0:0]	OPT_LOWPOWER = 1'b1
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
		, output wire	[31:0]	f_crc
		, output wire		f_valid
		, output wire [31:0]	f_data
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
	initial	crc        = INITIAL_CRC;
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
	begin
		crc       <= INITIAL_CRC;
	end else if (S_AXIS_TVALID)
	begin

		if (S_AXIS_TLAST)
		begin
			crc   <= INITIAL_CRC;
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
	end else if (S_AXIS_TVALID)
	begin
		r_valid <= S_AXIS_TVALID && (!i_cfg_crc_en || !S_AXIS_TLAST);
		r_data  <= S_AXIS_TDATA;
		r_last  <= S_AXIS_TLAST;
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
	assign	f_crc = crc;
	assign	f_valid = r_valid;
	assign	f_data = r_data;

	always @(*)
	if (S_AXI_ARESETN && M_AXIS_TVALID && !M_AXIS_TLAST)
	begin
		assert(r_valid);
	end

	always @(*)
	if (S_AXI_ARESETN && (!M_AXIS_TVALID || !M_AXIS_TLAST))
	begin
		assert(!M_AXIS_TABORT);
	end
`endif
// }}}
endmodule
