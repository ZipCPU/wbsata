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
## Copyright (C) 2022-2025, Gisselquist Technology, LLC
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
.PHONY: all framer fifo dma gears scrambler
## }}}
all: crc satatx_crc satarx_crc framer scrambler satatb_bwrap satarx_scrambler satalnk_align satalnk_rmcont fifo dma pextend wbarb txarb rxarb report
framer: satarx_framer satatx_framer
fifo: afifo sfifo skid
dma: s2mm mm2s gears
gears: txgears rxgears
scrambler: sata_scrambler satarx_scrambler satatx_scrambler

RTL := ../../rtl

CRC      := sata_crc
TXCRC    := satatx_crc
RXCRC    := satarx_crc
FRAMR    := sata_framer
SCRAMBLR := sata_scrambler
RXSCRAM  := satarx_scrambler
TXSCRAM  := satatx_scrambler
TXALIGN  := satalnk_align
RXALIGN  := satalnk_rmcont
RXFRAME  := satarx_framer
TXFRAME  := satatx_framer
BWRAP    := satatb_bwrap
PEXTEND  := sata_pextend
AFIFO    := sata_afifo
SFIFO    := sata_sfifo
SKID     := sata_skid
TXGEARS  := satadma_txgears
RXGEARS  := satadma_rxgears
MM2S     := satadma_mm2s
S2MM     := satadma_s2mm
WBARB    := satatrn_wbarbiter
TXARB    := satatrn_txarb
RXARB    := satatrn_rxregfis

AXIN     := faxin_slave.v faxin_master.v
WB       := fwb_slave.v fwb_master.v
NOJOBSERVER := MAKEFLAGS=
SBYFLAGS := -j2 -f

.PHONY: crc sata_crc
## {{{
crc: sata_crc
sata_crc: $(CRC)_prf/PASS $(CRC)_cvr/PASS
$(CRC)_prf/PASS: $(CRC).sby $(CRC)_wrapper.v $(RTL)/$(RXCRC).v $(RTL)/$(TXCRC).v $(AXIN)
	$(NOJOBSERVER) sby -j8 -f $(CRC).sby prf
$(CRC)_cvr/PASS: $(CRC).sby $(CRC)_wrapper.v $(RTL)/$(RXCRC).v $(RTL)/$(TXCRC).v $(AXIN)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(CRC).sby cvr
## }}}

.PHONY: txcrc satatx_crc
## {{{
txcrc: satatx_crc
$(TXCRC): $(TXCRC)_prf/PASS $(TXCRC)_cvr/PASS
$(TXCRC)_prf/PASS: $(TXCRC).sby $(RTL)/$(TXCRC).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXCRC).sby prf
$(TXCRC)_cvr/PASS: $(TXCRC).sby $(RTL)/$(TXCRC).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXCRC).sby cvr
## }}}

.PHONY: rxcrc satarx_crc
## {{{
rxcrc: satarx_crc
$(RXCRC): $(RXCRC)_prf/PASS $(RXCRC)_cvr/PASS
$(RXCRC)_prf/PASS: $(RXCRC).sby $(RTL)/$(RXCRC).v $(AXIN)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXCRC).sby prf
$(RXCRC)_cvr/PASS: $(RXCRC).sby $(RTL)/$(RXCRC).v $(AXIN)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXCRC).sby cvr
## }}}

.PHONY: scrambler sata_scrambler
## {{{
scrambler: sata_scrambler
sata_scrambler: $(SCRAMBLR)_prf/PASS $(SCRAMBLR)_cvr/PASS
$(SCRAMBLR)_prf/PASS: $(SCRAMBLR).sby $(SCRAMBLR).v $(RTL)/satarx_scrambler.v $(RTL)/$(TXSCRAM).v $(AXIN)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SCRAMBLR).sby prf
$(SCRAMBLR)_cvr/PASS: $(SCRAMBLR).sby $(SCRAMBLR).v $(RTL)/satarx_scrambler.v $(RTL)/$(TXSCRAM).v $(AXIN)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SCRAMBLR).sby cvr
## }}}

.PHONY: rxscrambler
## {{{
rxscrambler: $(RXSCRAM)
$(RXSCRAM): $(RXSCRAM)_prf/PASS
$(RXSCRAM)_prf/PASS: $(RXSCRAM).sby $(RTL)/$(RXSCRAM).v $(AXIN)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXSCRAM).sby prf
## }}}

.PHONY: txscrambler
## {{{
txscrambler: $(TXSCRAM)
$(TXSCRAM): $(TXSCRAM)_prf/PASS $(TXSCRAM)_cvr/PASS
$(TXSCRAM)_prf/PASS: $(TXSCRAM).sby $(RTL)/$(TXSCRAM).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXSCRAM).sby prf
$(TXSCRAM)_cvr/PASS: $(TXSCRAM).sby $(RTL)/$(TXSCRAM).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXSCRAM).sby cvr
## }}}

.PHONY: framer sata_framer
## {{{
framer: sata_framer
sata_framer: $(FRAMR)_prf/PASS $(FRAMR)_cvr/PASS
$(FRAMR)_prf/PASS: $(FRAMR).sby $(FRAMR).v $(RTL)/$(RXFRAME).v $(RTL)/satatx_framer.v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(FRAMR).sby prf
$(FRAMR)_cvr/PASS: $(FRAMR).sby $(FRAMR).v $(RTL)/$(RXFRAME).v $(RTL)/satatx_framer.v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(FRAMR).sby cvr
## }}}

.PHONY: rxframer $(RXFRAME)
## {{{
rxframer: $(RXFRAME)
$(RXFRAME): $(RXFRAME)_prf/PASS
$(RXFRAME)_prf/PASS: $(RXFRAME).sby $(RTL)/$(RXFRAME).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXFRAME).sby prf
## }}}

.PHONY: txframer $(TXFRAME)
## {{{
txframer: $(TXFRAME)
$(TXFRAME): $(TXFRAME)_prf/PASS
$(TXFRAME)_prf/PASS: $(TXFRAME).sby $(RTL)/$(TXFRAME).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXFRAME).sby prf
## }}}

.PHONY: txalign $(TXALIGN)
## {{{
$(TXALIGN): txalign
$(TXALIGN): $(TXALIGN)_prf/PASS
$(TXALIGN)_prf/PASS: $(TXALIGN).sby $(RTL)/$(TXALIGN).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXALIGN).sby prf
## }}}

.PHONY: rxalign $(RXALIGN)
## {{{
$(RXALIGN): rxalign
$(RXALIGN): $(RXALIGN)_prf/PASS
$(RXALIGN)_prf/PASS: $(RXALIGN).sby $(RTL)/$(RXALIGN).v $(RTL)/sata_primitives.vh
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXALIGN).sby prf
## }}}

.PHONY: pextend pulse $(PEXTEND)
## {{{
pextend: $(PEXTEND)
pulse: $(PEXTEND)
$(PEXTEND): $(PEXTEND)_prf/PASS $(PEXTEND)_cvr/PASS
$(PEXTEND)_prf/PASS: $(PEXTEND).sby $(RTL)/$(PEXTEND).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(PEXTEND).sby prf
$(PEXTEND)_cvr/PASS: $(PEXTEND).sby $(RTL)/$(PEXTEND).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(PEXTEND).sby cvr
## }}}

.PHONY: bwrap $(BWRAP)
## {{{
bwrap: $(BWRAP)
$(BWRAP): $(BWRAP)_prf/PASS
$(BWRAP)_prf/PASS: $(BWRAP).sby $(BWRAP).v ../verilog/mdl_s8b10b.v ../verilog/mdl_s10b8b.v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(BWRAP).sby prf
## }}}

.PHONY: afifo $(AFIFO)
## {{{
afifo: $(AFIFO)
$(AFIFO): $(AFIFO)_prf/PASS $(AFIFO)_prfopt/PASS
$(AFIFO): $(AFIFO)_cvr/PASS $(AFIFO)_cvropt/PASS
$(AFIFO)_prf/PASS: $(AFIFO).sby $(RTL)/$(AFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(AFIFO).sby prf
$(AFIFO)_prfopt/PASS: $(AFIFO).sby $(RTL)/$(AFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(AFIFO).sby prfopt
$(AFIFO)_cvr/PASS: $(AFIFO).sby $(RTL)/$(AFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(AFIFO).sby cvr
$(AFIFO)_cvropt/PASS: $(AFIFO).sby $(RTL)/$(AFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(AFIFO).sby cvropt
## }}}

.PHONY: sfifo $(AFIFO)
## {{{
sfifo: $(SFIFO)
$(SFIFO): $(SFIFO)_prf/PASS    $(SFIFO)_prf_r/PASS
$(SFIFO): $(SFIFO)_prf_w/PASS  $(SFIFO)_prf_wr/PASS
$(SFIFO): $(SFIFO)_prf_a/PASS  $(SFIFO)_prf_ar/PASS
$(SFIFO): $(SFIFO)_prf_aw/PASS $(SFIFO)_prf_awr/PASS
$(SFIFO): $(SFIFO)_cvr/PASS
$(SFIFO)_prf/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby prf
$(SFIFO)_prf_r/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby prf_r
$(SFIFO)_prf_w/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby prf_w
$(SFIFO)_prf_wr/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby prf_wr
$(SFIFO)_prf_a/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby prf_a
$(SFIFO)_prf_ar/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby prf_ar
$(SFIFO)_prf_aw/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby prf_aw
$(SFIFO)_prf_awr/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby prf_awr
$(SFIFO)_cvr/PASS: $(SFIFO).sby $(RTL)/$(SFIFO).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SFIFO).sby cvr
## }}}

.PHONY: skid  $(SKID)
## {{{
skid: $(SKID)
$(SKID): $(SKID)_prfc/PASS $(SKID)_prfo/PASS
$(SKID): $(SKID)_lpc/PASS  $(SKID)_lpo/PASS
$(SKID): $(SKID)_cvr/PASS
$(SKID)_prfc/PASS: $(SKID).sby $(RTL)/$(SKID).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SKID).sby prfc
$(SKID)_prfo/PASS: $(SKID).sby $(RTL)/$(SKID).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SKID).sby prfo
$(SKID)_lpc/PASS: $(SKID).sby $(RTL)/$(SKID).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SKID).sby lpc
$(SKID)_lpo/PASS: $(SKID).sby $(RTL)/$(SKID).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SKID).sby lpo
$(SKID)_cvr/PASS: $(SKID).sby $(RTL)/$(SKID).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(SKID).sby cvr
## }}}

.PHONY: txgears $(TXGEARS)
## {{{
txgears: $(TXGEARS)
$(TXGEARS): $(TXGEARS)_prf/PASS $(TXGEARS)_prfw/PASS
$(TXGEARS): $(TXGEARS)_cvr/PASS $(TXGEARS)_cvrw/PASS
$(TXGEARS)_prf/PASS: $(TXGEARS).sby $(RTL)/$(TXGEARS).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXGEARS).sby prf
$(TXGEARS)_prfw/PASS: $(TXGEARS).sby $(RTL)/$(TXGEARS).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXGEARS).sby prfw
$(TXGEARS)_cvr/PASS: $(TXGEARS).sby $(RTL)/$(TXGEARS).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXGEARS).sby cvr
$(TXGEARS)_cvrw/PASS: $(TXGEARS).sby $(RTL)/$(TXGEARS).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXGEARS).sby cvrw
## }}}

.PHONY: rxgears $(RXGEARS)
## {{{
rxgears: $(RXGEARS)
$(RXGEARS): $(RXGEARS)_prf/PASS $(RXGEARS)_prfw/PASS
$(RXGEARS): $(RXGEARS)_cvr/PASS
$(RXGEARS)_prf/PASS: $(RXGEARS).sby $(RTL)/$(RXGEARS).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXGEARS).sby prf
$(RXGEARS)_prfw/PASS: $(RXGEARS).sby $(RTL)/$(RXGEARS).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXGEARS).sby prfw
$(RXGEARS)_cvr/PASS: $(RXGEARS).sby $(RTL)/$(RXGEARS).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXGEARS).sby cvr
## }}}

.PHONY: mm2s $(MM2S)
## {{{
mm2s: $(MM2S)
$(MM2S): $(MM2S)_prf/PASS $(MM2S)_cvr/PASS
$(MM2S)_prf/PASS: $(MM2S).sby $(RTL)/$(MM2S).v $(WB)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(MM2S).sby prf
$(MM2S)_cvr/PASS: $(MM2S).sby $(RTL)/$(MM2S).v $(WB)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(MM2S).sby cvr
## }}}

.PHONY: s2mm $(S2MM)
## {{{
s2mm: $(S2MM)
$(S2MM): $(S2MM)_prf/PASS $(S2MM)_cvr/PASS
$(S2MM)_prf/PASS: $(S2MM).sby $(RTL)/$(S2MM).v $(WB)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(S2MM).sby prf
$(S2MM)_cvr/PASS: $(S2MM).sby $(RTL)/$(S2MM).v $(WB)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(S2MM).sby cvr
## }}}

.PHONY: wbarb $(WBARB)
## {{{
wbarb: $(WBARB)
$(WBARB): $(WBARB)_prf/PASS $(WBARB)_cvr/PASS
$(WBARB)_prf/PASS: $(WBARB).sby $(RTL)/$(WBARB).v $(WB)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(WBARB).sby prf
$(WBARB)_cvr/PASS: $(WBARB).sby $(RTL)/$(WBARB).v $(WB)
	$(NOJOBSERVER) sby $(SBYFLAGS) $(WBARB).sby cvr
## }}}

.PHONY: txarb $(TXARB)
## {{{
txarb: $(TXARB)
$(TXARB): $(TXARB)_prf/PASS $(TXARB)_cvr/PASS
$(TXARB)_prf/PASS: $(TXARB).sby $(RTL)/$(TXARB).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXARB).sby prf
$(TXARB)_cvr/PASS: $(TXARB).sby $(RTL)/$(TXARB).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(TXARB).sby cvr
## }}}

.PHONY: rxarb $(RXARB)
## {{{
rxarb: $(RXARB)
$(RXARB): $(RXARB)_prf/PASS $(RXARB)_cvr/PASS
$(RXARB)_prf/PASS: $(RXARB).sby $(RTL)/$(RXARB).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXARB).sby prf
$(RXARB)_cvr/PASS: $(RXARB).sby $(RTL)/$(RXARB).v
	$(NOJOBSERVER) sby $(SBYFLAGS) $(RXARB).sby cvr
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
	rm -rf sata_crc*/
	rm -rf sata_scrambler*/
	rm -rf sata_framer*/
	rm -rf satarx_scrambler*/
	rm -rf satalnk_align*/
	rm -rf satalnk_rmcont*/
	rm -rf satarx_framer*/
	rm -rf satatb_bwrap*/
## }}}
