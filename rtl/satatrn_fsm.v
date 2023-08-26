////////////////////////////////////////////////////////////////////////////////
//
// Filename:	satatrn_fsm.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Handles FIS processing.  satatrn_route will send things from
//		the RX side to us via an asynchronous FIFO, but now we need
//	to process FIS's here.  My intent is to follow the FIS FSM found in
//	the SATA spec for how to handle the transport layer.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2022-2023, Gisselquist Technology, LLC
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
// }}}
`default_nettype none
module	satatrn_fsm #(
	) (
		input	wire	i_clk, i_reset,
		//
		input	wire		i_fis_valid,
		output	wire		o_fis_ready,
		input	wire	[31:0]	i_fis_data,
		//
		input	wire		i_tx_valid,
		input	wire		o_tx_ready,
		input	wire	[31:0]	i_tx_data,
		//
		output	reg		o_valid,
		input	wire		i_ready,
		output	reg	[31:0]	o_data,
		output	reg		o_last
	);

	always @(posedge i_clk)
	if (i_reset)
	end else case(tran_fsm)
	HT_HOST_IDLE: begin
		// {{{
		fis_addr <= 0;
		if (i_tx_valid)
		begin
			case(i_tx_data[7:0])
			FIS_COMMAND: tran_fsm <= HT_CMDFIS;
			FIS_CONTROL: tran_fsm <= HT_CNTRLFIS;
			FIS_DMASTUP: tran_fsm <= HT_DMASTUPFIS;
			// (??): tran_fsm <= HT_PIOOTRANS2;
			default: tran_fsm <= HT_HOST_IDLE;
			endcase
		end

		if (i_fis_valid)
		begin
			case(i_fis_data[7:0])
			FIS_REGISTER: tran_fsm <= HT_REGFIS;
			FIS_DEVBITS:  tran_fsm <= HT_DB_FIS;
			FIS_DMAACTIVATE: tran_fsm <= HT_DMA_FIS;
			FIS_PIOSETUP:	tran_fsm <= HT_PS_FIS;
			// FIS_BIST: tran_fsm <= HT_DMA_FIS;
			// FIS_DATA: 	// handled elsewhere, we won't get this
			default: tran_fsm <= HT_HOST_IDLE;
			endcase
		end end
		// }}}
	HT_CMDFIS: begin
		// {{{
		// Construct a register - host to device FIS
		o_valid <= 1'b1;
		if (!o_valid || i_ready)
		begin
			fis_addr <= fis_addr + 1;
			case(fis_addr)
			0: o_data <= { features[7:0],command, 8'h80, 8'h27 };
			1: o_data <= { device[7:0], lba[23:0] };
			2: o_data <= { features[15:8], lba[47:24] };
			3: o_data <= { control[7:0], icc[7:0], count[15:0] };
			default:
				o_data <= 32'h0;
			endcase
		end
		if (o_valid && i_ready && fis_addr >= 4)
			o_last <= 1'b1;
		if (o_valid && i_ready && o_last)
		begin
			o_valid <= 0;
			fsm_state <= HT_CMDTRANSTATUS;
		end end
		// }}}
	HT_CTRLFIS: begin
		// {{{
		// Construct a register - host to device FIS
		o_valid <= 1'b1;
		if (!o_valid || i_ready)
		begin
			fis_addr <= fis_addr + 1;
			case(fis_addr)
			0: o_data <= { features[7:0],command, 8'h00, 8'h27 };
			1: o_data <= { device[7:0], lba[23:0] };
			2: o_data <= { features[15:8], lba[47:24] };
			3: o_data <= { control[7:0], icc[7:0], count[15:0] };
			default:
				o_data <= 32'h0;
			endcase
		end
		if (o_valid && i_ready && fis_addr >= 4)
			o_last <= 1'b1;
		if (o_valid && i_ready && o_last)
		begin
			o_valid <= 0;
			fsm_state <= HT_CTRLTRANSTATUS;
		end end
		// }}}
	HT_DMASTUP0:
	HT_CHKTYP:

endmodule
