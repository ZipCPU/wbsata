////////////////////////////////////////////////////////////////////////////////
//
// Filename:	./bench/verilog/testscript/sata_start.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	This module ... doesn't seem to have a purpose.  It isn't
//		(currently) part of any simulation, and may be removed in the
//	future.
//
// Creator:
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
`include "../testscript/satalib.v"
// }}}
module sata_soft_reset (
    input wire clk,         // Clock sinyali
    input wire reset,       // Reset sinyali
    output reg [31:0] tx_data, // Gönderilecek veri (FIS verisi)
    output reg tx_ready,    // Komut gönderim sinyali
    input wire rx_ready     // Alıcı hazır sinyali
);

    // Durum makineleri için tanımlar
    localparam IDLE        = 3'b000;
    localparam SEND_FIS    = 3'b001;
    localparam WAIT_RESP   = 3'b010;

    // FIS tipleri
    localparam [7:0] FIS_TYPE_CONTROL = 8'hA1;  // Control FIS tipi

    reg [2:0] state;          // Durum makinesi durumu
    reg [7:0] control_field;  // Control FIS için kontrol alanı

    initial begin
        state = IDLE;
        tx_ready = 0;
        control_field = 8'h08; // Soft Reset komutunun Control alanı
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            tx_ready <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx_ready <= 0;
                    if (!reset) begin
                        // Control FIS paketini hazırla
                        tx_data <= {FIS_TYPE_CONTROL, 24'h080000}; // Soft Reset için FIS
                        $display("Preparing Soft Reset FIS: %h", tx_data);
                        state <= SEND_FIS;
                    end
                end

                SEND_FIS: begin
                    tx_ready <= 1;  // Gönderim başlıyor
                    $display("Sending Soft Reset FIS...");
                    state <= WAIT_RESP;
                end

                WAIT_RESP: begin
                    if (rx_ready) begin
                        tx_ready <= 0;
                        $display("Soft Reset completed.");
                        state <= IDLE; // İşlem tamamlandı
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
