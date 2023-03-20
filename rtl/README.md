## SATA Controller components

- [`sata_controller`](sata_controller.v): The "top" level of the controller
  - [`sata_transport`](sata_transport.v)
    - [sfifo](sfifo.v): Basic synchronous FIFO
    - [afifo](afifo.v): Basic asynchronous FIFO
  - [`sata_link`](sata_link.v)
    - [`satalnk_rmcont`](satalnk_rmcont.v)
    - [afifo](afifo.v): Basic asynchronous FIFO
    - [`satalnk_txpacket`](satalnk_txpacket.v)
      - `skidbuffer`
      - [`satatx_crc`](satatx_crc.v)
      - [`satatx_scrambler`](satatx_scrambler.v)
      - [`satatx_framer`](satatx_framer.v)
    - [`satalnk_fsm`](satalnk_fsm.v)
    - [`satalnk_align`](satalnk_align.v)
    - [`satalnk_rxpacket`](satalnk_rxpacket.v)
      - [`satarx_framer`](satarx_framer.v)
      - [`satarx_scrambler`](satarx_scrambler.v)
      - [`satarx_crc`](satarx_crc.v)

- [`sata_phy`](sata_phy.v)
  - [`sata_phyinit`](sata_phyinit.v)
  - `sata_phypwr` (Needs to be connected)

Unused: `sata_fsm`, `sata_rxdata`, `sata_txdata`
