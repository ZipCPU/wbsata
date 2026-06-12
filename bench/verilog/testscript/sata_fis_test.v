////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/testscript/sata_fis_test.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Test SATA SET DATE & TIME EXT command
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2025-2026, Gisselquist Technology, LLC
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
`include "../testscript/satalib.v"

// Example timestamp value (48 bits)
localparam [47:0] TIMESTAMP = 48'h123456789ABC;  // Example timestamp in milliseconds

task testscript;
begin
	// Wait for SATA controller to initialize
	#1000;

	$display("\n=== HOST: Sending SET DATE & TIME EXT Command ===");
	sata_set_time(TIMESTAMP);

	$display("HOST: SET DATE & TIME EXT test completed");
end endtask 