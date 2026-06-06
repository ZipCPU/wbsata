#!/bin/perl
################################################################################
##
## Filename:	bench/verilog/sim_run.pl
## {{{
## Project:	A Wishbone SATA controller
##
## Purpose:	Runs one or more of the test cases described in
##		dev_testcases.txt.
##
## Creator:	Dan Gisselquist, Ph.D.
##		Gisselquist Technology, LLC
##
################################################################################
## }}}
## Copyright (C) 2016-2025, Gisselquist Technology, LLC
## {{{
## This file is part of the WBSATA project.
##
## The WBSATA project is a free software (firmware) project: you may
## redistribute it and/or modify it under the terms of  the GNU General Public
## License as published by the Free Software Foundation, either version 3 of
## the License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
## FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
## for more details.
##
## You should have received a copy of the GNU General Public License along
## with this program.  If not, please see <http://www.gnu.org/licenses/> for a
## copy.
## }}}
## License:	GPL, v3, as defined and found on www.gnu.org,
## {{{
##		http://www.gnu.org/licenses/gpl.html
##
################################################################################
##
## }}}
use Cwd;
use File::Which;
$path_cnt = @ARGV;

$filelist = "sim_files.txt";
$testlist = "dev_testcases.txt";
$exefile  = "./devsim";
$linestr  = "----------------------------------------";
$report   = "report.txt";
$wbtoplvl = "satatb_top";
$testd    = "test/";
$vivado   = 1;
# Other potential simulators, such as Icarus or Verilator, don't yet have
# (workable) models for the GTX transceiver, so they aren't (yet) supported
# here.
$vivado_path = which('vivado'); # "/tools/Xilinx/Vivado/2024.1/bin/vivado"; # Path to Vivado executable

if ($vivado_path =~ /vivado$/) {
	print "Vivado install found at $vivado_path\n";
} else {
	print "No Vivado install found\n";
	exit -1;
}

## Usage:
##	perl sim_sim.pl all
##		(Run all tests using the default simulator: Vivado)
##   or
## 	perl sim_sim.pl <testcasename>
##		(Run the given test(s) using the default simulator: Vivado)
##   or
## 	perl sim_sim.pl vivado [all]
##		(Run all tests using Vivado, the "all" argument is optional)
##   or
## 	perl sim_sim.pl vivado <testcasename>
##		(Run given tests using Vivado)
##

## Process arguments
## {{{
$run_all = 0;
print "Debug: Script started with " . scalar(@ARGV) . " arguments: " . join(", ", @ARGV) . "\n";

if ($ARGV[0] eq "") {
	print "No test cases given\n";
	print "Usage:\n";
	print "\tperl sim_run.pl all\n";
	print "\t\tRuns all tests using Vivado (the only supported simulator)\n";
	print "\tperl sim_run.pl vivado [all]\n";
	print "\t\tRuns all tests using Vivado\n";
	print "\tperl sim_run.pl vivado <testname>\n";
	print "\t\tRuns the given tests using Vivado\n";
	exit(-1);
} elsif ($ARGV[0] eq "all") {
	$run_all = 1;
	open(SUM,">> $report");
	print(SUM "\nRunning all tests:\n$linestr\n");
	close SUM;
} elsif(($ARGV[0] eq "vivado") and $ARGV[1] eq "all") {
	$run_all = 1;
	$vivado  = 1;
	print "Debug: Running all tests with Vivado\n";
	open(SUM,">> $report");
	print(SUM "\nRunning all tests:\n$linestr\n");
	close SUM;
} elsif ($ARGV[0] eq "vivado") {
	if (scalar(@ARGV) == 1) {
		$run_all = 1;
		open(SUM,">> $report");
		print(SUM "\nRunning all tests:\n$linestr\n");
		close SUM;
	} else {
		$run_all = 0;
		$vivado  = 1;
		print "Debug: Running specific tests with Vivado: " . join(", ", @ARGV[1..$#ARGV]) . "\n";
		@array = @ARGV;
		splice(@array, 0, 1);
	}
} else {
	## What default simulators are supported??
	@array = @ARGV;
	# print "Debug: Running specific tests with default simulator: " . join(", ", @array) . "\n";
	# print "ERROR: No default simulator specified\n";
	##	Let's not generate an error.  We only support Vivado, so let's
	##	make that the default simulator.
	# print "Recommend: perl sim_run.pl vivado [all|test names]\n";
	# exit(-1);
}
## }}}

## timestamp
## {{{
sub timestamp {
	my $sc, $mn, $hr, $dy, $mo, $yr, $wday, $yday, $isdst;

	($sc,$mn,$hr,$dy,$mo,$yr,$wday,$yday,$isdst)=localtime(time);
	$yr=$yr+1900; $mo=$mo+1;
	$tstamp = sprintf("%04d/%02d/%02d %02d:%02d:%02d",
					$yr,$mo,$dy,$hr,$mn,$sc);
}
## }}}

## simline: Simulate, given a named test configuration
## {{{
sub simline($) {
	my $line = shift;

	my $tstname = "";
	my $args = "";

	# Vivado can't handle include `SCRIPT when running from the GUI, so we
	# instead create a DEFINE to be used anytime we are running from this
	# Perl-based regression running script (as defined by this file,
	# sim_run.pl).
	my $defs = " -DREGRESSION";
	my $parm = "";
	my $cpu_flag = 0;

	my $vcddump=0;
	my $vcdfile="";

	while ($line =~ /^(.*)#.*/) {
		$line = $1;
	} if ($line =~ /^\s*(\S+)\s+(\S+)\s+(\S+)\s+(.*)$/) {
		$tstname = $1;
		$tstcfg  = $2;
		$tstscript = $3;
		$args = $4;
		print "Debug: Parsed 4 components: test=$tstname, config=$tstcfg, script=$tstscript, args=$args\n";
	} elsif ($line =~ /^\s*(\S+)\s+(\S+)\s+(\S+)\s*$/) {
		$tstname = $1;
		$tstcfg  = $2;
		$tstscript = $3;
		$args = "";
		print "Debug: Parsed 3 components: test=$tstname, config=$tstcfg, script=$tstscript\n";
	} else {
		print "Debug: Failed to parse line: $line\n";
		return();
	}

	if ($tstcfg =~ /WB/i) {
		$toplevel = $wbtoplvl;
		$filelist = "sim_files.txt";
		$parm = $parm . " -P$toplevel.OPT_CPU=0 -P$toplevel.MEM_FILE=\\\"\\\"";
		$defs = $defs . " -D$tstscript";  # Pass the test script name as a define
		$cpu_flag = 0;
		print "Debug: Using WB configuration with toplevel=$toplevel and filelist=$filelist\n";
	} else {
		print "Debug: Unknown configuration: $tstcfg\n";
		return();
	}

	if ($tstname eq "") {	## No test
		print "Debug: No test name found\n";
		return();
	} elsif ($vivado > 0) {	## Vivado test support
		## Create and run the test with Vivado
		my $vivado_script = "vivado_sim.tcl";
		open(VS, ">$vivado_script") or die "Cannot create Vivado script: $!";
		print VS "create_project -force tmp_project tmp_project -part xc7a100tcsg324-1\n";
		print VS "set_property target_language Verilog [current_project]\n";
		print "Debug: Created Vivado project script header\n";
		
		# Copy the test script to a local file named testscript.v
		print "Debug: Copying testscript/$tstscript.v to testscript.v\n";
		system("cp testscript/$tstscript.v testscript.v") == 0 
			or die "Failed to copy test script: $!";
		
		# Copy the satalib.v file as well
		print "Debug: Copying testscript/satalib.v to satalib.v\n";
		system("cp testscript/satalib.v satalib.v") == 0
			or die "Failed to copy satalib.v: $!";
		
		# Fix the include path in the copied file
		print "Debug: Fixing include path in testscript.v\n";
		system("sed -i 's/`include \"\\.\\.\\/testscript\\/satalib.v\"/`include \"satalib.v\"/' testscript.v") == 0
			or die "Failed to fix include path: $!";
		
		# Read source files from filelist
		print "Debug: Reading source files from $filelist\n";
		open(FL, $filelist) or die "Cannot open file list: $!";
		my $file_count = 0;
		while(my $src = <FL>) {
			chomp($src);
			next if ($src =~ /^\s*$/);  # Skip empty lines
			next if ($src =~ /^\s*#/);  # Skip comment lines
			$src =~ s/^\s+|\s+$//g;     # Trim whitespace
			
			if ($src) {
				print VS "read_verilog $src\n";
			}
		}
		close(FL);
		
		# Include local testscript.v file instead of the original test script
		print VS "read_verilog testscript.v\n";
		print "Debug: Added local test script: testscript.v\n";
		
		# Properly set up the simulation
		print VS "set_property top $toplevel [current_fileset]\n";
		print VS "update_compile_order -fileset sources_1\n";
		print VS "set_property SOURCE_SET sources_1 [get_filesets sim_1]\n";
		print VS "set_property top $toplevel [get_filesets sim_1]\n";
		print VS "update_compile_order -fileset sim_1\n";
		print VS "set_property -name {xsim.elaborate.debug_level} -value {all} -objects [get_filesets sim_1]\n";
		print VS "set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]\n";
		# Set Verilog defines for proper test script selection
		print VS "set_property verilog_define {REGRESSION=1} [get_filesets sources_1]\n";
		print VS "set_property verilog_define {REGRESSION=1} [get_filesets sim_1]\n";
		print VS "launch_simulation -simset sim_1 -mode behavioral\n";
		print VS "exit\n";
		close(VS);
		print "Debug: Completed Vivado script generation\n";
		
		# Execute the Vivado simulation
		my $cmd = "$vivado_path -mode batch -source $vivado_script -log $tstname.log -journal $tstname.jou";
		print "Debug: Executing Vivado: $cmd\n";
		my $start_time = time();
		system($cmd);
		my $end_time = time();
		my $elapsed = $end_time - $start_time;
		print "Debug: Vivado execution completed in $elapsed seconds\n";
		
		# Check for successful completion BEFORE cleanup
		my $logfile = "$tstname.log";
		my $success = 0;
		my $errors_present = 0;
		my $assertion_failed = 0;
		my $timing_failure = 0;

		if (-e $logfile) {
			open(LF, $logfile);
			while(my $line = <LF>) {
				if ($line =~ /ERROR/) {
					$errors_present = 1;
				}

				if ($line =~ /assert.*fail/) {
					$assertion_failed = 1;
				}

				if ($line =~ /timing violation/i) {
					$timing_failure = 1;
				}

				if ($line =~ /fail/i) {
					$test_failed = 1;
				}

				if ($line =~ /Simulation complete/ || $line =~ /Test pass/) {
					$success = 1;
					last;
				}
			}
			close(LF);
		}

		# Cleanup temporary files and directories (but keep test log files)
		print "Debug: Cleaning up temporary files and directories\n";
		system("rm -f testscript.v satalib.v vivado_sim.tcl");
		system("rm -f *.jou");  # Remove journal files but keep test log files
		system("rm -rf tmp_project");

		$tstamp = timestamp();
		$msg = sprintf("%s Vivado    -- %s", $tstamp, $tstname);

		if ($assertion_failed or $errors_present) {
			push(@failed, $tstname);
			$msg = sprintf("ERRORS    %s\n", $msg);
		} elsif ($timing_failure) {
			push(@failed, $tstname);
			$msg = sprintf("TIMING-ER %s\n", $msg);
		} elsif ($test_failed or $success == 0) {
			push(@failed, $tstname);
			$msg = sprintf("FAIL      %s\n", $msg);
		} else {
			push(@passed, $tstname);
			$msg = sprintf("Pass      %s\n", $msg);
		}
		
		open(SUM,">> $report");
		print(SUM $msg);
		close(SUM);
		print $msg;

		return();
	} else {
		print "ERROR: No simulator defined!\n";
		exit(-1);
		return();
	}
}
## }}}

## gettest: Look up a test's configuration
## {{{
sub gettest($) {
	my ($key)=@_;
	my	$tstname;

print "Looking up $key\n";

	open(GTL, $testlist);
	while($line = <GTL>) {
		next if ($line =~ /^\s*#/);
		if ($line =~ /^\s*(\S+)\s+(\S+)\s/) {
			$tstname = $1;
			last if ($tstname eq $key);
		}
	} close GTL;
	if ($tstname eq $key) {
		$line;
	} else {
		print "ERR: Test not found: $key\n";
		"# FAIL";
	}
}
## }}}

## Run all tests
## {{{
if (!-d $testd) {
	print "Debug: Creating test directory: $testd\n";
	mkdir $testd;
}

if ($run_all) {
	print "Debug: Running all tests from $testlist\n";
	open(TL, $testlist) or die "Cannot open test list file: $!";
	my $test_count = 0;
	while($line = <TL>) {
		next if ($line =~ /^\s*#/);
		$test_count++;
		print "Debug: Processing test $test_count: $line";
		simline($line);
	}
	close(TL);
	print "Debug: Processed $test_count tests\n";

	open(SUM,">> $report");
	print (SUM "$linestr\nTest run complete\n\n");
	close SUM;
} else {
	print "Debug: Running specific tests: " . join(", ", @array) . "\n";
	my $test_count = 0;
	foreach $akey (@array) {
		$test_count++;
		print "Debug: Processing test $test_count: $akey\n";
		$line = gettest($akey);
		next if ($line =~ /FAIL/);
		simline($line);
	}
	print "Debug: Processed $test_count tests\n";
}
## }}}

if (@passed) {
	print "\n" . scalar(@passed) . " Passing testcases:\n$linestr\n";
	foreach $akey (@passed) {
		print " $akey\n";
	}
}

if (@failed) {
	print "\n" . scalar(@failed) . " Failed testcases:\n$linestr\n";
	foreach $akey (@failed) {
		print " $akey\n";
	}
}

if (@failed) {
	die "\nNot all tests passed\n";
} else {
	print "$linestr\nAll tests passed\n";
}
