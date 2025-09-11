// OV7670 카메라 컨트롤러 - 카메라 초기화 및 레지스터 설정
module ov7670_controller(
  input wire clk,
  input wire resend,
  output wire config_finished,
  output wire sioc,
  inout wire siod,
  output wire reset,    // 카메라 리셋 신호 (높을 때 정상 동작)
  output wire pwdn,
  output wire xclk
);

  // 내부 신호
  wire [15:0] command;
  wire finished;
  wire taken;
  wire send;
  reg sys_clk;
  
  // 카메라 주소 (OV7670 데이터시트 참조)
  localparam camera_address = 8'h42;
  
  // 상태 및 출력 할당
  assign config_finished = finished;
  assign send = ~finished;
  
  // I2C 송신기
  i2c_sender i2c_sender_inst(
    .clk(clk),
    .rst_n(reset),       // 리셋 신호 연결 추가
    .taken(taken),
    .siod(siod),
    .sioc(sioc),
    .send(send),
    .id(camera_address),
    .reg_addr(command[15:8]),
    .value(command[7:0])
  );
  
  // 카메라 제어 신호
  assign reset = 1'b1;  // 정상 모드
  assign pwdn = 1'b0;   // 파워 켜기
  assign xclk = sys_clk;
  
  // 레지스터 설정
  ov7670_registers registers_inst(
    .clk(clk),
    .rst_n(reset),    // 리셋 신호 연결 추가
    .advance(taken),
    .command(command),
    .finished(finished),
    .resend(resend)
  );
  
  // 시스템 클록 생성
  always @(posedge clk or negedge reset) begin
    if (!reset)
      sys_clk <= 1'b0;
    else
      sys_clk <= ~sys_clk;
  end

endmodule