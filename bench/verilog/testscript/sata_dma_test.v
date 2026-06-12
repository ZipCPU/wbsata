////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/testscript/sata_dma_test.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	DMA operation test for SATA controller
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

// Define DMA write test parameters
localparam [27:0] TEST_LBA = 28'h0000_200;  // Starting LBA for DMA read-write
localparam [7:0]  TEST_COUNT = 8'd1;        // Number of sectors to write

task testscript;
begin
	// Wait for SATA controller to initialize
	#1000;

	// Run a complete DMA write/read test
	$display("\n=== HOST: Starting DMA WRITE/READ Test ===");
	test_dma_write_read(TEST_LBA, TEST_COUNT);

	$display("HOST: SATA DMA Test Complete");
end endtask 