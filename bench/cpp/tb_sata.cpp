////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/cpp/tb_sata.cpp
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Exercise all of the functionality contained within the Verilog
//		core, from bring up through read to write and read-back.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
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
// Include files
// {{{
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <vector>
#include <iostream>
#include <fstream>

#include <Vsata_controller.h>
#include "testb.h"
#include "wb_tb.h"
#include "satasim.h"
#include "memsim.h"
// }}}

class SATA_TB : public WB_TB<Vsata_controller> {
public:
	SATASIM	*m_sata;
	MEMSIM  *m_mem;
	WB_TB<Vsata_controller>* m_tb;

	uint64_t m_current_lba;
    uint32_t m_sector_count;
    uint64_t m_disk_size;

	// Track basic disk image information
    std::string m_disk_filename;
    std::fstream m_disk_file;

	uint32_t m_dma_addr;

	SATA_TB(const char *filesystem_image) : WB_TB<Vsata_controller>() {
		// {{{
		if (0 != access(filesystem_image, R_OK)) {
			fprintf(stderr, "Cannot open %s for reading\n", filesystem_image);
			exit(EXIT_FAILURE);
		} 
		if (0 != access(filesystem_image, W_OK)) {
			fprintf(stderr, "Cannot open %s for writing\n", filesystem_image);
			exit(EXIT_FAILURE);
		}

		// Initialize DMA address
		m_dma_addr = 0x80100;

		// Initialize MEMSIM for DMA memory operations
		m_mem = new MEMSIM(1024*1024, 10); // 1MB memory with 10-cycle delay
		
		// Initialize SATASIM for disk operations
		m_sata = new SATASIM();
		// m_mem->load(filesystem_image);

		// Initialize other member variables
		m_current_lba = 0;
		m_sector_count = 0;
		m_disk_size = 0;
		m_disk_filename = filesystem_image; // Initialize m_disk_filename

		// Set this testbench as its own testbench reference
		m_tb = this;
		// }}}
	}
	
	virtual ~SATA_TB() {
		delete m_sata;
		delete m_mem;
	}

	Vsata_controller *core(void) {
		return m_core;
	}

	// Override simulator clock callbacks to interact with SATASIM
	virtual	void sim_clk_tick(void) {
		// Call parent's simulation clock callback
		TESTB<Vsata_controller>::sim_clk_tick();

		// RAM to device
		deploy_test_data();
	}
	
	virtual	void sim_rx_clk_tick(void) {
		// Get signals from SATASIM to apply to core
		bool rxphy_cominit, rxphy_comwake, rxphy_elecidle, rxphy_valid;
		bool rxphy_primitive, phy_ready;
		uint64_t rxphy_data;

		// Call parent's simulation RX clock callback
		TESTB<Vsata_controller>::sim_rx_clk_tick();
		
		// Get values from SATASIM
		m_sata->process_rx_signals(rxphy_cominit, rxphy_comwake, rxphy_elecidle, 
		                         rxphy_valid, rxphy_primitive, rxphy_data,
		                         phy_ready);
		
		// Update link layer state machine
		m_sata->link_layer_model();

		// Apply to core
		m_core->i_rxphy_cominit = rxphy_cominit;
		m_core->i_rxphy_comwake = rxphy_comwake;
		m_core->i_rxphy_elecidle = rxphy_elecidle;
		m_core->i_rxphy_valid = rxphy_valid;
		m_core->i_rxphy_data = rxphy_data; // 33-bit value
		m_core->i_phy_ready = phy_ready;
	}
	
	virtual	void sim_tx_clk_tick(void) {
		// Call parent's implementation first
		WB_TB<Vsata_controller>::sim_tx_clk_tick();
		
		// Create local variables to receive output values
		bool txphy_comfinish;
		bool txphy_ready;
		bool oob_done;
		
		// Process OOB signals from controller
		if (!m_core->o_lnk_ready) {
			oob_done = m_sata->process_oob();
			m_sata->set_oob_done(oob_done);
		}

		// Update SATASIM with core signals
		m_sata->process_tx_signals(
		    m_core->i_reset,
		    m_core->o_txphy_cominit,
		    m_core->o_txphy_comwake,
		    m_core->o_txphy_elecidle,
		    m_core->o_txphy_primitive,
		    m_core->o_txphy_data,
		    txphy_comfinish,
		    txphy_ready,
		    m_core->o_lnk_ready
		);
		
		// Apply outputs back to core
		m_core->i_txphy_comfinish = txphy_comfinish;
		m_core->i_txphy_ready = txphy_ready;
	}

	// Add a getter method to access m_time_ps from the parent TESTB class
	uint64_t get_time_ps(void) {
		return m_time_ps;
	}

	// Direct memory access for testing purposes
	void write_memory(uint32_t addr, uint32_t* data, uint32_t count) {
		m_mem->load(addr, (char*)data, count*sizeof(uint32_t));
	}

	void wait(int n) {
		for (int i = 0; i < n; i++)
			tick();
	}

	void reset_controller() {
		// Reset our SATA simulator
		m_sata->reset();

		// Assert reset for 100 cycles at the very start
		m_core->i_reset = 1;
		for (int i = 0; i < 100; i++)
			tick();
		m_core->i_reset = 0;
		tick();
		
		// Print status
		printf("HOST: SATA controller reset complete\n");
	}

	void wait_while_busy(void) {
		// Wait for interrupt indicating operation complete
		int timeout = 10000;
		while(!m_core->o_int && --timeout > 0)
			tick();
			
		if (timeout <= 0)
			printf("ERROR: Timeout waiting for busy to clear\n");
	}

	// Wishbone register read
	uint32_t wb_read_reg(uint32_t addr) {
		if (!m_tb) {
			std::cerr << "Cannot read register: Testbench not set" << std::endl;
			return 0;
		}
		
		return m_tb->wb_read(addr);
	}

	// Wishbone register write
	void wb_write_reg(uint32_t addr, uint32_t data) {
		if (!m_tb) {
			std::cerr << "Cannot write register: Testbench not set" << std::endl;
			return;
		}
		
		m_tb->wb_write(addr, data);
	}

	// Wait for link to be ready
	void wait_while_link_ready(void) {
		int timeout = 10000;
		
		while(!m_core->o_lnk_ready && --timeout > 0)
			tick();
			
		if (timeout <= 0)
			printf("ERROR: Timeout waiting for link ready\n");
		else
			printf("HOST: Link ready\n");
	}

	// Wait for interrupt
	void wait_for_int(void) {
		int timeout = 10000;
		
		while(!m_core->o_int && --timeout > 0)
			tick();
			
		if (timeout <= 0)
			printf("ERROR: Timeout waiting for interrupt\n");
	}

	// SATA Controller pulls data from memory
	void deploy_test_data() {
		// Use MEMSIM::apply to handle the memory transaction
		m_mem->apply(m_core->o_dma_cyc, m_core->o_dma_stb, m_core->o_dma_we,
			m_core->o_dma_addr, &m_core->o_dma_data, m_core->o_dma_sel, 
			m_core->i_dma_stall, m_core->i_dma_ack, &m_core->i_dma_data);
	}

	// Verify data from memory
	bool verify_data(uint32_t w_addr, uint32_t r_addr) {
		bool success = true;
		
		// Verify data directly from memory
		for (uint32_t i = 0; i < SATA_SECTOR_SIZE/4; i++) {
			if (m_mem->operator[](r_addr + i) != m_mem->operator[](w_addr + i)) {
				printf("TB: Data verification FAILED\n");
				printf("TB: Received data[%u] = %08x, Sent data[%u] = %08x\n", 
					i, m_mem->operator[](r_addr + i), i, m_mem->operator[](w_addr + i));
				return false;
			}
		}
		printf("TB: Data verification PASSED\n");
		
		return success;
	}

	// Write received data to disk
	void write_to_disk(uint64_t lba, const uint32_t* data, uint32_t count) {
		// Open disk file for writing
		m_disk_file.open(m_disk_filename, std::ios::binary | std::ios::in | std::ios::out);
		if (!m_disk_file.is_open()) {
			fprintf(stderr, "Failed to open disk image for writing\n");
			return;
		}

		// Calculate file offset (LBA * sector size)
		uint64_t offset = lba * SATA_SECTOR_SIZE;
		m_disk_file.seekp(offset);

		// Write data to disk (count is number of sectors, each sector is 128 words)
		uint32_t words_to_write = count * (SATA_SECTOR_SIZE / 4);  // Convert sectors to words
		for (uint32_t i = 0; i < words_to_write; i++) {
			// Convert each 32-bit word to bytes and write
			uint32_t word = data[i];
			// printf("DEVICE: Writing word %08x to disk\n", word);
			for (int j = 0; j < 4; j++) {
				uint8_t byte = (word >> (j * 8)) & 0xFF;
				m_disk_file.write(reinterpret_cast<char*>(&byte), 1);
			}
		}

		// Close the file
		m_disk_file.close();
	}

	// Read data from disk
	void read_from_disk(uint64_t lba, uint32_t* data, uint32_t count) {
		// Open disk file for reading
		m_disk_file.open(m_disk_filename, std::ios::binary | std::ios::in);
		if (!m_disk_file.is_open()) {
			fprintf(stderr, "Failed to open disk image for reading\n");
			return;
		}

		// Calculate file offset (LBA * sector size)
		uint64_t offset = lba * SATA_SECTOR_SIZE;
		m_disk_file.seekg(offset);

		// Read data from disk (count is number of sectors, each sector is 128 words)
		uint32_t words_to_read = count * (SATA_SECTOR_SIZE / 4);  // Convert sectors to words
		for (uint32_t i = 0; i < words_to_read; i++) {
			uint32_t word = 0;
			// Read 4 bytes to form a 32-bit word
			for (int j = 0; j < 4; j++) {
				uint8_t byte;
				m_disk_file.read(reinterpret_cast<char*>(&byte), 1);
				word |= (byte << (j * 8));
			}
			data[i] = word;
		}

		// Close the file
		m_disk_file.close();
	}

	// Execute DMA write operation
	void dma_write(uint64_t lba, uint32_t count, uint32_t dma_addr) {
		if (!m_core || !m_tb) {
			std::cerr << "Cannot perform DMA write: Core or testbench not set" << std::endl;
			return;
		}

		// Only 28-bit LBA and 8-bit count supported for now
		uint32_t lba24 = (uint32_t)(lba & 0xFFFFFF); // lower 24 bits
		uint32_t lba_hi = 0; // upper bits not used
		uint32_t count8 = count & 0xFF; // lower 8 bits
		
		// Setup Wishbone registers for the DMA write
		wb_write_reg(SATA_LBAHI_ADDR, lba_hi);             // Upper bits
		wb_write_reg(SATA_LBALO_ADDR, lba24);              // Lower 24 bits
		wb_write_reg(SATA_COUNT_ADDR, count8);             // Count
		wb_write_reg(SATA_DMA_ADDR_LO, dma_addr<<2);       // DMA address low
		wb_write_reg(SATA_DMA_ADDR_HI, uint32_t(0));       // DMA address high
		
		// Construct the command FIS word for DMA write
		uint32_t fis_cmd = (0x00 << 24) | (FIS_TYPE_DMA_WRITE << 16) | 
						((0x40 | ((lba >> 24) & 0x0F)) << 8) | FIS_TYPE_REG_H2D;
		wb_write_reg(SATA_CMD_ADDR, fis_cmd);            // Command
		
		// Wait for operation to complete (interrupt)
		wait_for_int();
		
		// Write the received data to disk
		write_to_disk(lba, m_sata->get_received_data(), count);
		
		printf("TB: DMA Write complete: LBA=%llu, Count=%u, DMA Addr=0x%08x\n", 
			(unsigned long long)lba, count, dma_addr);
	}

	// Execute DMA read operation
	void dma_read(uint64_t lba, uint32_t count, uint32_t dma_addr) {
		if (!m_core || !m_tb) {
			std::cerr << "Cannot perform DMA read: Core or testbench not set" << std::endl;
			return;
		}
		
		// Only 28-bit LBA and 8-bit count supported for now
		uint32_t lba24 = (uint32_t)(lba & 0xFFFFFF); // lower 24 bits
		uint32_t lba_hi = 0; // upper bits not used
		uint32_t count8 = count & 0xFF; // lower 8 bits
		
		// Setup Wishbone registers for the DMA read
		wb_write_reg(SATA_LBAHI_ADDR, lba_hi);             // Upper bits
		wb_write_reg(SATA_LBALO_ADDR, lba24);              // Lower 24 bits
		wb_write_reg(SATA_COUNT_ADDR, count8);             // Count
		wb_write_reg(SATA_DMA_ADDR_LO, dma_addr<<2);       // DMA address low
		wb_write_reg(SATA_DMA_ADDR_HI, uint32_t(0));       // DMA address high
		
		// Construct the command FIS word for DMA read
		uint32_t fis_cmd = (0x00 << 24) | (FIS_TYPE_DMA_READ << 16) | 
						((0x40 | ((lba >> 24) & 0x0F)) << 8) | FIS_TYPE_REG_H2D;
		wb_write_reg(SATA_CMD_ADDR, fis_cmd);            // Command

		// Read data from disk
		uint32_t* read_data = new uint32_t[count * (SATA_SECTOR_SIZE/4)];  // Allocate space for all sectors
		read_from_disk(lba, read_data, count);
		m_sata->set_sent_data(read_data);
		
		// Wait for operation to complete (interrupt)
		wait_for_int();
		
		printf("TB: DMA Read complete: LBA=%llu, Count=%u, DMA Addr=0x%08x\n", 
			(unsigned long long)lba, count, dma_addr);
	}

	// Test DMA write and read
	// For DMA Write: Memory (dma_addr) -> SATA Controller -> Disk (LBA)
	// For DMA Read:  Disk (LBA) -> SATA Controller -> Memory (dma_addr)
	bool dma_test(uint32_t lba, uint32_t count, uint32_t dma_addr) {
		uint32_t w_addr = dma_addr;
		uint32_t r_addr = dma_addr + SATA_SECTOR_SIZE;
		uint32_t *test_data = new uint32_t[SATA_SECTOR_SIZE/4];

		// Initialize memory with test pattern
		for (uint32_t i = 0; i < count * (SATA_SECTOR_SIZE/4); i++)
			test_data[i] = 0xA0000000 + i;

		printf("TB: Initialized memory with test pattern\n");
		m_mem->load(w_addr, (char*)&test_data[0], sizeof(uint32_t)*count * SATA_SECTOR_SIZE/4);
		
		// Perform DMA write (RAM to disk via SATA controller)
		printf("TB: Issue DMA Write\n");
		dma_write(lba, count, w_addr);
		
		// Wait some time after DMA write
		wait(1000);
		
		// DMA Read
		printf("TB: Issue DMA Read\n");
		dma_read(lba, count, r_addr);
		
		// Verify read data equals written data
		printf("TB: Verifying read data matches written data...\n");
		bool success = verify_data(w_addr, r_addr);

		delete[] test_data;
		return success;
	}

	// Execute PIO write operation
	void pio_write(uint64_t lba, uint32_t count, uint32_t dma_addr) {
		if (!m_core || !m_tb) {
			std::cerr << "Cannot perform PIO write: Core or testbench not set" << std::endl;
			return;
		}

		// Only 28-bit LBA and 8-bit count supported for now
		uint32_t lba24 = (uint32_t)(lba & 0xFFFFFF); // lower 24 bits
		uint32_t lba_hi = 0; // upper bits not used
		uint32_t count8 = count & 0xFF; // lower 8 bits
		
		// Setup Wishbone registers for the PIO write
		wb_write_reg(SATA_LBAHI_ADDR, lba_hi);             // Upper bits
		wb_write_reg(SATA_LBALO_ADDR, lba24);              // Lower 24 bits
		wb_write_reg(SATA_COUNT_ADDR, count8);             // Count
		wb_write_reg(SATA_DMA_ADDR_LO, dma_addr<<2);       // DMA address low
		wb_write_reg(SATA_DMA_ADDR_HI, uint32_t(0));       // DMA address high
		
		// Construct the command FIS word for PIO write
		uint32_t fis_cmd = (0x00 << 24) | (FIS_TYPE_PIO_WRITE_BUFFER << 16) | 
						((0x40 | ((lba >> 24) & 0x0F)) << 8) | FIS_TYPE_REG_H2D;
		wb_write_reg(SATA_CMD_ADDR, fis_cmd);            // Command

		// Wait for operation to complete (interrupt)
		wait_for_int();

		// Write the received data to disk
		write_to_disk(lba, m_sata->get_received_data(), count);
		
		printf("TB: PIO Write complete: LBA=%llu, Count=%u\n", 
			(unsigned long long)lba, count);
	}

	// Execute PIO read operation
	void pio_read(uint64_t lba, uint32_t count, uint32_t dma_addr) {
		if (!m_core || !m_tb) {
			std::cerr << "Cannot perform PIO read: Core or testbench not set" << std::endl;
			return;
		}
		
		// Only 28-bit LBA and 8-bit count supported for now
		uint32_t lba24 = (uint32_t)(lba & 0xFFFFFF); // lower 24 bits
		uint32_t lba_hi = 0; // upper bits not used
		uint32_t count8 = count & 0xFF; // lower 8 bits
		
		// Setup Wishbone registers for the PIO read
		wb_write_reg(SATA_LBAHI_ADDR, lba_hi);             // Upper bits
		wb_write_reg(SATA_LBALO_ADDR, lba24);              // Lower 24 bits
		wb_write_reg(SATA_COUNT_ADDR, count8);             // Count
		wb_write_reg(SATA_DMA_ADDR_LO, dma_addr<<2);       // DMA address low
		wb_write_reg(SATA_DMA_ADDR_HI, uint32_t(0));       // DMA address high
		
		// Construct the command FIS word for PIO read
		uint32_t fis_cmd = (0x00 << 24) | (FIS_TYPE_PIO_READ_BUFFER << 16) | 
						((0x40 | ((lba >> 24) & 0x0F)) << 8) | FIS_TYPE_REG_H2D;
		wb_write_reg(SATA_CMD_ADDR, fis_cmd);            // Command

		// Read data from disk
		uint32_t* read_data = new uint32_t[count * (SATA_SECTOR_SIZE/4)];  // Allocate space for all sectors
		read_from_disk(lba, read_data, count);
		m_sata->set_sent_data(read_data);

		// Wait for operation to complete (interrupt)
		wait_for_int();
		
		printf("TB: PIO Read complete: LBA=%llu, Count=%u\n", 
			(unsigned long long)lba, count);
	}

	// Test PIO write and read
	bool pio_test(uint32_t lba, uint32_t count, uint32_t dma_addr) {
		uint32_t w_addr = dma_addr;
		uint32_t r_addr = dma_addr + SATA_SECTOR_SIZE;
		uint32_t *test_data = new uint32_t[count * (SATA_SECTOR_SIZE/4)];

		// Initialize test pattern
		for (uint32_t i = 0; i < count * (SATA_SECTOR_SIZE/4); i++)
			test_data[i] = 0xB0000000 + i;

		printf("TB: Initialized test pattern for PIO\n");
		// Load test data at address 0
		m_mem->load(w_addr, (char*)&test_data[0], sizeof(uint32_t)*count * (SATA_SECTOR_SIZE/4));
		
		// Perform PIO write
		printf("TB: Issue PIO Write\n");
		pio_write(lba, count, w_addr);
		
		// Wait some time after PIO write
		wait(1000);
		
		// PIO Read
		printf("TB: Issue PIO Read\n");
		pio_read(lba, count, r_addr);
		
		// Verify read data equals written data
		printf("TB: Verifying PIO read data matches written data...\n");
		bool success = verify_data(w_addr, r_addr);

		delete[] test_data;
		return success;
	}
};

int	main(int argc, char **argv) {
	const char	IMG_FILENAME[] = "sata.img";
	const char	VCD_FILENAME[] = "trace.vcd";
	SATA_TB	tb(IMG_FILENAME);

	// Now open trace and continue with the rest of the test
	tb.opentrace(VCD_FILENAME);

	// Reset the controller
	tb.reset_controller();

	// Wait for link to be ready
	tb.wait_while_link_ready();
	
	// Wait some time after link up
	tb.wait(1000);

	// Test parameters
	uint32_t test_lba = 0;
	uint32_t test_count = 1;
	uint32_t dma_addr = tb.m_dma_addr;
	bool success = false;
	
	// Test DMA operations
	printf("\n=== Testing DMA Operations ===\n");
	success = tb.dma_test(test_lba, test_count, dma_addr);
	if (success)
		printf("DMA TEST SUMMARY: SUCCESS!\n");
	else {
		printf("DMA TEST SUMMARY: FAILED!\n");

		// Exit early, so we can *see* the failed exit status
		exit(EXIT_FAILURE);
	}

	// Wait between tests
	tb.wait(1000);

	// Test PIO operations
	printf("\n=== Testing PIO Operations ===\n");
	success = tb.pio_test(test_lba + SATA_SECTOR_SIZE, test_count, 0); // Use different LBA
	if (success)
		printf("PIO TEST SUMMARY: SUCCESS!\n");
	else {
		printf("PIO TEST SUMMARY: FAILED!\n");

		// Exit early, so we can *see* the failed exit status
		exit(EXIT_FAILURE);
	}


	tb.wait(1000);
		
	return success ? 0 : 1;
}
