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

// VHDL 소스 파일: ov7670_capture.vhd
// 이 모듈은 OV7670 카메라로부터 들어오는 프레임의 픽셀 데이터를 캡처하여
// Block RAM에 저장합니다.

module ov7670_capture (
    input wire          pclk,
    input wire          vsync,
    input wire          href,
    input wire  [7:0]   d,
    output wire [16:0]  addr,
    output wire [11:0]  dout,
    output wire         we,
    output wire         end_of_frame
);

    reg [15:0]  d_latch = 16'd0;
    reg [16:0]  address = 17'd0;
    reg [1:0]   line = 2'd0;
    reg [6:0]   href_last = 7'd0;
    reg         we_reg = 1'b0;
    reg         end_of_frame_reg = 1'b0;
    reg         href_hold = 1'b0;
    reg         latched_vsync = 1'b0;
    reg         latched_href = 1'b0;
    reg [7:0]   latched_d = 8'd0;

    assign addr = address;
    assign we = we_reg;
    // RGB565 (16-bit) to RGB444 (12-bit) conversion
    assign dout = {d_latch[15:12], d_latch[10:7], d_latch[4:1]};
    assign end_of_frame = end_of_frame_reg;

    always @(posedge pclk) begin
        if (we_reg) begin
            address <= address + 1;
        end

        // href의 상승 엣지(scan line의 시작) 감지
        if (~href_hold && latched_href) begin
            case (line)
                2'b00: line <= 2'b01;
                2'b01: line <= 2'b10;
                2'b10: line <= 2'b11;
                default: line <= 2'b00;
            endcase
        end
        href_hold <= latched_href;
        
        // 카메라로부터 12-bit RGB 데이터 캡처
        if (latched_href) begin
            d_latch <= {d_latch[7:0], latched_d};
        end
        we_reg <= 1'b0;

        // 새 프레임이 시작되는지 확인 (캡처 재시작)
        if (latched_vsync) begin
            address <= 17'd0;
            href_last <= 7'd0;
            line <= 2'd0;
            end_of_frame_reg <= 1'b1;
        else begin
            // 픽셀을 캡처해야 할 때마다 쓰기 활성화(we_reg) 설정
            if (href_last[2]) begin
                if (line[1]) begin
                    we_reg <= 1'b1;
                end
                href_last <= 7'd0;
            else begin
                href_last <= {href_last[5:0], latched_href};
            end
            end_of_frame_reg <= 1'b0;
        end
    end

    // 입력 신호를 하강 엣지에서 래칭하여 타이밍 문제 방지
    always @(negedge pclk) begin
        latched_d <= d;
        latched_href <= href;
        latched_vsync <= vsync;
    end

endmodule