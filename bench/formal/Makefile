################################################################################
##
## Filename:	bench/formal/Makefile
## {{{
## Project:	A Wishbone SATA controller
##
## Purpose:	
##
## Creator:	Dan Gisselquist, Ph.D.
##		Gisselquist Technology, LLC
##
################################################################################
## }}}
## Copyright (C) 2022-2024, Gisselquist Technology, LLC
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
all: crc framer scrambler satatb_bwrap

RTL := ../../rtl

CRC := sata_crc
FRAMR := sata_framer
SCRAMBLR := sata_scrambler
BWRAP := satatb_bwrap

.PHONY: crc sata_crc
## {{{
crc: sata_crc
sata_crc: $(CRC)_prf/PASS $(CRC)_cvr/PASS
$(CRC)_prf/PASS: $(CRC).sby $(CRC)_wrapper.v $(RTL)/satarx_crc.v $(RTL)/satatx_crc.v
	sby -f $(CRC).sby prf
$(CRC)_cvr/PASS: $(CRC).sby $(CRC)_wrapper.v $(RTL)/satarx_crc.v $(RTL)/satatx_crc.v
	sby -f $(CRC).sby cvr
## }}}

.PHONY: scrambler sata_scrambler
## {{{
scrambler: sata_scrambler
sata_scrambler: $(SCRAMBLR)_prf/PASS $(SCRAMBLR)_cvr/PASS
$(SCRAMBLR)_prf/PASS: $(SCRAMBLR).sby $(SCRAMBLR).v $(RTL)/satarx_scrambler.v $(RTL)/satatx_scrambler.v
	sby -f $(SCRAMBLR).sby prf
$(SCRAMBLR)_cvr/PASS: $(SCRAMBLR).sby $(SCRAMBLR).v $(RTL)/satarx_scrambler.v $(RTL)/satatx_scrambler.v
	sby -f $(SCRAMBLR).sby cvr
## }}}

.PHONY: framer sata_framer
## {{{
framer: sata_framer
sata_framer: $(FRAMR)_prf/PASS $(FRAMR)_cvr/PASS
$(FRAMR)_prf/PASS: $(FRAMR).sby $(FRAMR).v $(RTL)/satarx_framer.v $(RTL)/satatx_framer.v
	sby -f $(FRAMR).sby prf
$(FRAMR)_cvr/PASS: $(FRAMR).sby $(FRAMR).v $(RTL)/satarx_framer.v $(RTL)/satatx_framer.v
	sby -f $(FRAMR).sby cvr
## }}}

.PHONY: bwrap satatb_bwrap
## {{{
bwrap: satatb_bwrap
satatb_bwrap: $(BWRAP)_prf/PASS
$(BWRAP)_prf/PASS: $(BWRAP).sby $(BWRAP).v ../verilog/satatb_8b10b.v ../verilog/satatb_10b8b.v
	sby -f $(BWRAP).sby prf
## }}}

.PHONY: report
## {{{
report:
	+perl genreport.pl > report.html
## }}}

.PHONY: clean
## {{{
clean:
	rm  -f report.html
	rm -rf sata_crc_*/
	rm -rf sata_scrambler_*/
	rm -rf sata_framer_*/
## }}}
