////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/formal/sata_framer.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Composes two SATA framing modules together, as a means for
//		formally verifying both.  If the design works as intended,
//	packets will pass sans modification between the two modules.
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
// }}}
module	sata_framer #(
		// {{{
		parameter	[0:0]	OPT_LOWPOWER = 1'b0,
		parameter		W = 32,
		parameter	[W:0]	P_SOF  = 33'h1_7cb5_3737,
		parameter	[W:0]	P_EOF  = 33'h1_7cb5_d5d5,
		parameter	[W:0]	P_HOLD = 33'h1_7caa_d5d5
		// }}}
	) (
		// {{{
		input	wire	i_clk, i_reset,
		//
		input	wire		S_AXIS_TVALID,
		output	wire		S_AXIS_TREADY,
		input	wire	[W-1:0]	S_AXIS_TDATA,
		input	wire		S_AXIS_TLAST,
		//
		output	wire		M_AXIS_TVALID,
		// input wire		M_AXIS_TREADY,
		output	wire	[W-1:0]	M_AXIS_TDATA,
		output	wire		M_AXIS_TLAST,
		output	wire		M_AXIS_TABORT
		// }}}
	);

	// Local declarations
	// {{{
	reg	f_past_valid;
	(* anyseq *)	reg		phy_ready;
	(* anyconst *)	reg		f_ckval;
	(* anyconst *)	reg	[31:0]	f_ckword;
	(* anyconst *)	reg	[31:0]	f_value;
	reg	[31:0]	s_word, m_word, tx_word;

	wire		tx_valid, tx_ready, rx_rvalid;
	wire	[1:0]	tx_state;
	wire		rx_state;
	wire	[W:0]	tx_data;
	wire	[W-1:0]	rx_rdata;
	// }}}

	satatx_framer #(
		.OPT_LOWPOWER(OPT_LOWPOWER)
	) tx (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.S_AXIS_TVALID(S_AXIS_TVALID), .S_AXIS_TREADY(S_AXIS_TREADY),
		.S_AXIS_TDATA(S_AXIS_TDATA), .S_AXIS_TLAST(S_AXIS_TLAST),
		//
		.M_AXIS_TVALID(tx_valid),
		.M_AXIS_TREADY(tx_ready && phy_ready),
		.M_AXIS_TDATA(tx_data),
		//
		// , .f_crc(tx_crc),
		.f_state(tx_state)
		// }}}
	);

	assign	tx_ready = 1;

	satarx_framer #(
		.OPT_LOWPOWER(OPT_LOWPOWER)
	) rx (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.S_AXIS_TVALID(tx_valid && phy_ready),
		.S_AXIS_TDATA(tx_data),
		.S_AXIS_TABORT(1'b0),
		//
		.M_AXIS_TVALID(M_AXIS_TVALID),
		.M_AXIS_TDATA(M_AXIS_TDATA),
		.M_AXIS_TABORT(M_AXIS_TABORT),
		.M_AXIS_TLAST(M_AXIS_TLAST),
		//
		.f_rvalid(rx_rvalid),
		.f_rdata(rx_rdata),
		.f_state(rx_state)
		// }}}
	);

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
// Formal properties
// {{{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

	// Reset
	// {{{
	initial	f_past_valid = 1'b0;
	always @(posedge i_clk)
		f_past_valid <= 1'b1;

	always @(*)
	if (!f_past_valid)
		assume(i_reset);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Stream properties
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// S_AXIS_* properties
	// {{{
	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
		assume(!S_AXIS_TVALID);
	end else if ($past(S_AXIS_TVALID && !S_AXIS_TREADY))
	begin
		assume(S_AXIS_TVALID);
		assume($stable(S_AXIS_TDATA));
		assume($stable(S_AXIS_TLAST));
	end
	// }}}

	// tx_* properties
	// {{{
	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
		assert(!tx_valid);
	end else if ($past(tx_valid && (!tx_ready || !phy_ready)))
	begin
		assert(tx_valid);
		assert($stable(tx_data));
	end
	// }}}
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Word counting
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// s_word
	// {{{
	initial	s_word = 0;
	always @(posedge i_clk)
	if (i_reset)
		s_word <= 0;
	else if (S_AXIS_TVALID && S_AXIS_TREADY)
	begin
		if (S_AXIS_TLAST)
			s_word <= 0;
		else
			s_word <= s_word + 1;
	end
	// }}}

	// tx_word
	// {{{
	initial	tx_word = 0;
	always @(posedge i_clk)
	if (i_reset)
		tx_word <= 0;
	else if (tx_valid && phy_ready)
	begin
		if (tx_data == P_SOF || tx_data == P_EOF)
			tx_word <= 0;
		else if (!tx_data[W])
			tx_word <= tx_word + 1;
	end
	// }}}

	// m_word
	// {{{
	initial	m_word = 0;
	always @(posedge i_clk)
	if (i_reset)
		m_word <= 0;
	else if (M_AXIS_TVALID)
	begin
		if (M_AXIS_TLAST)
			m_word <= 0;
		else
			m_word <= m_word + 1;
	end
	// }}}

	always @(*)
		assert(tx_word < 4096);

	always @(*)
		assert(m_word < 4096);

	always @(posedge i_clk)
	if (!i_reset)
	begin
		if (s_word > 0)
			assert(tx_state != 2'b00);

		if (s_word == 0)
		begin
			// assert(i_reset || tx_state == 2'b00 || tx_state == 2'b10);
			assert(!tx_valid || tx_data[32] || tx_state == 2'b10);

			if (tx_state == 2'b01 && tx_data[32])
			begin
				assert(tx_data == P_SOF);
				assert(S_AXIS_TVALID);
			end

			if (tx_valid && !tx_data[32])
				assert(tx_word < 4095);

			if (tx_valid && tx_data == P_SOF)
				assert(rx_state == 1'b0);

			assert(i_reset || !tx_valid || tx_data != P_HOLD);

			if (!tx_valid)
			begin
				assert(tx_word == 0);
			end else begin
				// assert(tx_data == P_EOF || tx_data == P_SOF);
			end
		end else begin
			assert(tx_state == 2'b01);
			assert(!tx_valid || tx_data != P_EOF);
			assert(!tx_valid || tx_data != P_SOF);
			assert(s_word == tx_word
				+ ((tx_valid && tx_data != P_HOLD) ? 1:0));
		end

		if (tx_word > 0)
			assert(tx_valid);

		if (tx_word == 0 && (!tx_valid || tx_data[32]))
			assert(rx_state == 1'b0);

		if (!i_reset)
		begin
			assert(rx_rvalid == (tx_word > 0));
		end

		if (M_AXIS_TVALID && M_AXIS_TLAST)
		begin
			assert(tx_word == 0);
		end else begin
			assert(tx_word == m_word + ((tx_word > 0) ? 1:0)
						+ (M_AXIS_TVALID ? 1:0));
		end

		if (tx_valid && tx_data != P_SOF)
			assert(rx_state == 1'b1);
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Contract rules
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	// Rule #1: Data in == Data out
	// {{{
	always @(*)
	if (!i_reset && f_ckval && S_AXIS_TVALID && s_word == f_ckword)
		assume(f_value == S_AXIS_TDATA);

	always @(*)
	if (!i_reset && f_ckval && tx_valid && tx_word == f_ckword
			&& !tx_data[W])
		assert({ 1'b0, f_value } == tx_data);

	always @(*)
	if (!i_reset && f_ckval && rx_rvalid && tx_word == f_ckword + 1)
		assert(f_value == rx_rdata);

	always @(*)
	if (!i_reset && f_ckval && M_AXIS_TVALID && m_word == f_ckword)
		assert(f_value == M_AXIS_TDATA);
	// }}}

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Cover properties
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	reg	[2:0]	cvr_frames;

	initial	cvr_frames = 0;
	always @(posedge i_clk)
	if (i_reset)
		cvr_frames <= 0;
	else if (M_AXIS_TVALID && M_AXIS_TLAST && m_word > 3)
		cvr_frames <= cvr_frames + 1;

	always @(posedge i_clk)
	if (!i_reset)
		cover(cvr_frames == 1);

	always @(posedge i_clk)
	if (!i_reset)
		cover(cvr_frames == 2);

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// "Careless" assumptions
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	always @(*)
	if (s_word < 1)
		assume(!S_AXIS_TVALID || !S_AXIS_TLAST);

	always @(*)
		assume(s_word < 4095);


	// }}}
// }}}
endmodule
