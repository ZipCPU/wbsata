////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	bench/formal/sata_scrambler.v (a formal wrapper)
// {{{
// Project:	Demonstration SONAR project
//
// Purpose:	Composes two scrambler modules together, as a means for formally
//		verifying both.  If the design works as intended, values will
//	pass through both scrambler components (TX and RX) without modification.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2021-2022, Gisselquist Technology, LLC
// {{{
// The algorithms described in this file are proprietary to Gisselquist
// Technology, LLC.  They may not be redistributed without the express
// permission of an authorized representative of Gisselquist Technology.
//
////////////////////////////////////////////////////////////////////////////////
//
`default_nettype none
// }}}
module	sata_scrambler #(
		// {{{
		parameter	[0:0]	OPT_LOWPOWER = 1'b0,
		parameter		W = 32
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
		input wire		M_AXIS_TREADY,
		output	wire	[W-1:0]	M_AXIS_TDATA,
		output	wire		M_AXIS_TLAST
		// }}}
	);

	// Local declarations
	// {{{
	reg	f_past_valid;
	(* anyconst *)	reg		f_ckval;
	(* anyconst *)	reg	[31:0]	f_ckword;
	(* anyconst *)	reg	[32:0]	f_value;
	reg	[31:0]	s_word, m_word, tx_word;

	wire		tx_valid, tx_ready, tx_last;
	wire	[W-1:0]	tx_data;

	wire	[15:0]	tx_fill, rx_fill;
	wire	[31:0]	rx_prn, clear_data;

	// wire	[31:0]	tx_crc, rx_crc;
	// wire	[1:0]	tx_state;
	// wire		rx_rvalid;
	// wire	[31:0]	rx_rdata;
	// }}}

	satatx_scrambler #(
		.OPT_LOWPOWER(OPT_LOWPOWER)
	) tx (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.S_AXIS_TVALID(S_AXIS_TVALID),
		.S_AXIS_TREADY(S_AXIS_TREADY),
		.S_AXIS_TDATA(S_AXIS_TDATA),
		.S_AXIS_TLAST(S_AXIS_TLAST),
		//
		.M_AXIS_TVALID(tx_valid),
		.M_AXIS_TREADY(tx_ready),
		.M_AXIS_TDATA(tx_data),
		.M_AXIS_TLAST(tx_last),
		//
		.f_fill(tx_fill)
		// }}}
	);

	satarx_scrambler #(
		.OPT_LOWPOWER(OPT_LOWPOWER)
	) rx (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.i_cfg_scrambler_en(1'b1),
		//
		.S_AXIS_TVALID(tx_valid),
		.S_AXIS_TREADY(tx_ready),
		.S_AXIS_TDATA(tx_data),
		.S_AXIS_TLAST(tx_last),
		//
		.M_AXIS_TVALID(M_AXIS_TVALID),
		.M_AXIS_TREADY(M_AXIS_TREADY),
		.M_AXIS_TDATA(M_AXIS_TDATA),
		.M_AXIS_TLAST(M_AXIS_TLAST),
		//
		.f_fill(rx_fill),
		.f_next(rx_prn)
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
	end else if ($past(tx_valid && !tx_ready))
	begin
		assert(tx_valid);
		assert($stable(tx_data));
		assert($stable(tx_last));
	end
	// }}}

	// M_AXIS_* properties
	// {{{
	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
	begin
		assert(!M_AXIS_TVALID);
	end else if ($past(M_AXIS_TVALID && !M_AXIS_TREADY))
	begin
		assert(M_AXIS_TVALID);
		assert($stable(M_AXIS_TDATA));
		assert($stable(M_AXIS_TLAST));
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
	else if (tx_valid && tx_ready)
	begin
		if (tx_last)
			tx_word <= 0;
		else
			tx_word <= tx_word + 1;
	end
	// }}}

	// m_word
	// {{{
	initial	m_word = 0;
	always @(posedge i_clk)
	if (i_reset)
		m_word <= 0;
	else if (M_AXIS_TVALID && M_AXIS_TREADY)
	begin
		if (M_AXIS_TLAST)
			m_word <= 0;
		else
			m_word <= m_word + 1;
	end
	// }}}

	always @(*)
	if (s_word < 1)
		assume(!S_AXIS_TVALID || !S_AXIS_TLAST);

	always @(*)
		assume(s_word < 4096);

	always @(*)
		assert(tx_word + ((tx_valid && !tx_last) ? 1:0) < 4096);

	always @(*)
		assert(m_word +((M_AXIS_TVALID && !M_AXIS_TLAST) ? 1:0) < 4096);


	always @(*)
	begin
		if (tx_valid)
		begin
			assert((s_word == 0) == tx_last);
		end

		if (s_word == 0)
		begin
			if (tx_valid)
			begin
				assert(tx_last);
			end else
				assert(tx_word == 0);
		end else begin
			assert(s_word == tx_word + (tx_valid ? 1:0));
		end

		if (M_AXIS_TVALID && M_AXIS_TLAST)
		begin
			assert(tx_word == 0);
		end else begin
			assert(tx_word == m_word + (M_AXIS_TVALID ? 1:0));
		end
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
		assume(f_value == { S_AXIS_TLAST, S_AXIS_TDATA });

	// TX WORD will be scrambled, so we can't check it here
	assign	clear_data = tx_data ^ rx_prn;
	always @(*)
	if (!i_reset && f_ckval && tx_valid && tx_word == f_ckword)
		assert(f_value == { tx_last, clear_data });

	always @(*)
	if (!i_reset && f_ckval && M_AXIS_TVALID && m_word == f_ckword)
		assert(f_value == { M_AXIS_TLAST, M_AXIS_TDATA });

	always @(*)
	if (!i_reset && (!tx_valid || !tx_last))
		assert(tx_fill == rx_fill);
	// }}}

	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// "Careless" assumptions
	// {{{
	////////////////////////////////////////////////////////////////////////
	//
	//

	always @(posedge i_clk)
	if ($past(M_AXIS_TVALID && !M_AXIS_TREADY)
			&& $past(M_AXIS_TVALID && !M_AXIS_TREADY, 1)
			&& $past(M_AXIS_TVALID && !M_AXIS_TREADY, 2)
			&& $past(M_AXIS_TVALID && !M_AXIS_TREADY, 3)
			&& $past(M_AXIS_TVALID && !M_AXIS_TREADY, 4))
		assume(M_AXIS_TREADY);
	// }}}
// }}}
endmodule
