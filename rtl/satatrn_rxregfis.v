module	satatrn_rxregfis #(
		parameter LGFIFO = 4
	) (
		// {{{
		input	wire		i_clk, i_reset,
		input	wire		i_phy_clk, i_phy_reset_n,
		input	wire		i_link_err,
		//
		input	wire		i_valid,
		input	wire	[31:0]	i_data,	// *LITTLE* ENDIAN
		input	wire		i_last,
		//
		output	wire		o_reg_valid,
		output	wire	[31:0]	o_reg_data,
		output	wire		o_reg_last,
		//
		output	reg		o_data_valid,
		output	reg	[31:0]	o_data_data,
		output	reg		o_data_last
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[7:0]	FIS_DATA = 8'h46;
	reg		mid_packet_phy, is_regpacket_phy, afifo_wr_phy,
			is_datapacket_phy;
	reg	[32:0]	afifo_wr_data;
	wire		afifo_full, afifo_empty;
	// }}}

	// mid_packet_phy
	// {{{
	always @(posedge i_phy_clk)
	if (!i_phy_reset_n || i_link_err)
		mid_packet_phy <= 1'b0;
	else if (i_valid && !afifo_full)
		mid_packet_phy <= !i_last;
	// }}}

	// is_regpacket_phy
	// {{{
	always @(posedge i_phy_clk)
	if (!i_phy_reset_n || i_link_err)
		is_regpacket_phy <= 1'b0;
	else if (i_valid)
	begin
		if (!mid_packet_phy)
		begin
			is_regpacket_phy <= 1'b1;
			case(i_data[7:0])
			FIS_DATA: is_regpacket_phy <= 1'b0;
			default: begin end
			endcase
		end

		if (i_last)
			is_regpacket_phy <= 1'b0;
	end
	// }}}

	// afifo_wr_phy
	// {{{
	always @(posedge i_clk)
	if (!i_phy_reset_n || i_link_err)
		afifo_wr_phy <= 1'b0;
	else if (i_valid && (is_regpacket_phy || i_data[7:0] != FIS_DATA)
			&& !afifo_full)
		afifo_wr_phy <= 1'b1;
	else
		afifo_wr_phy <= 1'b0;
	// }}}

	// afifo_wr_data
	// {{{
	always @(posedge i_clk)
	if (i_valid && (mid_packet_phy || i_data[7:0] != FIS_DATA))
		afifo_wr_data <= { i_last, i_data };
	// }}}

	// reg_afifo
	// {{{
	afifo #(
		.WIDTH(33), .LGFIFO(LGFIFO)
	) u_reg_afifo (
		.i_wclk(i_phy_clk), .i_wr_reset_n(i_phy_reset_n),
		.i_wr(afifo_wr_phy), .i_wr_data(afifo_wr_data),
			.o_wr_full(afifo_full),
		.i_rclk(i_clk), .i_rd_reset_n(!i_reset),
		.i_rd(!afifo_empty), .o_rd_data({ o_reg_last, o_reg_data }),
			.o_rd_empty(afifo_empty)
	);

	assign	o_reg_valid = !afifo_empty;
	// }}}

	// is_datapacket_phy
	// {{{
	always @(posedge i_phy_clk)
	if (!i_phy_reset_n || i_link_err)
		is_datapacket_phy <= 1'b0;
	else if (i_valid)
	begin
		if (!mid_packet_phy)
		begin
			is_datapacket_phy <= 1'b0;
			case(i_data[7:0])
			FIS_DATA: is_datapacket_phy <= 1'b1;
			default: begin end
			endcase
		end

		if (i_last)
			is_datapacket_phy <= 1'b0;
	end
	// }}}

	// o_data_valid
	// {{{
	always @(posedge i_clk)
	if (!i_phy_reset_n || i_link_err)
		o_data_valid <= 1'b0;
	else
		o_data_valid <= i_valid && is_datapacket_phy;
	// }}}

	// o_data_data, o_data_last
	// {{{
	always @(posedge i_clk)
		{ o_data_last, o_data_data } <= { i_last, i_data };
	// }}}
endmodule
