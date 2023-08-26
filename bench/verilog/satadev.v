////////////////////////////////////////////////////////////////////////////////
//
// Filename:	satadev.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	This is the top level of our Verilog SATA model.  It's designed
//		to act *like* a SATA device enough that we can simulate through
//	(and understand) the GTX transceivers used within the SATA PHY.
//
// State machine:
//	COMRESET: Fig 183, p313
//		Host issues COMRESET
//		  6. data bursts, including inter-burst spacing
//		  Sustained as long as reset is asserted
//		  Started during hardware reset, ened following
//		  Each burst is 160 Gen1 UI's long (106.7ns)
//		  Each interburst idle shall be 480 GEN1 UI's long (320ns)
//		COMRESET detector looks for four consecutive bursts with 320ns
//		  spacing (nominal)
//		Spacing of less than 175ns or greater than 525ns shall
//		  invalidate COMRESET
//		COMRESET is negated by 525ns (or more) silence on the channel
//	COMINIT: Device replies with COMINIT after detecting the release of
//		COMRESET
//	COMWAKE: Host replies with COMWAKE
//		COMWAKE = six bursts of data separated by a bus idle condition
//		Each burst is 160 Gen1 UI long, each interburst idle shall be
//		  160 GEN1 UI's long (106.7ns).  The detector looks for four
//		  consecutive bursts with 106.7ns spacing (nominal)
//		Spacing less than 35ns or greater than 172ns shall invalidate
//		  COMWAKE detector
//	Device sends COMWAKE
//	- Device sends continuous stream of ALIGN at highest supported spead
//		After 54.6us, w/o response, it moves down to the next supported
//		speed
//	- Host responds to device COMWAKE with ...
//		- D10.2 characters at the lowest supported speed.
//		- When it detects ALIGN, it replies with ALIGN at the same speed
//		  Must be able to acquire lock w/in 54.6us (2048 Gen1 DWORD tim)
//		- Host waits for at least 873.8 us (32768 Gen1 DWORD times)
//		  after detecting COMWAKE to receive first ALIGN.  If no ALIGN
//		  is received, the host restarts the power-on sequence
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
module	satadev #(
	) (
		input	wire	i_rx_p, i_rx_n,
		output	wire	o_tx_p, o_tx_n
	);

	reg	devck, devock;
	wire	rx_pad, rx_valid;

	assign	rx_pad = i_rx_p;
	assign	rx_valid = (i_rx_p === 1'b1 && i_rx_n === 1'b0)
				|| (i_rx_p === 1'b0 && i_rx_n === 1'b1);

	
endmodule
