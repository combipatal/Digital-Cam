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
 
// VHDL 소스 파일: ov7670_controller.vhd
// OV7670 카메라 컨트롤러 - I2C 유사 버스를 통해 카메라로 레지스터 값을 전송합니다.

module ov7670_controller (
    input wire          clk,
    input wire          resend,
    output wire         config_finished,
    output wire         sioc,
    inout  wire         siod,
    output wire         reset,
    output wire         pwdn,
    output wire         xclk
);

    localparam [7:0] camera_address = 8'h42; // 카메라 모듈의 I2C 쓰기 주소

    wire [15:0] command;
    wire        finished;
    wire        taken;
    wire        send;
    reg         sys_clk = 1'b0;

    assign config_finished = finished;
    assign send = ~finished;
    assign reset = 1'b1; // Normal mode
    assign pwdn = 1'b0;  // Power device up
    assign xclk = sys_clk;

    // I2C 통신을 통해 레지스터 값을 카메라에 전송하는 모듈
    // 참고: i2c_sender.v 파일이 별도로 필요합니다.
    i2c_sender Inst_i2c_sender (
        .clk    (clk),
        .send   (send),
        .taken  (taken),
        .id     (camera_address),
        .reg_addr    (command[15:8]),
        .value  (command[7:0]),
        .siod   (siod),
        .sioc   (sioc)
    );
    
    // 전송할 레지스터 값 시퀀스를 생성하는 모듈
    ov7670_registers Inst_ov7670_registers (
        .clk      (clk),
        .advance  (taken),
        .resend   (resend),
        .command  (command),
        .finished (finished)
    );

    // 카메라에 외부 클럭(xclk)을 공급하기 위한 클럭 분주
    always @(posedge clk) begin
        sys_clk <= ~sys_clk;
    end

endmodule

// --- i2c_sender 모듈 선언부 (참고용) ---
// 이 컨트롤러를 사용하려면 아래와 같은 인터페이스를 가진 i2c_sender.v 파일이 필요합니다.
/*
module i2c_sender(
    input wire          clk,
    input wire          send,
    output wire         taken,
    input wire  [7:0]   id,
    input wire  [7:0]   reg_addr,
    input wire  [7:0]   value,
    inout wire          siod,
    output wire         sioc
);
    // I2C sender logic
endmodule
*/