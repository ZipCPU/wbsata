////////////////////////////////////////////////////////////////////////////////
//
// Filename:	satatrn_route.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Routes incoming SATA packets to one of two destination, either
//		the DMA (for data) or to a transport layer FIS processor/FSM.
//	Packets are routed based upon FIS type.  Data FISs will go to the
//	DMA and have their bytes reversed so they are big-endian.  Other
//	FISs will be forwarded to the FIS processors/FSM.
//
// FUTURE:
//	May also need to consider a debug option where FISs that don't match
//	either data or shadow register writes are still written to memory
//	(somewhere) for debug purposes.
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
`default_nettype none
// }}}
module	satatrn_route #(
		parameter [0:0]	OPT_LITTLE_ENDIAN = 1'b0
	) (
		// {{{
		input	wire		i_clk, i_reset,
		// The incoming data packet
		// {{{
		input	wire		s_valid,
		output	wire		s_ready,
		input	wire	[31:0]	s_data,
		input	wire		s_last,
		input	wire		s_abort,
		// }}}
		// Writes to the shadow register file
		// {{{
		// NO ABORTs!  All writes to shadow register file must wait
		//	until s_valid && s_last && !s_abort before being
		//	written, they can then be written in a big burst--all
		//	at once
		output	reg		o_sr_valid,	// == active sr access
		input	wire		i_sr_ready,
		output	reg	[31:0]	o_sr_data,
		output	reg		o_sr_last,
		// }}}
		// Writes to the DMA
		// {{{
		input	wire		i_dma_en,	// Enable DMA
		//
		output	wire		o_dma_valid,
		input	wire		i_dma_ready,
		output	wire	[31:0]	o_dma_data,
		output	wire		o_dma_last,
		output	wire		o_dma_abort,
		// }}}
		// Control words
		// {{{
		// We don't really have a PIO activate command here, since
		// *EVERYTHING* in our controller uses the DMA.  Hence, a
		// PIO setup command will also activate the DMA in the same
		// fashion.
		output	reg		o_dma_activate
		// }}}
		// }}}
	);

	// Local declarations
	// {{{
	localparam	[1:0]	PKT_SHADOW  = 2'b00,
				PKT_DATA    = 2'b01,
				PKT_IGNORED = 2'b11;

	// My notes say I only need to handle the following 6 FIS types
	localparam	[7:0]	FIS_REGISTER		= 8'h27, // Good
				FIS_DMAACTIVATE		= 8'h39, // Good
				FIS_DMASETUP		= 8'h41,	// ?
				FIS_DATA		= 8'h46, // Good
				FIS_PIOSETUP		= 8'h5f, // ??
				FIS_SETDEVBITS		= 8'ha1; // Good

	reg		pkt_start;
	reg	[1:0]	pkt_type;
	reg		update_shadow;
	//		update_abort;
	reg	[31:0]	update_data;
	reg	[2:0]	update_addr;
	reg	[3:0]	updated_count;	// One more bit than sr_addr

	reg		dma_valid, dma_last, dma_abort;
	reg	[31:0]	dma_data;

	reg	[2:0]	sr_addr;

	reg	[31:0]	fis_mem	[0:7];
	reg	[7:0]	active_fis;
	// }}}

	// pkt_start: Will the next incoming word begin a packet?
	// {{{
	always @(posedge i_clk)
	if (i_reset)
		pkt_start <= 1'b1;
	else if (s_valid && s_ready && s_last)
		pkt_start <= 1'b1;
	else if (s_abort && (!s_valid || s_ready))
		pkt_start <= 1'b1;
	else if (s_valid && s_ready)
		pkt_start <= 1'b0;
	// }}}

	// active_fis
	// {{{
	always @(posedge i_clk)
	if (i_reset)
		active_fis <= 8'h00;
	else if (s_valid && s_ready && pkt_start)
		active_fis <= s_data[7:0];
	// }}}

	// update_*, dma_*, packet processing state machine
	// {{{
	always @(posedge i_clk)
	if (i_reset)
	begin
		// {{{
		pkt_type <= PKT_IGNORED;
		update_shadow <= 1'b1;
		update_addr   <= 3'h0;
		update_data   <= 32'h0;
		// update_abort <= 1'b0;

		dma_valid <= 1'b0;
		dma_last  <= 1'b0;
		dma_abort <= 1'b0;
		dma_data  <= 32'h0;
		// }}}
	end else if (s_abort && (!s_valid || s_ready))
	begin
		// {{{
		update_shadow <= 1'b1;
		update_addr   <= 3'h0;
		update_data   <= 32'h0;
		// update_abort  <= 1'b0;

		// if (pkt_type == PKT_SHADOW) update_abort <= 1'b1;

		dma_valid <= o_dma_valid && !i_dma_ready;
		dma_last  <= 1'b0;
		dma_abort <= (pkt_type == PKT_DATA);
		dma_data  <= 32'h0;
		// }}}
	end else if (s_valid && s_ready)
	begin
		// {{{
		update_shadow <= 1'b1;
		update_addr   <= 3'h0;
		update_data   <= 32'h0;
		// update_abort  <= 1'b0;

		if (!o_dma_valid || i_dma_ready)
		begin
			dma_valid <= 1'b0;
			dma_last  <= 1'b0;
			dma_abort <= 1'b0;
			dma_data  <= 32'h0;
		end

		if (pkt_start)
		begin
			case(s_data[7:0])
			FIS_REGISTER, FIS_PIOSETUP, FIS_SETDEVBITS,
				FIS_DMASETUP: begin
				// {{{
				pkt_type <= PKT_SHADOW;
				update_shadow <= 1'b1;
				update_addr   <= 3'h0;
				update_data   <= s_data;
				end
				// }}}
			FIS_DATA:
				pkt_type <= (i_dma_en) ? PKT_DATA : PKT_IGNORED;
			// FIS_DMAACTIVATE		= 8'h39,
			default: pkt_type <= PKT_IGNORED;
			endcase
		end else case(pkt_type)
		PKT_SHADOW: begin
			update_shadow <= 1'b1;
			update_addr   <= update_addr + 1;
			update_data   <= s_data;
			end
		PKT_DATA: begin
			// {{{
			dma_valid <= 1'b1;
			if (!o_dma_valid || i_dma_ready)
			begin
				dma_last  <= s_last;
				dma_abort <= 1'b0;
				if (OPT_LITTLE_ENDIAN)
					dma_data  <= s_data;
				else
					dma_data <= BYTE_REVERSE(s_data);
			end else begin
				dma_abort <= 1'b1;
				pkt_type <= PKT_IGNORED;
			end end
			// }}}
		default: begin end
		endcase

		if (s_last)
			pkt_type <= PKT_IGNORED;
		// }}}
	end else begin
		update_shadow <= 1'b0;
		if (i_dma_ready)
			dma_valid <= 1'b0;
	end

	assign	o_dma_valid = dma_valid;
	assign	o_dma_data  = dma_data;
	assign	o_dma_last  = dma_last;
	assign	o_dma_abort = dma_abort;
	// }}}

	// o_dma_activate
	// {{{
	always @(posedge i_clk)
	if (i_reset)
		o_dma_activate <= 1'b0;
	else if (s_valid && s_ready && s_last && !s_abort)
	begin
		o_dma_activate <= 1'b0;
		if (pkt_start)
			o_dma_activate <= s_data[7:0] == FIS_DMAACTIVATE;
		if (active_fis == FIS_PIOSETUP && pkt_type == PKT_SHADOW
						&& update_addr == 3)
			o_dma_activate <= 1'b1;
	end else
		o_dma_activate <= 1'b0;
	// }}}

	// updated_count
	// {{{
	always @(posedge i_clk)
	if (i_reset)
		updated_count <= 0;
	else if (s_abort)
		updated_count <= 0;
	else if (o_sr_valid && i_sr_ready && o_sr_last)
		updated_count <= 0;
	else if (update_shadow && !updated_count[3])
		updated_count <= update_addr + 1;
	// }}}

	// sr_addr
	// {{{
	always @(posedge i_clk)
	if (i_reset)
		sr_addr <= 0;
	else if (o_sr_valid && i_sr_ready)
	begin
		sr_addr <= sr_addr + 1;
		if (o_sr_last)
			sr_addr <= 0;
	end else if (!o_sr_valid)
	begin
		sr_addr <= 0;

		if (!o_sr_valid && !s_valid && updated_count > 0
				&& pkt_start && !update_shadow)
			sr_addr <= 1;
	end
	// }}}

	// Write to FIS MEM
	// {{{
	always @(posedge i_clk)
	if (update_shadow)
		fis_mem[update_addr] <= update_data;
	// }}}

	// o_sr_data: Read from FIS MEM
	// {{{
	always @(posedge i_clk)
	if (!o_sr_valid || i_sr_ready)
		o_sr_data <= fis_mem[sr_addr];
	// }}}

	// o_sr_valid, o_sr_last
	// {{{
	always @(posedge i_clk)
	if (i_reset)
	begin
		o_sr_valid <= 1'b0;
		o_sr_last  <= 1'b0;
	end else if (!o_sr_valid || i_sr_ready)
	begin
		if (!s_valid && updated_count != 0 && pkt_start
						&& !update_shadow)
		begin
			// Once we've finished receiving a FIS,
			//	!s_valid -- nothing new coming in
			//	updated_count != 0 -- pkt is waiting to push fwd
			//	pkt_start -- Finished the last packet
			//	!update_shadow -- Not still updating due to last
			//		pkt
			// we can forward it on.
			o_sr_valid <= 1'b1;
			o_sr_last  <= (updated_count == 1);
		end else if (o_sr_valid && i_sr_ready)
		begin
			// Once we've started forwarding this
			// FIS, keep going until finished
			o_sr_valid <= !o_sr_last;
			o_sr_last  <= (updated_count == sr_addr + 1);
		end
	end
	// }}}

	function [31:0] BYTE_REVERSE(input [31:0] i_data);
	begin
		BYTE_REVERSE = { i_data[7:0], i_data[15:8], i_data[23:16],
				i_data[31:24] };
	end endfunction

	assign	s_ready = (!o_dma_valid || i_dma_ready)
				&&(!o_sr_valid || i_sr_ready);
endmodule
