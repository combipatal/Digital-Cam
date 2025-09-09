/*
 * Copyright (C) 2011 Mike Field <hamster@snap.net.nz>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
 
// VHDL 소스 파일: ov7670_registers.vhd
// 이 모듈은 OV7670 카메라에 프로그래밍할 레지스터 값 시퀀스를 생성합니다.

module ov7670_registers (
    input wire          clk,
    input wire          resend,
    input wire          advance,
    output reg [15:0]   command,
    output wire         finished
);

    reg [7:0] address = 8'd0;

    assign finished = (command == 16'hFFFF);

    always @(posedge clk) begin
        if (resend) begin
            address <= 8'd0;
        end else if (advance) begin
            address <= address + 1;
        end

        case (address)
            8'h00: command <= 16'h1280; // COM7   Reset
            8'h01: command <= 16'h1280; // COM7   Reset
            8'h02: command <= 16'h1204; // COM7   Size & RGB output
            8'h03: command <= 16'h1100; // CLKRC  Prescaler - Fin/(1+1)
            8'h04: command <= 16'h0C00; // COM3   Lots of stuff, enable scaling, all others off
            8'h05: command <= 16'h3E00; // COM14  PCLK scaling off
            8'h06: command <= 16'h8C00; // RGB444 Set RGB format
            8'h07: command <= 16'h0400; // COM1   no CCIR601
            8'h08: command <= 16'h4010; // COM15  Full 0-255 output, RGB 565
            8'h09: command <= 16'h3a04; // TSLB   Set UV ordering,  do not auto-reset window
            8'h0A: command <= 16'h1438; // COM9   - AGC Celling
            8'h0B: command <= 16'h4f40; // MTX1   - colour conversion matrix
            8'h0C: command <= 16'h5034; // MTX2   - colour conversion matrix
            8'h0D: command <= 16'h510C; // MTX3   - colour conversion matrix
            8'h0E: command <= 16'h5217; // MTX4   - colour conversion matrix
            8'h0F: command <= 16'h5329; // MTX5   - colour conversion matrix
            8'h10: command <= 16'h5440; // MTX6   - colour conversion matrix
            8'h11: command <= 16'h581e; // MTXS   - Matrix sign and auto contrast
            8'h12: command <= 16'h3dc0; // COM13  - Turn on GAMMA and UV Auto adjust
            8'h13: command <= 16'h1100; // CLKRC  Prescaler - Fin/(1+1)
            8'h14: command <= 16'h1711; // HSTART HREF start (high 8 bits)
            8'h15: command <= 16'h1861; // HSTOP  HREF stop (high 8 bits)
            8'h16: command <= 16'h32A4; // HREF   Edge offset and low 3 bits of HSTART and HSTOP
            8'h17: command <= 16'h1903; // VSTART VSYNC start (high 8 bits)
            8'h18: command <= 16'h1A7b; // VSTOP  VSYNC stop (high 8 bits) 
            8'h19: command <= 16'h030a; // VREF   VSYNC low two bits
            8'h1A: command <= 16'h0e61; // COM5(0x0E) 0x61
            8'h1B: command <= 16'h0f4b; // COM6(0x0F) 0x4B 
            8'h1C: command <= 16'h1602;
            8'h1D: command <= 16'h1e37; // MVFP (0x1E) 0x07  -- FLIP AND MIRROR IMAGE 0x3x
            8'h1E: command <= 16'h2102;
            8'h1F: command <= 16'h2291;
            8'h20: command <= 16'h2907;
            8'h21: command <= 16'h330b;
            8'h22: command <= 16'h350b;
            8'h23: command <= 16'h371d;
            8'h24: command <= 16'h3871;
            8'h25: command <= 16'h392a;
            8'h26: command <= 16'h3c78; // COM12 (0x3C) 0x78
            8'h27: command <= 16'h4d40;
            8'h28: command <= 16'h4e20;
            8'h29: command <= 16'h6900; // GFIX (0x69) 0x00
            8'h2A: command <= 16'h6b4a;
            8'h2B: command <= 16'h7410;
            8'h2C: command <= 16'h8d4f;
            8'h2D: command <= 16'h8e00;
            8'h2E: command <= 16'h8f00;
            8'h2F: command <= 16'h9000;
            8'h30: command <= 16'h9100;
            8'h31: command <= 16'h9600;
            8'h32: command <= 16'h9a00;
            8'h33: command <= 16'hb084;
            8'h34: command <= 16'hb10c;
            8'h35: command <= 16'hb20e;
            8'h36: command <= 16'hb382;
            8'h37: command <= 16'hb80a;
            default: command <= 16'hFFFF;
        endcase
    end
endmodule