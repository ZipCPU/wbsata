////////////////////////////////////////////////////////////////////////////////
//
// Filename:	satatb_symdet.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Recovers the SATA clock from the symbol stream.  The algorithm
//		is cheap and simple, and ... won't work outside of a simulation
//	context.  It works by looking for two close clock edges, "measuring"
//	the distance between them, and then locking to the second edge.  It
//	depends upon a sufficient number of close edges to work.
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
`timescale 1ns/1ps
// }}}
module	satatb_symdet #(
		parameter	OVERSAMPLE = 4
	) (
		input	wire	i_reset,
		input	wire	i_rx_data,
		output	wire	o_rxclk
	);

	// Local declarations
	// {{{
	parameter	realtime	NOMINAL_BAUD = 1000.0/1500.0;
	realtime	baud_period = NOMINAL_BAUD;
	realtime	prise, pfall, nextedge = 0;

	wire	dlybit, autoprod;
	reg	clkgate, rxclk;
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Generate a cyclic autocorrelation in autoprod
	// {{{

	// This follows from Gardner's work, taking the autocorrelation of the
	// input times itself delayed by a quarter period.  The result will be
	// a '1' any time there's a change between adjacent bits.
	//
	// This change will be detected as soon as the bits become valid, and
	// will remain valid until the bits are no longer valid (or equal).
	// The correct sample time will be halfway through the period of
	// autoprod.  autoprod is guaranteed to go to zero between bits, from
	// sometime after the middle of the baud interval until sometime before
	// the middle of the next baud interval where things change.
	//

	assign	dlybit = #(NOMINAL_BAUD / 2.0) (i_rx_data === 1'b1);
	assign	autoprod = (dlybit === 1'b1) ^ (i_rx_data === 1'b1);
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Find the middle of a baud interval
	// {{{

	// Lock the next rising edge of the next rxclk to the middle of
	// a buad interval

	always @(posedge autoprod)
		prise = $time;

	always @(negedge autoprod)
	begin
		pfall = $time;
		if (pfall > prise && pfall - prise <= 3.0*NOMINAL_BAUD/4.0)
			pcenter = prise + (pfall - prise)/2;

		if (pfall - prise < NOMINAL_BAUD/2.0)
			rxclk <= #(NOMINAL_BAUD/2.0 - (pfall - prise)/2) 1'b0;
		else
			rxclk <= 0;

		// Center the rise of the next clock on the middle of this
		// baud interval
		rxclk <= #(NOMINAL_BAUD - (pfall - prise)/2) 1'b1;

		// Note the time of lock, lest rxclk rise early (in the next
		// block ...)
		nextedge = $time + (NOMINAL_BAUD - (pfall - prise)/2);
	end
	// }}}

	initial	rxclk = 0;
	always @(posedge rxclk)
	begin
		// Schedule the clock to fall and then rise again.
		//
		if(($time < nextedge)&&((nextedge - $time) < 0.5*NOMINAL_BAUD))
		begin
			// We rose too early.  The "official" nextedge hasn't
			// happened yet.  Lock to it anyway.
			rxclk <= #((nextedge-$time) + baud_period/2.0) 0;
			rxclk <= #((nextedge-$time) + baud_period) 1;
			//
			// else ... we can't rise too late.  If we are locked
			// and scheduled to rise, and we re-lock on a transition
			// that tells us to rise earlier than we expected, then
			// rxclk *will* rise at that time and we'll maintain
			// our lock like normal below.  It might be told to rise
			// twice, but ... as long as the two times are within
			// a half-baud of each other, it will only actually
			// rise once--which is what we want.
		end else begin
			// Just maintain our last lock
			rxclk <= #(baud_period/2.0) 0;
			rxclk <= #(baud_period/2.0) 1;
		end
	end

	initial	clkgate = 0;
	always @(*)
	if (!rxclk)
		clkgate = !i_reset;

	assign	o_rxclk = rxclk && clkgate;
endmodule
