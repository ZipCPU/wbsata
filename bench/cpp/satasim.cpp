#include "satasim.h"
#include <iostream>
#include <cstring>
#include <cassert>
#include <iomanip>

// Constructor
SATASIM::SATASIM() {
    m_busy = false;
    
    // Initialize interface signals
    m_rxphy_elecidle = true;
    m_rxphy_cominit = false;
    m_rxphy_comwake = false;
    m_txphy_comfinish = false;
    m_ready = false;
    m_rxphy_valid = false;  
    m_rxphy_primitive = false;
    m_rxphy_data = 0;

    // Initialize TX signals
    m_txphy_cominit = false;
    m_txphy_comwake = false;
    m_txphy_elecidle = true;
    m_txphy_primitive = false;
    m_txphy_data = 0;
    
    // Initialize reset and ready signals
    m_reset = false;
    m_link_ready = false;
    m_phy_ready = false;
    m_txphy_ready = false;
    
    // Initialize link layer state machine
    m_link_state = SEND_ALIGN;

    // Initialize OOB processing
    m_oob_done = false;

    // Initialize DMA-PIO operations
    m_dma_act = false;
    m_dma_read = false;
    m_pio_setup = false;
    m_pio_read = false;
    m_data_response = false;
    
    // Initialize scrambler and CRC
    m_crc_matched = false;
    m_scrambler_fill = SCRAMBLER_INITIAL;
    m_crc = CRC_INITIAL;
    
    // Initialize data buffer
    m_lba = 0;
    m_data_complete = false;
    reset_data_buffer();
    memset(m_received_data, 0, sizeof(m_received_data));
    m_sent_data = nullptr;
}

// Destructor
SATASIM::~SATASIM() {
    // Nothing to clean up
}

// Byte swap function for endianness conversion
uint32_t SATASIM::swap_endian(uint32_t data) {
    return ((data & 0xFF000000) >> 24) |
            ((data & 0x00FF0000) >> 8) |
            ((data & 0x0000FF00) << 8) |
            ((data & 0x000000FF) << 24);
}

// Reset the SATA interface
void SATASIM::reset() {
    m_busy = false;
    
    // Reset interface signals
    m_rxphy_elecidle = true;
    m_rxphy_cominit = false;
    m_rxphy_comwake = false;
    m_txphy_comfinish = false;
    m_ready = false;
    m_rxphy_valid = false;
    m_rxphy_primitive = false;
    m_rxphy_data = 0;
    
    // Reset status signals
    m_phy_ready = false;
    m_txphy_ready = false;
    m_oob_done = false;
    
    // Reset scrambler and CRC state
    m_scrambler_fill = SCRAMBLER_INITIAL;
    m_crc = CRC_INITIAL;
    
    // Reset data buffer
    reset_data_buffer();
}

// Reset data buffer
void SATASIM::reset_data_buffer() {
    // memset(m_received_data, 0, sizeof(m_received_data));
    m_scrambler_fill = SCRAMBLER_INITIAL;
    m_crc = CRC_INITIAL;
    m_data_count = 0;
    m_crc_matched = false;
    m_data_complete = false;
}

// Check if operation is in progress
bool SATASIM::is_busy() {
    return m_busy;
}

void SATASIM::set_oob_done(bool oob_done) {
    m_oob_done = oob_done;
}

// Send COMINIT and COMWAKE responses
bool SATASIM::send_coms() {
    static bool cominit_sent = false;
    static bool comwake_sent = false;

    // Handle the COMINIT response
    if (m_txphy_comfinish && !cominit_sent) {
        // Drive COMINIT one clock after comfinish
        m_rxphy_cominit = true;
        printf("DEVICE: Sending COMINIT\n");
    } else {
        // After one clock, clear COMINIT
        if (m_rxphy_cominit) {
            cominit_sent = true;
            m_rxphy_cominit = false;
        }
    }

    // Handle the COMWAKE response (only after COMINIT was sent)
    if (m_txphy_comfinish && !comwake_sent && cominit_sent) {
        // Drive COMWAKE one clock after comfinish
        m_rxphy_comwake = true;
        printf("DEVICE: Sending COMWAKE\n");
    } else {
        // After one clock, clear COMWAKE
        if (m_rxphy_comwake) {
            comwake_sent = true;
            m_rxphy_comwake = false;
        }
    }

    return cominit_sent && comwake_sent;
}

// Detect COMINIT and COMWAKE signals from controller
void SATASIM::detect_coms() {
    if (m_txphy_cominit || m_txphy_comwake) {
        // Controller is sending COMINIT/COMWAKE - set comfinish in response
        m_txphy_comfinish = true;
        printf("DEVICE: Detecting COMINIT/COMWAKE\n");
    } else {
        m_txphy_comfinish = false;
    }
}

// Process OOB (Out-of-Band) signaling
bool SATASIM::process_oob() {
    bool coms_done = false;
    // bool sync_received = false;
    // static int align_cnt = 0;

    // Detect COMs and send responses
    detect_coms();
    coms_done = send_coms();

    if (coms_done) {
        // Controller is ready - exit electrical idle
        m_rxphy_elecidle = false;

        // Start sending ALIGN primitives (on RX clock domain)
        // device_phy_sends(ALIGN_P, true);
        // align_cnt++;

        // Send SYNC primitive
        // sync_received = wait_for_primitive(SYNC_P);
        // if (sync_received && (align_cnt == 100))
        //     device_phy_sends(SYNC_P, true);
    }

    return coms_done;
}

// Generate input signals for the controller (drives controller's inputs)
void SATASIM::process_rx_signals(bool &rxphy_cominit,
                             bool &rxphy_comwake,
                             bool &rxphy_elecidle,
                             bool &rxphy_valid,
                             bool &rxphy_primitive,
                             uint64_t &rxphy_data,
                             bool &phy_ready) {
    // Pass our internal RX signals to the output parameters
    rxphy_cominit = m_rxphy_cominit;
    rxphy_comwake = m_rxphy_comwake;
    rxphy_elecidle = m_rxphy_elecidle;
    rxphy_valid = m_rxphy_valid;
    
    // Construct 33-bit signal with primitive bit at MSB (bit 32)
    rxphy_data = (uint64_t)m_rxphy_data & 0xFFFFFFFF;  // 32-bit data
    if (m_rxphy_primitive)
        rxphy_data |= (1ULL << 32);  // Set bit 32 (primitive bit)
    
    rxphy_primitive = m_rxphy_primitive;
    
    // Pass other PHY status signals
    phy_ready = m_phy_ready;
}

// Update internal state from controller's outputs
void SATASIM::process_tx_signals(bool reset,
                              bool txphy_cominit, 
                              bool txphy_comwake, 
                              bool txphy_elecidle, 
                              bool txphy_primitive, 
                              uint32_t txphy_data,
                              bool &txphy_comfinish,
                              bool &txphy_ready,
                              bool link_ready) {
    // Update reset state
    m_reset = reset;
    m_link_ready = link_ready;
    
    // Set up PHY status based on reset
    if (m_reset) {
        m_txphy_ready = false;
        m_phy_ready = false;
    } else {
        m_txphy_ready = true;
        m_phy_ready = true;
    }

    txphy_comfinish = m_txphy_comfinish;
    txphy_ready = m_txphy_ready;

    // Capture TX signals from controller to our internal state
    m_txphy_cominit = txphy_cominit;
    m_txphy_comwake = txphy_comwake;
    m_txphy_elecidle = txphy_elecidle;
    m_txphy_primitive = txphy_primitive;
    m_txphy_data = txphy_data;
}

// Send data or primitive from device to host
void SATASIM::device_phy_sends(uint32_t data, bool primitive) {
    // Set the data and primitive signals on RX clock domain
    m_rxphy_valid = true;
    m_rxphy_primitive = primitive;
    m_rxphy_data = data;
}

// Wait for a specific primitive from controller
bool SATASIM::wait_for_primitive(uint32_t primitive) {
    bool primitive_received = false;
    bool log_flag = false;
    
    // Wait for the specific primitive on the TX clock domain
    if((m_txphy_data == primitive) && (m_txphy_primitive)) {
        log_flag = true;
        primitive_received = true;
    }
    
    // Log which primitive was received
    if (log_flag) {
        log_flag = false;
        if (primitive == XRDY_P)
            printf("DEVICE: XRDY received\n");
        else if (primitive == RRDY_P)
            printf("DEVICE: RRDY received\n");
        else if (primitive == OK_P)
            printf("DEVICE: OK received\n");
        else if (primitive == ERR_P)
            printf("DEVICE: ERR received\n");
        else if (primitive == WTRM_P)
            printf("DEVICE: WTRM received\n");
        else if (primitive == R_IP_P)
            printf("DEVICE: R_IP received\n");
        else if (primitive == EOF_P)
            printf("DEVICE: EOF received\n");
        else if (primitive == SYNC_P)
            printf("DEVICE: SYNC received\n");
        else if (primitive == SOF_P)
            printf("DEVICE: SOF received\n");
        else if (primitive == ALIGN_P)
            printf("DEVICE: ALIGN received\n");
    }
    
    return primitive_received;
}

void SATASIM::device_link_sends(uint32_t data, bool is_last) {
    uint32_t s_data = 0;

    if (!is_last) {
        s_data = swap_endian(scramble_data(data));
        calculate_crc(data);
    } else {
        s_data = swap_endian(scramble_data(m_crc));
    }

    device_phy_sends(s_data, false);
}

// Receive data from controller
void SATASIM::device_link_receives() {
    uint32_t fis_type = 0;
    uint32_t cmd_type = 0;
    uint32_t raw_data = 0;
    
    // Extract FIS type from 32-bit data
    if (!m_txphy_primitive) {
        if (m_data_count == 0) {
            // If we're receiving the first data word, reset our buffer
            reset_data_buffer();
            
            // Initialize the scramble function for first data word
            raw_data = scramble_data(swap_endian(m_txphy_data));
            fis_type = (raw_data >> 16) & 0xFF;
            cmd_type = (raw_data & 0xFF);
            m_lba = (raw_data >> 8) & 0xFF;
            m_data_count++;
            
            // Calculate expected CRC
            calculate_crc(raw_data);
            
            // Set command flags
            if (fis_type == FIS_TYPE_DMA_WRITE && cmd_type == FIS_TYPE_REG_H2D) {
                m_dma_act = true;
                printf("DEVICE: DMA Write command received\n");
            } else if (fis_type == FIS_TYPE_DMA_READ && cmd_type == FIS_TYPE_REG_H2D) {
                m_dma_read = true;
                printf("DEVICE: DMA Read command received\n");
            } else if (fis_type == FIS_TYPE_PIO_WRITE_BUFFER && cmd_type == FIS_TYPE_REG_H2D) {
                m_pio_setup = true;
                printf("DEVICE: PIO Write command received\n");
            } else if (fis_type == FIS_TYPE_PIO_READ_BUFFER && cmd_type == FIS_TYPE_REG_H2D) {
                m_pio_setup = true;
                m_pio_read = true;
                printf("DEVICE: PIO Read command received\n");
            } else if (cmd_type == FIS_TYPE_DATA) {
                m_data_response = true;
                printf("DEVICE: Data command received\n");
            }
        } else {
            raw_data = scramble_data(swap_endian(m_txphy_data));
            m_crc_matched = (raw_data == m_crc);
            calculate_crc(raw_data);
            
            if (m_crc_matched)
                printf("DEVICE: CRC validation successful\n");
            
            // Store the data word
            if (!m_crc_matched && m_data_response) {
                m_received_data[m_data_count-1] = swap_endian(raw_data);
                m_data_count++;
            }
        }
    }
}

// Helper function equivalent to the scramble function in satatx_scrambler.v
uint64_t SATASIM::scramble_function(uint16_t prior) {
    uint16_t s_fill = prior;
    uint32_t s_prn = 0;
    
    // Implement the Verilog scramble algorithm
    for (int k = 0; k < 32; k++) {
        // Get MSB bit
        s_prn |= ((s_fill >> 15) & 0x1) << k;
        
        // LFSR with polynomial
        if (s_fill & 0x8000) { // if MSB is 1
            s_fill = ((s_fill << 1) ^ SCRAMBLER_POLYNOMIAL) & 0xFFFF;
        } else {
            s_fill = (s_fill << 1) & 0xFFFF;
        }
    }
    
    // Return 48-bit result (32-bit PRN + 16-bit next state)
    return ((uint64_t)s_prn << 16) | s_fill;
}

// Main scrambling function 
uint32_t SATASIM::scramble_data(uint32_t data) {
    uint64_t result = scramble_function(m_scrambler_fill);
    uint32_t prn = result >> 16;
    m_scrambler_fill = result & 0xFFFF;
    
    // XOR input data with generated PRN
    return data ^ prn;
}

// Helper function equivalent to the advance_crc function in satatx_crc.v
uint32_t SATASIM::advance_crc(uint32_t prior, uint32_t dword) {
    volatile uint32_t sreg = prior;
    volatile uint32_t input = dword;
    
    // Implement the Verilog CRC algorithm
    for (int k = 0; k < 32; k++) {
        // Using volatile variables to prevent optimization issues
        volatile bool bit = (sreg >> 31) & 0x1;
        volatile bool data_bit = (input >> (31-k)) & 0x1;
        
        // printf("CPP DEBUG: bit = %d, data_bit = %d\n", bit, data_bit);
        if (bit ^ data_bit) {
            sreg = ((sreg << 1) ^ CRC_POLYNOMIAL) & 0xFFFFFFFF;
        } else {
            sreg = (sreg << 1) & 0xFFFFFFFF;
        }
    }
    
    return sreg;
}

// Main CRC calculation function
uint32_t SATASIM::calculate_crc(uint32_t data) {
    m_crc = advance_crc(m_crc, data);
    
    return m_crc;
}

void SATASIM::dma_activate() {
    if (m_data_count == 0) {
        device_phy_sends(SOF_P, true);
        m_data_count++;
    } else if (m_data_count == 1) {
        device_link_sends(DMA_ACT_FIS_RESPONSE[0], false);
        m_data_count++;
    } else if (m_data_count == 2) {
        m_dma_act = false;
        device_link_sends(0, true);
        m_link_state = SEND_EOF;
        printf("DEVICE: Link state -> SEND_EOF\n");
    }
}

void SATASIM::pio_setup_response() {
    if (m_data_count == 0) {
        device_phy_sends(SOF_P, true);
        m_data_count++;
    } else if (m_data_count == 6) {
        m_pio_setup = false;
        device_link_sends(0, true);
        m_link_state = SEND_EOF;
        printf("DEVICE: Link state -> SEND_EOF\n");
    } else {
        device_link_sends(PIO_SETUP_FIS_RESPONSE[m_data_count-1], false);
        m_data_count++;
    }
}

void SATASIM::data_send() {
    if (m_data_count == 0) {
        device_phy_sends(SOF_P, true);
        m_data_count++;
    } else if (m_data_count == 1) {
        device_link_sends(DATA_FIS_RESPONSE[0], false);
        m_data_count++;
    } else if (m_data_count == (SATA_SECTOR_SIZE/4)+2) {
        m_dma_read = false;
        m_pio_read = false;
        m_data_response = true;
        device_link_sends(0, true);
        m_link_state = SEND_EOF;
        printf("DEVICE: Link state -> SEND_EOF\n");
    } else {
        device_link_sends(m_sent_data[m_data_count-2], false);
        m_data_count++;
    }
}

void SATASIM::d2h_response() {
    if (m_data_count == 0) {
        device_phy_sends(SOF_P, true);
        m_data_count++;
    } else {
        if (m_data_count == 5) {
            m_data_response = false;
            device_link_sends(0, true); // Data is not important here
            m_link_state = SEND_EOF;
            printf("DEVICE: Link state -> SEND_EOF\n");
        } else {
            device_link_sends(D2H_REG_FIS_RESPONSE[m_data_count-1], false);
            m_data_count++;
        }
    }
}

// Link layer state machine for DMA activation
LinkState SATASIM::link_layer_model() {
    static int align_cnt = 0;

    if (m_oob_done) {
        // Use a state machine to handle the link layer protocol
        switch (m_link_state) {
            case SEND_ALIGN:
                align_cnt++;    // Count the number of ALIGN primitives sent (100 is trivial)
                device_phy_sends(ALIGN_P, true);
                // If OOB processing is done, transition to IDLE
                if (align_cnt == 100) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                break;

            case IDLE:
                reset_data_buffer();
                device_phy_sends(SYNC_P, true);
                // Host asks; if device is ready to accept data
                if (wait_for_primitive(XRDY_P)) {
                    m_link_state = RCV_CHKRDY;
                    printf("DEVICE: Link state -> RCV_CHKRDY\n");
                } else if (m_dma_act || m_dma_read || m_pio_setup || m_pio_read || m_data_response) {
                    m_link_state = SEND_CHKRDY;
                    printf("DEVICE: Link state -> SEND_CHKRDY\n");
                }
                break;

            case SEND_CHKRDY:
                device_phy_sends(XRDY_P, true);
                if (wait_for_primitive(RRDY_P)) {
                    m_link_state = SEND_DATA;
                    printf("DEVICE: Link state -> SEND_DATA\n");
                } else if (wait_for_primitive(XRDY_P)) {
                    m_link_state = RCV_CHKRDY;
                    printf("DEVICE: Link state -> RCV_CHKRDY\n");
                }
                break;

            case SEND_DATA:
                if (m_dma_act)
                    dma_activate();
                else if (m_pio_setup)
                    pio_setup_response();
                else if (m_dma_read || m_pio_read)
                    data_send();
                else if (m_data_response)
                    d2h_response();
                break;

            case SEND_EOF:
                device_phy_sends(EOF_P, true);
                m_link_state = WAIT;
                printf("DEVICE: Link state -> WAIT\n");
                break;
            
            case RCV_CHKRDY:
                device_phy_sends(RRDY_P, true);
                // Did we get the start of frame primitive?
                if (wait_for_primitive(SOF_P)) {
                    m_link_state = RCV_DATA;
                    printf("DEVICE: Link state -> RCV_DATA\n");
                }
                break;
            
            case RCV_DATA:
                // Keep indicating we're OK to receive data
                device_phy_sends(R_IP_P, true);
                
                // Process incoming data
                device_link_receives();

                // Check if we've seen EOF or WTRM to end data reception
                if (wait_for_primitive(EOF_P)) {
                    m_data_complete = true;
                    m_link_state = RCVEOF;
                    printf("DEVICE: Link state -> RCVEOF\n");
                } else if (wait_for_primitive(WTRM_P)) {
                    m_link_state = BADEND;
                    printf("DEVICE: Link state -> BADEND\n");
                }
                break;

            case RCVEOF:
                device_phy_sends(R_IP_P, true);
                if (m_crc_matched) {
                    m_link_state = GOODEND;
                    printf("DEVICE: Link state -> GOODEND\n");
                }
                else {
                    m_link_state = BADEND;
                    printf("DEVICE: Link state -> BADEND\n");
                }
                break;
            
            case WAIT:
                device_phy_sends(WTRM_P, true);
                // Wait for SYNC or OK or ERR primitive
                if (wait_for_primitive(SYNC_P)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                else if (wait_for_primitive(OK_P)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                else if (wait_for_primitive(ERR_P)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                break;
            
            case GOODEND:
                device_phy_sends(OK_P, true);
                if (wait_for_primitive(SYNC_P)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                break;
            
            case BADEND:
                device_phy_sends(ERR_P, true);
                if (wait_for_primitive(SYNC_P)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                break;
        }
    }

    return m_link_state;
}
