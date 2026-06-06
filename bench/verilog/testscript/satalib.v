////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/verilog/testscript/satalib.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	A library of functions to be used as helpers when writing
//		test scripts.
//
// Creator:
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2025, Gisselquist Technology, LLC
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
localparam	[ADDRESS_WIDTH-1:0]
                ADDR_CMD      = SATA_ADDR + 0,
                ADDR_LBALO    = SATA_ADDR + 4,
                ADDR_LBAHI    = SATA_ADDR + 8,
                ADDR_COUNT    = SATA_ADDR + 12,
                ADDR_LO       = SATA_ADDR + 24,
                ADDR_HI       = SATA_ADDR + 28,
                ADDR_SATAPHY  = DRP_ADDR + 0,
				ADDR_MEM	  = MEM_ADDR;

localparam [7:0] FIS_TYPE_REG_H2D  = 8'h27,	// Host to Device Register
		FIS_TYPE_REG_D2H   = 8'h34,	// Device to Host Register
		FIS_TYPE_DMA_ACT   = 8'h39,	// DMA Activate
		FIS_TYPE_DMA_SETUP = 8'h41,	// DMA Command Setup
		FIS_TYPE_PIO       = 8'h5F,	// PIO Setup
		FIS_TYPE_DATA      = 8'h46,	// Data FIS
		FIS_TYPE_BIST      = 8'h58,	// BIST Activate
		FIS_TYPE_SETBITS   = 8'hA1,	// Set Device Bits
		FIS_TYPE_VENDOR    = 8'hC7;	// Vendor Specific

localparam [7:0] CMD_SET_DATETIME = 8'h77;
localparam [7:0] CMD_WRITE_DMA = 8'hCA;      // Write DMA command code
localparam [7:0] CMD_READ_DMA = 8'hC8;       // Read DMA command code
localparam [7:0] CMD_READ_BUFFER = 8'hE4;    // Read Buffer command code
localparam [7:0] CMD_WRITE_BUFFER = 8'hE8;   // Write Buffer command code

localparam BYTES_PER_SECTOR = 512;
localparam READ_BUF_ADDR = ADDR_MEM + (4 * BYTES_PER_SECTOR);	// Random place from mem

task wait_response();
begin
	$display("Waiting for response...");
	// #10;
	wait(sata_int);
	$display("Response received.");
end endtask

task	sata_set_time(input [47:0] timestamp);
	reg	[31:0]	status;
begin
	u_bfm.writeio(ADDR_COUNT, 32'h0);
	u_bfm.writeio(ADDR_LBAHI, { 8'h0, timestamp[47:24] });
	u_bfm.writeio(ADDR_LBALO, { 8'h0, timestamp[23: 0] });
	u_bfm.writeio(ADDR_CMD,   { 8'h0, CMD_SET_DATETIME, 8'h80,
			FIS_TYPE_REG_H2D });

	wait(sata_int);
	u_bfm.readio(ADDR_CMD, status);

	if (status !== 32'h00_77_00_34)
	begin
		error_flag = 1'b1;
		$display("SET DATE & TIME EXT command failed with status 0x%08x", status);
	end
end endtask

task sata_write_dma(input [27:0] lba, input [7:0] count, input [31:0] buffer_addr);
	reg [31:0] status;
begin
	// In 28-bit addressing, the highest 4 bits go into bits [3:0] of the device register
	// and the remaining 24 bits are in LBALO
	u_bfm.writeio(ADDR_LBAHI, 32'h0);  // Upper bits not used in standard command
	u_bfm.writeio(ADDR_LBALO, {8'h0, lba[23:0]});

	// Set up count (number of sectors)
	u_bfm.writeio(ADDR_COUNT, {24'h0, count});

	// Set up DMA buffer address
	u_bfm.writeio(ADDR_LO, buffer_addr); // Lower 32 bits of buffer address
	u_bfm.writeio(ADDR_HI, 32'h0);       // Upper 32 bits of buffer address (usually 0)

	// Send the Write DMA command
	// Device register format: 0x40 | LBA[27:24]
	// 0x40 = 01000000b - bit 6 set for LBA mode
	$display("HOST: Sending WRITE DMA command to LBA=%0h, count=%0d, buffer=%0h", lba, count, buffer_addr);
	u_bfm.writeio(ADDR_CMD, {8'h0, CMD_WRITE_DMA, 8'h40 | lba[27:24], FIS_TYPE_REG_H2D});

	// Wait for DMA completion interrupt
	$display("HOST: Waiting for WRITE DMA completion...");
	wait(sata_int);
	
	// Check command status
	u_bfm.readio(ADDR_CMD, status);

	// Check for success - status format should be: {features, command, device, FIS type}
	// Looking for: features=0, command without busy bit, device=0, FIS_TYPE_REG_D2H
	if ((status & 32'hFF_80_00_FF) !== 32'h00_00_00_34)
	begin
		error_flag = 1'b1;
		$display("WRITE DMA command failed with status 0x%08x", status);
		$display("  - Features: 0x%02x", status[31:24]);
		$display("  - Command: 0x%02x", status[23:16]);
		$display("  - Device: 0x%02x", status[15:8]);
		$display("  - FIS type: 0x%02x (expected 0x34)", status[7:0]);
	end
	else
		$display("WRITE DMA command completed successfully");
end endtask

task sata_read_dma(input [27:0] lba, input [7:0] count, input [31:0] buffer_addr);
	reg [31:0] status;
begin
	// Set up LBA (Logical Block Address)
	u_bfm.writeio(ADDR_LBAHI, 32'h0);  // Upper bits not used in standard command
	u_bfm.writeio(ADDR_LBALO, {8'h0, lba[23:0]});
	
	// Set up count (number of sectors)
	u_bfm.writeio(ADDR_COUNT, {24'h0, count});
	
	// Set up DMA buffer address
	u_bfm.writeio(ADDR_LO, buffer_addr);
	u_bfm.writeio(ADDR_HI, 32'h0);
	
	// Send READ DMA command
	$display("HOST: Sending READ DMA command from LBA=%0h, count=%0d, buffer=%0h", lba, count, buffer_addr);
	u_bfm.writeio(ADDR_CMD, {8'h0, CMD_READ_DMA, 8'h40 | lba[27:24], FIS_TYPE_REG_H2D});
	
	// Wait for DMA completion interrupt
	$display("HOST: Waiting for READ DMA completion...");
	wait(sata_int);
	
	// Check command status
	u_bfm.readio(ADDR_CMD, status);
	
	if ((status & 32'hFF_80_00_FF) !== 32'h00_00_00_34)
	begin
		error_flag = 1'b1;
		$display("HOST: READ DMA command failed with status 0x%08x", status);
		$display("  - Features: 0x%02x", status[31:24]);
		$display("  - Command: 0x%02x", status[23:16]);
		$display("  - Device: 0x%02x", status[15:8]);
		$display("  - FIS type: 0x%02x (expected 0x34)", status[7:0]);
	end
	else
		$display("HOST: READ DMA command completed successfully");
end endtask

// Additional helper to fill memory buffer with test data pattern
task fill_dma_buffer(input [31:0] buffer_addr, input [15:0] length_in_bytes);
	reg [31:0] data_pattern;
	integer i;
begin
	$display("HOST: Filling DMA buffer at %0h with test pattern (%0d bytes)", buffer_addr, length_in_bytes);
	
	for (i = 0; i < length_in_bytes; i = i + 4) begin
		// Create a recognizable pattern
		data_pattern = i;
		u_bfm.writeio(buffer_addr[ADDRESS_WIDTH-1:0] + i, data_pattern);
	end
end endtask

// Additional helper to verify memory buffer contains expected data
task verify_dma_buffer(input [31:0] src_addr, input [31:0] dest_addr, input [15:0] length_in_bytes);
	reg [31:0] src_data, dest_data;
	integer i;
	reg mismatch;
begin
	$display("HOST: Verifying data between %0h and %0h (%0d bytes)", src_addr, dest_addr, length_in_bytes);
	
	mismatch = 0;
	for (i = 0; i < length_in_bytes; i = i + 4) begin
		u_bfm.readio(src_addr + i, src_data);
		u_bfm.readio(dest_addr + i, dest_data);
		
		if (src_data !== dest_data) begin
			$display("HOST: Data mismatch at offset %0d: Expected %0h, Got %0h", i, src_data, dest_data);
			mismatch = 1;
		end
	end
	
	if (mismatch)
		$display("HOST: DMA data verification FAILED");
	else
		$display("HOST: DMA data verification PASSED");
end endtask

// Example test procedure for a complete DMA write/read test
// 1-) fill_dma_buffer   -> Fills system memory at TEST_BUFFER with test pattern
// 2-) sata_write_dma    -> Transfers data from system memory to SATA device
//							[Device should send DMA ACTIVATION]
// 						    [Data now stored on SATA device at specified LBA]
// 3-) sata_read_dma     -> Transfers data from SATA device back to a different memory location
// 4-) verify_dma_buffer -> Compares original and read-back data
task test_dma_write_read(input [27:0] lba, input [7:0] count);
begin
	// Fill write buffer with pattern
	fill_dma_buffer(ADDR_MEM, count * BYTES_PER_SECTOR);
	#1000;

	// Write data to device
	sata_write_dma(lba, count, ADDR_MEM);
	#1000;

	// Read data back to a different buffer
	sata_read_dma(lba, count, READ_BUF_ADDR);
	#1000;

	// Verify the data matches
	verify_dma_buffer(ADDR_MEM, READ_BUF_ADDR, count * BYTES_PER_SECTOR);

	$display("\n=== DMA Test Complete ===\n");
end endtask

// PIO Write Buffer - Write data to device's buffer using PIO mode
task sata_write_buffer(input [31:0] buffer_addr, input [15:0] sector_count);
    reg [31:0] status;
begin
    // Set up sector count (number of 512-byte blocks to write)
    u_bfm.writeio(ADDR_COUNT, {16'h0, sector_count});
    
    // Set up buffer address in system memory containing the data
    u_bfm.writeio(ADDR_LO, buffer_addr);
    u_bfm.writeio(ADDR_HI, 32'h0);
    
    // Send WRITE BUFFER command - this is a PIO data-out command
    $display("HOST: Sending WRITE BUFFER command for %0d sectors from buffer %0h", sector_count, buffer_addr);
    u_bfm.writeio(ADDR_CMD, {8'h0, CMD_WRITE_BUFFER, 8'h40, FIS_TYPE_REG_H2D});
    
    // Wait for PIO completion interrupt
    $display("HOST: Waiting for WRITE BUFFER completion...");
    wait(sata_int);
    
    // Check command status
    u_bfm.readio(ADDR_CMD, status);
    
    if ((status & 32'hFF_80_00_FF) !== 32'h00_00_00_34)
    begin
        error_flag = 1'b1;
        $display("HOST: WRITE BUFFER command failed with status 0x%08x", status);
        $display("  - Features: 0x%02x", status[31:24]);
        $display("  - Command: 0x%02x", status[23:16]);
        $display("  - Device: 0x%02x", status[15:8]);
        $display("  - FIS type: 0x%02x (expected 0x34)", status[7:0]);
    end
    else
        $display("HOST: WRITE BUFFER command completed successfully");
end endtask

// PIO Read Buffer - Read data from device's buffer using PIO mode
task sata_read_buffer(input [31:0] buffer_addr, input [15:0] sector_count);
    reg [31:0] status;
begin
    // Set up sector count (number of 512-byte blocks to read)
    u_bfm.writeio(ADDR_COUNT, {16'h0, sector_count});
    
    // Set up buffer address in system memory where data will be stored
    u_bfm.writeio(ADDR_LO, buffer_addr);
    u_bfm.writeio(ADDR_HI, 32'h0);
    
    // Send READ BUFFER command - this is a PIO data-in command
    $display("HOST: Sending READ BUFFER command for %0d sectors to buffer %0h", sector_count, buffer_addr);
    u_bfm.writeio(ADDR_CMD, {8'h0, CMD_READ_BUFFER, 8'h40, FIS_TYPE_REG_H2D});
    
    // Wait for PIO completion interrupt
    $display("HOST: Waiting for READ BUFFER completion...");
    wait(sata_int);
    
    // Check command status
    u_bfm.readio(ADDR_CMD, status);
    
    if ((status & 32'hFF_80_00_FF) !== 32'h00_00_00_34)
    begin
        error_flag = 1'b1;
        $display("HOST: READ BUFFER command failed with status 0x%08x", status);
        $display("  - Features: 0x%02x", status[31:24]);
        $display("  - Command: 0x%02x", status[23:16]);
        $display("  - Device: 0x%02x", status[15:8]);
        $display("  - FIS type: 0x%02x (expected 0x34)", status[7:0]);
    end
    else
        $display("HOST: READ BUFFER command completed successfully");
end endtask

// Add helper task to test PIO buffer read/write operations
task test_pio_buffer(input [7:0] sector_count);
begin
    // Fill write buffer with pattern
    $display("\n Initializing the buffer with a test pattern...");
    fill_dma_buffer(ADDR_MEM, sector_count * BYTES_PER_SECTOR);
    #1000;

    // Write data to device's buffer
    sata_write_buffer(ADDR_MEM, sector_count);
    #1000;

    // Read data back to a different buffer
    sata_read_buffer(READ_BUF_ADDR, sector_count);
    #1000;

    // Verify the data matches
    $display("\n Verifying the data matches for PIO read/write...");
    verify_dma_buffer(ADDR_MEM, READ_BUF_ADDR, sector_count * BYTES_PER_SECTOR);

    $display("\n=== PIO Buffer Test Complete ===\n");
end endtask
