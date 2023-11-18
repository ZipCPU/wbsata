module	satatrn_txarb #(
		parameter	LGAFIFO = 4,
		parameter [0:0]	OPT_LOWPOWER = 1'b0
	) (
		// {{{
		input	wire		i_clk, i_reset,
		input	wire		i_phy_clk, i_phy_reset_n,
		//
		input	wire		i_reg_valid,
		output	wire		o_reg_ready,
		input	wire	[31:0]	i_reg_data,
		input	wire		i_reg_last,
		//
		input	wire		i_txgate,
		//
		input	wire		i_data_valid,
		output	wire		o_data_ready,
		input	wire	[31:0]	i_data_data,
		input	wire		i_data_last,
		//
		output	reg		o_valid,
		input	wire		i_ready,
		output	reg	[31:0]	o_data,
		output	reg		o_last
		// }}}
	);

	localparam	FIS_DATA = 8'h46;

	reg		mid_data_packet, mid_reg_packet;
	wire		regfifo_full, regfifo_empty, regfifo_last,regfifo_ready;
	wire	[31:0]	regfifo_data;
	reg		txgate_phy, txgate_xpipe;

	// txgate_phy, txgate_xpipe
	// {{{
	always @(posedge i_phy_clk)
	if (!i_phy_reset_n)
		{ txgate_phy, txgate_xpipe } <= 0;
	else
		{ txgate_phy, txgate_xpipe } <= { txgate_xpipe, i_txgate };
	// }}}

	// Move the FIS data to the PHY clock
	// {{{
	afifo #(
		.WIDTH(1+32), .LGFIFO(LGAFIFO)
	) u_reg_afifo (
		.i_wclk(i_clk), .i_wr_reset_n(!i_reset),
		.i_wr(i_reg_valid), .i_wr_data({ i_reg_last, i_reg_data }),
			.o_wr_full(regfifo_full),
		//
		.i_rclk(i_phy_clk), .i_rd_reset_n(i_phy_reset_n),
		.i_rd(regfifo_ready),.o_rd_data({ regfifo_last, regfifo_data }),
			.o_rd_empty(regfifo_empty)
	);

	assign	o_reg_ready = !regfifo_full;
	// }}}

	// mid_data_packet
	// {{{
	always @(posedge i_phy_clk)
	if (!i_phy_reset_n)
		mid_data_packet <= 1'b0;
	else if (i_data_valid && o_data_ready)
		mid_data_packet <= !i_data_last;
	else if (!mid_reg_packet && !mid_data_packet && (!o_valid || i_ready)
				&& txgate_phy && i_data_valid)
		mid_data_packet <= 1'b1;
	// }}}

	// mid_reg_packet
	// {{{
	always @(posedge i_phy_clk)
	if (!i_phy_reset_n)
		mid_reg_packet <= 1'b0;
	else if (!regfifo_empty && regfifo_ready)
		mid_reg_packet <= !regfifo_last;
	// }}}

	// o_valid
	// {{{
	always @(posedge i_phy_clk)
	if (!i_phy_reset_n)
		o_valid <= 1'b0;
	else if (!o_valid || i_ready)
	begin
		if (mid_reg_packet)
			o_valid <= !regfifo_empty;
		else if (mid_data_packet)
			o_valid <= i_data_valid;
		else if (txgate_phy && i_data_valid)
			o_valid <= 1'b1;
		else if (!regfifo_empty)
			o_valid <= 1'b1;
		else
			o_valid <= 1'b0;
	end
	// }}}

	// o_data, o_last
	// {{{
	always @(posedge i_clk)
	if (!o_valid || i_ready)
	begin
		if (mid_data_packet)
			{ o_last, o_data } <= { i_data_last, i_data_data };
		else if (mid_reg_packet)
			{ o_last, o_data } <= { i_reg_last, i_reg_data };
		else if (txgate_phy && i_data_valid)
			{ o_last, o_data } <= { 1'b0, 24'h0, FIS_DATA };
		else if (!regfifo_empty || !OPT_LOWPOWER)
			{ o_last, o_data } <= { regfifo_last, regfifo_data };
		else
			{ o_last, o_data } <= 33'h0;
	end
	// }}}

	assign	regfifo_ready  = (!o_valid || i_ready) && (mid_reg_packet
				|| (!mid_data_packet
				&& (!txgate_phy || !i_data_valid)));
	assign	o_data_ready = mid_data_packet && (!o_valid || i_ready);
endmodule
