// OV7670 레지스터 모듈과 I2C 송신 모듈을 제어하는 컨트롤러
// resend 신호를 i2c_sender의 리셋에 연결하도록 수정되었습니다.

module ov7670_controller (
    input clk,
    input resend,
    output config_finished,
    output sioc,
    inout siod,
    output reset,
    output pwdn,
    output xclk
);

    wire [15:0] command;
    wire finished;
    wire taken;
    wire send;
    
    // 카메라의 I2C 쓰기 주소
    localparam CAMERA_ADDRESS = 8'h42;

    assign config_finished = finished;
    assign send = ~finished;

    // 카메라의 전원(pwdn) 및 리셋 신호 제어
    assign reset = 1'b1; // Normal mode
    assign pwdn = 1'b0;  // Power device up

    // 50MHz clk을 분주하여 25MHz의 xclk 생성
    reg sys_clk = 1'b0;
    always @(posedge clk) begin
        sys_clk <= ~sys_clk;
    end
    assign xclk = sys_clk;

    // I2C 송신 모듈 인스턴스
    i2c_sender Inst_i2c_sender (
        .clk(clk),
        .reset(resend), // [수정] resend 스위치 신호를 i2c_sender의 리셋으로 연결
        .taken(taken),
        .siod(siod),
        .sioc(sioc),
        .send(send),
        .id(CAMERA_ADDRESS),
        .reg_addr(command[15:8]),
        .value(command[7:0])
    );

    // 카메라 레지스터 ROM 모듈 인스턴스
    ov7670_registers Inst_ov7670_registers (
        .clk(clk),
        .advance(taken),
        .command(command),
        .finished(finished),
        .resend(resend)
    );

endmodule

