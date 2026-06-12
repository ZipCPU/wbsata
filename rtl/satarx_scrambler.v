////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./rtl/satarx_scrambler.v
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
//
`default_nettype none
`timescale 1ns/1ps
// }}}
module	satarx_scrambler #(
		// {{{
		parameter	[15:0]	POLYNOMIAL = 16'ha011,
		parameter	[15:0]	INITIAL = 16'hffff,
		parameter	[0:0]	OPT_LOWPOWER = 1'b1
		// }}}
	) (
		// {{{
		input	wire		S_AXI_ACLK, S_AXI_ARESETN,
		input	wire		i_cfg_scrambler_en,
		// Incoming data
		input	wire		S_AXIS_TVALID,
		output	wire		S_AXIS_TREADY,
		input	wire	[31:0]	S_AXIS_TDATA,
		input	wire		S_AXIS_TLAST,
		input	wire		S_AXIS_TABORT,
		// Outgoing data
		output	reg		M_AXIS_TVALID,
		input	wire		M_AXIS_TREADY,
		output	reg	[31:0]	M_AXIS_TDATA,
		output	reg		M_AXIS_TLAST,
		output	reg		M_AXIS_TABORT
`ifdef	FORMAL
		, output	wire	[15:0]	f_fill
		, output	wire	[31:0]	f_next
`endif
		// }}}
	);

	// Local declarations
	// {{{
	reg		r_active, midpacket;
	wire	[31:0]	prn;
	wire	[15:0]	next_fill;
	reg	[15:0]	fill;
	// }}}

	assign	S_AXIS_TREADY = !M_AXIS_TVALID || M_AXIS_TREADY;
	assign	{ prn, next_fill }= scramble(fill);

	// r_active
	// {{{
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
		r_active <= 0;
	else if (S_AXIS_TVALID)
	begin
		if (!S_AXIS_TREADY)
			r_active <= 1'b1;
		else
			r_active <= !S_AXIS_TLAST;
	end
	// }}}

	// fill
	// {{{
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
		fill <= INITIAL;
	else if (S_AXIS_TVALID && S_AXIS_TREADY)
	begin
		if (S_AXIS_TLAST)
			fill <= (i_cfg_scrambler_en) ? INITIAL : 16'h00;
		else
			fill <= next_fill;
	end else if (!r_active && !S_AXIS_TVALID)
		fill <= (i_cfg_scrambler_en) ? INITIAL : 16'h00;
	// }}}

	// midpacket
	// {{{
	initial	midpacket = 0;
	always @(posedge S_AXI_ACLK)
	if (!S_AXI_ARESETN)
		midpacket <= 0;
	else if (S_AXIS_TABORT && (!S_AXIS_TVALID || S_AXIS_TREADY))
		midpacket <= 0;
	else if (S_AXIS_TVALID && S_AXIS_TREADY)
		midpacket <= !S_AXIS_TLAST;
	// }}}

	// M_AXIS*
	// {{{
	initial	M_AXIS_TVALID = 0;
	always @(posedge S_AXI_ACLK)
	begin
		if (!M_AXIS_TVALID || M_AXIS_TREADY)
		begin
			M_AXIS_TVALID <= S_AXIS_TVALID && (midpacket || !S_AXIS_TABORT);
			M_AXIS_TABORT <= 1'b0;

			if (i_cfg_scrambler_en)
				M_AXIS_TDATA  <= S_AXIS_TDATA ^ prn;
			else
				M_AXIS_TDATA  <= S_AXIS_TDATA;
			M_AXIS_TLAST  <= S_AXIS_TLAST;

			if (OPT_LOWPOWER && (!S_AXIS_TVALID || S_AXIS_TABORT))
				{ M_AXIS_TLAST, M_AXIS_TDATA } <= 0;
		end

		if (S_AXIS_TABORT && (!S_AXIS_TVALID || S_AXIS_TREADY))
			M_AXIS_TABORT <= (M_AXIS_TABORT && M_AXIS_TVALID && !M_AXIS_TREADY) || midpacket;

		if (!S_AXI_ARESETN)
		begin
			M_AXIS_TVALID <= 0;
			M_AXIS_TABORT <= 0;
			if (OPT_LOWPOWER)
			begin
				M_AXIS_TDATA  <= 0;
				M_AXIS_TLAST  <= 0;
			end
		end
	end
	// }}}

	function automatic [32+16-1:0]	scramble(input [15:0] prior);
		// {{{
		integer	k;
		reg	[15:0]	s_fill;
		reg	[31:0]	s_prn;
	begin
		s_fill = prior;
		for(k=0; k<32; k=k+1)
		begin
			s_prn[k] = s_fill[15];

			if (s_fill[15])
				s_fill = { s_fill[14:0], 1'b0 } ^ POLYNOMIAL;
			else
				s_fill = { s_fill[14:0], 1'b0 };
		end

		scramble = { s_prn, s_fill };
	end endfunction
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
	localparam	MAX_LENGTH = 1022;
	localparam	LGMX = $clog2(MAX_LENGTH+1);
	reg	f_past_valid;
	wire	[LGMX-1:0]	fs_word, fm_word;
	wire	[12-1:0]	fs_pkt, fm_pkt;
	(* anyconst *)	reg	f_enabled;

	initial	f_past_valid = 0;
	always @(posedge S_AXI_ACLK)
		f_past_valid <= 1;

	always @(posedge S_AXI_ACLK)
	if (!f_past_valid)
		assume(!S_AXI_ARESETN);

	always @(*)
		assume(i_cfg_scrambler_en == f_enabled);

	always @(posedge S_AXI_ACLK)
	if (S_AXI_ARESETN && f_enabled)
		assert(fill != 0);

	////////////////////////////////////////////////////////////////////////
	//
	// Basic AXI-N stream properties
	// {{{
	faxin_slave #(
		.DATA_WIDTH(32),
		.MAX_LENGTH(MAX_LENGTH)
	) f_slave (
		// {{{
		.S_AXI_ACLK(S_AXI_ACLK),
		.S_AXI_ARESETN(S_AXI_ARESETN),
		.S_AXIN_VALID(S_AXIS_TVALID),
		.S_AXIN_READY(S_AXIS_TREADY),
		.S_AXIN_DATA(S_AXIS_TDATA),
		.S_AXIN_BYTES(0),
		.S_AXIN_LAST(S_AXIS_TLAST),
		.S_AXIN_ABORT(S_AXIS_TABORT),
		//
		.f_stream_word(fs_word),
		.f_packets_rcvd(fs_pkt)
		// }}}
	);

	faxin_master #(
		.DATA_WIDTH(32),
		.MAX_LENGTH(MAX_LENGTH)
	) f_master (
		// {{{
		.S_AXI_ACLK(S_AXI_ACLK),
		.S_AXI_ARESETN(S_AXI_ARESETN),
		.S_AXIN_VALID(M_AXIS_TVALID),
		.S_AXIN_READY(M_AXIS_TREADY),
		.S_AXIN_DATA(M_AXIS_TDATA),
		.S_AXIN_BYTES(0),
		.S_AXIN_LAST(M_AXIS_TLAST),
		.S_AXIN_ABORT(M_AXIS_TABORT),
		//
		.f_stream_word(fm_word),
		.f_packets_rcvd(fm_pkt)
		// }}}
	);

	// Restate the slave stream property(s)
	// {{{
	always @(posedge S_AXI_ACLK)
	if (!f_past_valid || !$past(S_AXI_ARESETN))
		assume(!S_AXIS_TVALID);
	else if ($past(S_AXIS_TVALID && !S_AXIS_TREADY))
	begin
		assume(S_AXIS_TVALID);
		assume($stable(S_AXIS_TDATA));
		assume($stable(S_AXIS_TLAST));
		assume(!$fell(S_AXIS_TABORT));
	end
	// }}}

	// Restate the master stream property(s)
	// {{{
	always @(posedge S_AXI_ACLK)
	if (!f_past_valid || !$past(S_AXI_ARESETN))
		assert(!M_AXIS_TVALID);
	else if ($past(M_AXIS_TVALID && !M_AXIS_TREADY))
	begin
		assert(M_AXIS_TVALID);
		assert($stable(M_AXIS_TDATA));
		assert($stable(M_AXIS_TLAST));
		assert(!$fell(M_AXIS_TABORT));
	end
	// }}}

	//// Tie the properties of slave and master together
	// {{{
	always @(posedge S_AXI_ACLK)
	if (S_AXI_ARESETN)
	begin
		if (!S_AXIS_TABORT)
			assert(midpacket == (fs_word > 0));
		if (M_AXIS_TVALID || fm_word != 0)
			assert(midpacket || M_AXIS_TLAST || M_AXIS_TABORT);
		if (M_AXIS_TABORT)
			assert(fs_word == 0);

		if (M_AXIS_TVALID && (M_AXIS_TLAST || M_AXIS_TABORT))
			assert(fs_word == 0);
		if (!M_AXIS_TABORT && !S_AXIS_TABORT && (!M_AXIS_TVALID || !M_AXIS_TLAST))
			assert(fm_word + (M_AXIS_TVALID ? 1:0) == fs_word);

		assert(fm_pkt + ((M_AXIS_TVALID && M_AXIS_TLAST && !M_AXIS_TABORT) ? 1:0) == fs_pkt);
	end
	// }}}

	always @(posedge S_AXI_ACLK)
	if (S_AXI_ARESETN && !M_AXIS_TVALID && OPT_LOWPOWER)
	begin
		assert(M_AXIS_TDATA == 0);
		assert(M_AXIS_TLAST == 0);
	end
	// }}}

	assign	f_fill = (S_AXIS_TVALID) ? next_fill : fill;
	assign	f_next = prn;

	////////////////////////////////////////////////////////////////////////
	//
	// Careless assumptions
	// {{{
	always @(*)
		assume(!fs_pkt[11] && !fm_pkt[11]);
	// }}}
// }}}
`endif
endmodule
