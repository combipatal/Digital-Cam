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

// VHDL 소스 파일: i2c_sender.vhd
// I2C와 유사한 인터페이스를 통해 OV7670 카메라 모듈에 명령을 전송하는 모듈입니다.

module i2c_sender (
    input wire          clk,
    inout wire          siod,
    output reg          sioc,
    output reg          taken,
    input wire          send,
    input wire  [7:0]   id,
    input wire  [7:0]   reg_addr, // reg를 reg_addr로 변경 (Verilog 예약어)
    input wire  [7:0]   value
);ㄴ

    reg [7:0]   divider = 8'd1;
    reg [31:0]  busy_sr = 32'd0;
    reg [31:0]  data_sr = 32'hFFFFFFFF;
    
    // siod는 acknowledge bit 수신을 위해 high-impedance 상태가 되어야 합니다.
    assign siod = ((busy_sr[11:10] == 2'b10) ||
                   (busy_sr[20:19] == 2'b10) ||
                   (busy_sr[29:28] == 2'b10)) ? 1'bz : data_sr[31];

    always @(posedge clk) begin
        taken <= 1'b0;
        if (!busy_sr[31]) begin
            sioc <= 1'b1;
            if (send) begin
                if (divider == 8'd0) begin
                    // 데이터 패킷 구성: Start(100) + ID(8) + ACK(0) + Reg(8) + ACK(0) + Value(8) + ACK(0) + Stop(01)
                    data_sr <= {3'b100, id, 1'b0, reg_addr, 1'b0, value, 1'b0, 2'b01};
                    busy_sr <= 32'hFFFFFFFF; // 모든 비트를 '1'로 설정하여 전송 시작
                    taken   <= 1'b1;
                end else begin
                    divider <= divider + 1; // 파워업 시 초기 딜레이
                end
            end
        end else begin
            // I2C 클럭(sioc) 생성 로직
            casex ({busy_sr[31:29], busy_sr[2:0]})
                6'b111_111: sioc <= 1'b1; // Start sequence #1
                6'b111_110: sioc <= 1'b1; // Start sequence #2
                6'b111_100: sioc <= 1'b0; // Start sequence #3
                6'b110_000: begin // End sequence #1
                    case (divider[7:6])
                        2'b00: sioc <= 1'b0;
                        2'b01: sioc <= 1'b1;
                        2'b10: sioc <= 1'b1;
                        default: sioc <= 1'b1;
                    endcase
                end
                6'b100_000: sioc <= 1'b1; // End sequence #2
                6'b000_000: sioc <= 1'b1; // Idle
                default: begin
                    case (divider[7:6])
                        2'b00: sioc <= 1'b0;
                        2'b01: sioc <= 1'b1;
                        2'b10: sioc <= 1'b1;
                        default: sioc <= 1'b0;
                    endcase
                end
            endcase

            // 1비트 전송 완료 시 시프트 레지스터 이동
            if (divider == 8'hFF) begin
                busy_sr <= {busy_sr[30:0], 1'b0};
                data_sr <= {data_sr[30:0], 1'b1};
                divider <= 8'd0;
            end else begin
                divider <= divider + 1;
            end
        end
    end
endmodule
