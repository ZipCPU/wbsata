////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	bench/formal/sata_crc_wrapper.v
// {{{
// Project:	Demonstration SONAR project
//
// Purpose:	Composes two CRC modules together, as a means for formally
//		verifying both.  If the design works as intended, values will
//	pass sans modification, and without generating any aborts, between the
//	two modules.  If corruption takes place, however, it should be possible
//	to generate an abort.
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
module	sata_crc_wrapper #(
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
	(* anyconst *)	reg		phy_reliable;
	(* anyseq *)	reg	[31:0]	phy_errors;
	(* anyconst *)	reg		f_ckval;
	(* anyconst *)	reg	[31:0]	f_ckword;
	(* anyconst *)	reg	[31:0]	f_value;
	reg	[31:0]	s_word, m_word, tx_word;

	wire		tx_valid, tx_ready, tx_last;
	wire	[W-1:0]	tx_data;
	wire	[31:0]	tx_crc, rx_crc;
	wire	[1:0]	tx_state;
	wire		rx_rvalid;
	wire	[31:0]	rx_rdata;
	// }}}

	satatx_crc #(
		.OPT_LOWPOWER(OPT_LOWPOWER)
	) tx (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.S_AXIS_TVALID(S_AXIS_TVALID), .S_AXIS_TREADY(S_AXIS_TREADY),
		.S_AXIS_TDATA(S_AXIS_TDATA), .S_AXIS_TLAST(S_AXIS_TLAST),
		//
		.M_AXIS_TVALID(tx_valid), .M_AXIS_TREADY(tx_ready && phy_ready),
		.M_AXIS_TDATA(tx_data), .M_AXIS_TLAST(tx_last),
		//
		.f_crc(tx_crc),
		.f_state(tx_state)
		// }}}
	);

	assign	tx_ready = 1;

	satarx_crc #(
		.OPT_LOWPOWER(OPT_LOWPOWER)
	) rx (
		// {{{
		.S_AXI_ACLK(i_clk), .S_AXI_ARESETN(!i_reset),
		//
		.i_cfg_crc_en(1'b1),
		//
		.S_AXIS_TVALID(tx_valid && phy_ready),
		.S_AXIS_TDATA(tx_data ^ phy_errors),
		.S_AXIS_TLAST(tx_last),
		//
		.M_AXIS_TVALID(M_AXIS_TVALID),
		.M_AXIS_TDATA(M_AXIS_TDATA),
		.M_AXIS_TABORT(M_AXIS_TABORT),
		.M_AXIS_TLAST(M_AXIS_TLAST),
		//
		.f_crc(rx_crc),
		.f_valid(rx_rvalid), .f_data(rx_rdata)
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

	// Inducing errors, verifying !TABORT
	// {{{
	always @(*)
	if (phy_reliable || !tx_valid)
		assume(phy_errors == 0);

	always @(*)
	if (!i_reset && !tx_valid)
		assert(!tx_last);
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
		assert($stable(tx_last));
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
	else if (M_AXIS_TVALID)
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
		assert(tx_word + (tx_valid ? 1:0)
				<= 4096 + ((tx_valid && tx_last) ? 1:0));

	always @(*)
		assert(m_word +((M_AXIS_TVALID && !M_AXIS_TLAST) ? 1:0) < 4096);

	always @(*)
	if (!i_reset && tx_word > 0)
		assert(rx_rvalid);

	always @(posedge i_clk)
	begin
		if (s_word == 0)
		begin
			if (tx_word == 0)
			begin
				assert(!tx_valid && tx_state == 2'b00);
			end else begin
				assert(tx_valid && (tx_state != 2'b00 || tx_last));
			end
		end else begin
			assert(tx_state != 2'b00);
			assert(s_word == tx_word + (tx_valid ? 1:0));
		end

		if (M_AXIS_TVALID && M_AXIS_TLAST)
		begin
			assert(tx_word == 0);
		end else begin
			assert(tx_word == m_word + (rx_rvalid ? 1:0)
						+ (M_AXIS_TVALID ? 1:0));
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

	// Rule #1: No corruption => no packets aborted
	// {{{
	localparam	[31:0]	INITIAL_CRC = 32'h52325032;
	localparam	[31:0]	POLYNOMIAL = 32'h04c1_1db7;
	reg	[31:0]	past_crc;

	always @(posedge i_clk)
	if (tx_valid && tx_ready && phy_ready)
	begin
		past_crc <= tx_crc;
	end

	always @(*)
	if (phy_reliable)
		assert(!M_AXIS_TABORT);

	always @(*)
	if (!i_reset && phy_reliable)
	begin
		if (tx_valid)
		begin
			if (tx_last)
			begin
				assert(rx_crc == tx_data);
			end else if (tx_word == 0)
			begin
				assert(rx_crc == INITIAL_CRC);
			end else begin
				assert(advance_crc(rx_crc, tx_data) == tx_crc);
			end
		end else
			assert(rx_crc == tx_crc);
	end

	always @(*)
	if (!i_reset && s_word == 0 && tx_state != 2'b10)
		assert(tx_crc == INITIAL_CRC);

	// always @(*) if (!i_reset && tx_word > 0 && phy_reliable)
	//	assert(rx_crc == past_crc);

	always @(*)
	if (m_word == 0 && !M_AXIS_TVALID && !rx_rvalid)
		assert(rx_crc == INITIAL_CRC);

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
	// }}}

	// Rule #2: Data in == Data out
	// {{{
	always @(*)
	if (!phy_reliable)
		assume(!f_ckval);

	always @(*)
	if (!i_reset && f_ckval && S_AXIS_TVALID && s_word == f_ckword)
		assume(f_value == S_AXIS_TDATA);

	always @(*)
	if (!i_reset && f_ckval && tx_valid && !tx_last && tx_word == f_ckword)
		assert(f_value == tx_data);

	always @(posedge i_clk)
	if (f_past_valid && !$past(i_reset) && f_ckval)
	begin
		if (rx_rvalid && f_ckword + 1 == tx_word)
		begin
			assert(f_value == rx_rdata);
		end
	end

	always @(*)
	if (!i_reset && f_ckval && M_AXIS_TVALID && m_word == f_ckword)
		assert(f_value == M_AXIS_TDATA);
	// }}}

	// Rule #3: Aborted packets must still be possible
	// {{{
	// Hence, the CRC can detect a corrupted packet
	always @(*)
		cover(!i_reset && M_AXIS_TABORT);
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
	if ($past(tx_valid && !phy_ready) && $past(tx_valid && !phy_ready, 1))
		// && $past(tx_valid && !phy_ready, 2))
	begin
		assume(phy_ready);
	end

	// }}}
// }}}
endmodule
