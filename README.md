## Wishbone SATA Host Controller

Several projects of mine require a WB SATA controller.  The [10Gb Ethernet
switch](https://github.com/ZipCPU/eth10g) project is an example of one of these
projects.  This repository is intended to be a common IP repository shared by
those projects, and encapsulating the test bench(es) specific to the SATA
controller.

A couple quick features of this controller:

1. Since the [ZipCPU](https://github.com/ZipCPU/zipcpu) that will control
   this IP is big-endian, this controller will need to handle both
   little-endian commands (per spec) and big-endian data.

   There will be an option to be make the IP fully little-endian.

2. My initial goal will be Gen1 (1500Mb/s) compliance.  Later versions may
   move on to Gen2 or Gen3 compliance.

## Hardware

My test setup is (at present) an [Enclustra
Mercury+ST1](https://www.enclustra.com/en/products/base-boards/mercury-st1/)
board with an [Enclustra Kintex-7
160T](https://www.enclustra.com/en/products/fpga-modules/mercury-kx2/)
daughter board, connected to an
[Ospero FPGA Drive FMC](https://opsero.com/product/fpga-drive-fmc-dual/).

## Status

While fully funded, this project is currently a
[work in progress](doc/prjstatus.png).  It is not (yet) fully drafted.  At
present it needs three significant capabilities before it can move to
simulation (or hardware) testing:

1. A means of issuing and detecting out-of-band signaling: COMINIT, COMRESET,
   and COMWAKE.

   Yes, the Xilinx GTX transceiver can handle these, however the
   logic isn't yet present within the IP to handle the control signals to
   either generate (on TX) or handle (on RX) these various signals.

2. A simulation model.  While I typically use C++ Verilator models, this IP
   will require a Verilog model to make sure GTX transceiver works as
   expected--to include the verifying that the out-of-band signals are
   properly detected and handled.

3. A means of debugging in hardware.  I normally do my hardware debugging using
   a [Wishbone scope](https://github.com/ZipCPU/wbscope).  This is my intention
   here as well.  However, the
   [WBSCOPE](https://github.com/ZipCPU/wbscope) can only capture 32-bits per
   clock cycle.  In this case, I'll either need to expand that to more bits
   per clock cycle, or I'll need to choose from among the many critical bits
   within the IP which 32-bits per cycle are the ones I want to capture.  This
   little bit of engineering hasn't (yet) taken place.  It needs to take place
   before I can test on the hardware I have.

## License

The project is currently licensed under GPLv3.  The [ETH10G
project](https://github.com/ZipCPU/eth10g) that will use this capability
will relicense it under Apache2.

