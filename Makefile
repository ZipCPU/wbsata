# Master Makefile for WBSATA project
# This Makefile coordinates all simulation and verification tasks

# Default target
all: create_dirs cpp_sim formal verilog_sim

# Directory paths
BENCH_DIR := bench
CPP_DIR := $(BENCH_DIR)/cpp
FORMAL_DIR := $(BENCH_DIR)/formal
VERILOG_DIR := $(BENCH_DIR)/verilog

# Build artifacts
BUILD_DIR := build
REPORT_DIR := $(BUILD_DIR)/reports
LOG_DIR := $(BUILD_DIR)/logs

# Create necessary directories
create_dirs:
	@mkdir -p $(BUILD_DIR) $(REPORT_DIR) $(LOG_DIR)

# C++ Simulation
cpp_sim: create_dirs
	@echo "Running C++ simulation..."
	@cd $(CPP_DIR) && $(MAKE) clean && $(MAKE) run > ../../$(LOG_DIR)/cpp_sim.log 2>&1
	@if [ $$? -eq 0 ]; then \
		echo "C++ simulation PASSED" > $(REPORT_DIR)/cpp_sim.result; \
	else \
		echo "C++ simulation FAILED" > $(REPORT_DIR)/cpp_sim.result; \
		exit 1; \
	fi

# Formal Verification
formal: create_dirs
	@echo "Running formal verification..."
	@cd $(FORMAL_DIR) && $(MAKE) clean && $(MAKE) all > ../../$(LOG_DIR)/formal.log 2>&1
	@if [ $$? -eq 0 ]; then \
		echo "Formal verification PASSED" > $(REPORT_DIR)/formal.result; \
	else \
		echo "Formal verification FAILED" > $(REPORT_DIR)/formal.result; \
		exit 1; \
	fi

# Verilog Simulation
verilog_sim: create_dirs
	@echo "Running Verilog simulation..."
	@cd $(VERILOG_DIR) && perl sim_run.pl vivado all > ../../$(LOG_DIR)/verilog_sim.log 2>&1
	@if [ $$? -eq 0 ]; then \
		echo "Verilog simulation PASSED" > $(REPORT_DIR)/verilog_sim.result; \
	else \
		echo "Verilog simulation FAILED" > $(REPORT_DIR)/verilog_sim.result; \
		exit 1; \
	fi

# Generate summary report
report:
	@echo "=== Simulation Summary ==="
	@echo "C++ Simulation: $$(cat $(REPORT_DIR)/cpp_sim.result)"
	@echo "Formal Verification: $$(cat $(REPORT_DIR)/formal.result)"
	@echo "Verilog Simulation: $$(cat $(REPORT_DIR)/verilog_sim.result)"

# Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@cd $(CPP_DIR) && $(MAKE) clean
	@cd $(FORMAL_DIR) && $(MAKE) clean
	@cd $(VERILOG_DIR) && $(MAKE) clean

# Help target
help:
	@echo "Available targets:"
	@echo "  all            - Run all simulations"
	@echo "  cpp_sim        - Run C++ simulation"
	@echo "  formal         - Run formal verification"
	@echo "  verilog_sim    - Run Verilog simulation"
	@echo "  report         - Generate summary report"
	@echo "  clean          - Clean all build artifacts"
	@echo "  help           - Show this help message"

.PHONY: all cpp_sim formal verilog_sim report clean help 