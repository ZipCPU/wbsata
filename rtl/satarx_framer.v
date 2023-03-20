////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	satarx_framer.v
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
// Copyright (C) 2021-2023, Gisselquist Technology, LLC
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
module	satarx_framer #(
		// {{{
		parameter	[32:0]	P_SOF = 33'h1_7cb5_3737,
					P_EOF = 33'h1_7cb5_d5d5,
					P_WTRM= 33'h1_7cb5_5858,
					P_SYNC= 33'h1_7c95_b5b5,
		parameter	[0:0]	OPT_LOWPOWER = 1'b0
		// }}}
	) (
		// {{{
		input	wire		S_AXI_ACLK, S_AXI_ARESETN,
		//
		input	wire		S_AXIS_TVALID,
		input	wire	[32:0]	S_AXIS_TDATA,
		input	wire		S_AXIS_TABORT,
		//
		output	reg		M_AXIS_TVALID,
		output	reg	[31:0]	M_AXIS_TDATA,
		output	reg		M_AXIS_TLAST,
		output	reg		M_AXIS_TABORT
`ifdef	FORMAL
		, output wire		f_rvalid
		, output wire	[31:0]	f_rdata
		, output wire		f_state
`endif
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[0:0]	S_IDLE = 1'b0, S_DATA = 1'b1;
	reg		r_valid, r_state;
	reg	[31:0]	r_data;
	wire		i_primitive;
	// }}}

	assign	i_primitive = S_AXIS_TDATA[32];

	initial	M_AXIS_TVALID = 0;
	always @(posedge S_AXI_ACLK)
	begin
		// M_AXIS_* default values
		// {{{
		M_AXIS_TVALID <= 0;
		M_AXIS_TDATA  <= 0;
		M_AXIS_TLAST  <= 0;
		M_AXIS_TABORT <= 0;
		// }}}

		if (S_AXIS_TVALID)
		begin
			if (!i_primitive)
			begin
				// {{{
				r_valid <= (r_state == S_DATA);
				if (r_state == S_DATA)
				begin
					r_data  <= S_AXIS_TDATA[31:0];

					M_AXIS_TVALID <= r_valid;
					M_AXIS_TDATA  <= r_data;
					if (OPT_LOWPOWER && !r_valid)
						M_AXIS_TDATA <= 0;
				end
				// }}}
			end else case( S_AXIS_TDATA[31:0])
			P_SOF[31:0]: r_state <= S_DATA;
			P_EOF[31:0]: begin
				// {{{
				r_state <= S_IDLE;
				r_valid <= 1'b0;
				r_data  <= 0;

				M_AXIS_TVALID <= r_valid;
				M_AXIS_TDATA  <= r_data;
				M_AXIS_TLAST  <= 1;
				end
				// }}}
			P_WTRM[31:0]: begin
				// {{{
				r_state <= S_IDLE;

				M_AXIS_TVALID <= r_valid;
				if (r_valid)
				begin
					M_AXIS_TDATA  <= 0;
					M_AXIS_TLAST  <= 1;
					M_AXIS_TABORT <= 1;
				end end
				// }}}
			P_SYNC[31:0]: begin
				// {{{
				r_state <= S_IDLE;

				if (r_valid)
				begin
					M_AXIS_TDATA  <= 0;
					M_AXIS_TLAST  <= 1;
					M_AXIS_TABORT <= 1;
				end end
				// }}}
			endcase
		end

		if (S_AXIS_TABORT)
		begin
			// {{{
			M_AXIS_TABORT <= (r_valid);

			r_state       <= S_IDLE;
			r_valid       <= 0;
			M_AXIS_TVALID <= 0;
			// }}}
		end

		if (!S_AXI_ARESETN)
		begin
			// {{{
			r_state <= S_IDLE;
			r_valid <= 0;
			M_AXIS_TVALID <= 0;
			M_AXIS_TABORT <= 0;
			if (OPT_LOWPOWER)
			begin
				r_data <= 0;
				M_AXIS_TDATA  <= 0;
				M_AXIS_TLAST  <= 0;
			end
			// }}}
		end
	end
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
	assign	f_rvalid = r_valid;
	assign	f_rdata  = r_data;
	assign	f_state  = r_state;

	always @(*)
	if (S_AXI_ARESETN && r_state == S_IDLE)
		assert(!r_valid);
`endif
// }}}
endmodule
