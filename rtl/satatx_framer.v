////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/satatx_framer.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Simply encapsulates a packet with SOF and EOF primitives.
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
`timescale	1ns/1ps
// }}}
module	satatx_framer #(
		parameter	[32:0]	P_SOF = 33'h1_7cb5_3737,
					P_EOF = 33'h1_7cb5_d5d5,
					P_HOLD= 33'h1_7caa_d5d5,
		parameter	[0:0]	OPT_LOWPOWER = 1'b0
	) (
		// {{{
		input	wire		S_AXI_ACLK, S_AXI_ARESETN,
		//
		input	wire		S_AXIS_TVALID,
		output	wire		S_AXIS_TREADY,
		input	wire	[31:0]	S_AXIS_TDATA,
		input	wire		S_AXIS_TLAST,
		//
		output	reg		M_AXIS_TVALID,
		input	wire		M_AXIS_TREADY,
		output	reg	[32:0]	M_AXIS_TDATA,
		output	reg		M_AXIS_TLAST
`ifdef	FORMAL
		, output	wire	[1:0]	f_state
`endif
		// }}}
	);

	localparam	S_IDLE = 2'b00, S_DATA = 2'b01, S_EOF = 2'b10;

	reg	[1:0]	fsm_state;

	assign	S_AXIS_TREADY = (!M_AXIS_TVALID || M_AXIS_TREADY)
					&& fsm_state == S_DATA;

	initial	M_AXIS_TVALID = 0;
	always @(posedge S_AXI_ACLK)
	begin
		if (M_AXIS_TREADY)
			M_AXIS_TVALID <= 0;

		case(fsm_state)
		S_IDLE: if (S_AXIS_TVALID && (!M_AXIS_TVALID || M_AXIS_TREADY))
			// {{{
			begin
			fsm_state <= S_DATA;
			M_AXIS_TVALID <= 1;
			M_AXIS_TDATA  <= P_SOF;
			M_AXIS_TLAST  <= 0;
			end
			// }}}
		S_DATA: begin
			// {{{
			M_AXIS_TVALID <= 1;
			if (S_AXIS_TVALID && S_AXIS_TREADY)
			begin
				M_AXIS_TDATA  <= { 1'b0, S_AXIS_TDATA };
				M_AXIS_TLAST  <= 0;

				if (S_AXIS_TLAST)
					fsm_state <= S_EOF;
			end else if (M_AXIS_TREADY)
				M_AXIS_TDATA <= P_HOLD;
			end
			// }}}
		S_EOF: if (M_AXIS_TREADY)
			// {{{
			begin
			fsm_state <= S_IDLE;
			M_AXIS_TVALID <= 1;
			M_AXIS_TDATA  <= P_EOF;
			M_AXIS_TLAST  <= 1;
			end
			// }}}
		default:
			fsm_state <= S_IDLE;
		endcase

		if (!S_AXI_ARESETN)
		begin
			// {{{
			fsm_state <= S_IDLE;
			M_AXIS_TVALID <= 0;
			if (OPT_LOWPOWER)
			begin
				M_AXIS_TDATA <= 0;
				M_AXIS_TLAST <= 0;
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
	assign	f_state = fsm_state;

	always @(*)
	if (S_AXI_ARESETN)
	begin
		if (fsm_state == S_DATA || fsm_state == S_EOF)
			assert(M_AXIS_TVALID);

		// if (fsm_state == S_EOF)

		case(fsm_state)
		S_IDLE: begin
			// {{{
			if (M_AXIS_TVALID)
				assert(M_AXIS_TDATA == P_EOF);
			end
			// }}}
		S_DATA: begin
			// {{{
			assert(M_AXIS_TVALID);
			assert(M_AXIS_TDATA != P_EOF);
			if (M_AXIS_TDATA[32])
				assert(M_AXIS_TDATA == P_SOF
						|| M_AXIS_TDATA == P_HOLD);
			end
			// }}}
		S_EOF: begin
			// {{{
			assert(!M_AXIS_TDATA[32]);
			assert(M_AXIS_TVALID);
			end
			// }}}
		default:
			assert(0);
		endcase

		if (M_AXIS_TVALID && M_AXIS_TDATA[32])
		begin
			assert(M_AXIS_TDATA == P_SOF
				|| M_AXIS_TDATA == P_EOF
				|| M_AXIS_TDATA == P_HOLD);
		end
	end
`endif
// }}}
endmodule
