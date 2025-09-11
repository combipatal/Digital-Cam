// VGA 제어 모듈 - VGA 신호 생성
module VGA(
  input wire rst_n,          // 활성화 낮음 리셋
  input wire CLK25,          // 25MHz 입력 클록
  output wire clkout,        // 출력 클록 (ADV7123 및 TFT 화면용)
  output reg Hsync,          // 수평 동기화 신호
  output reg Vsync,          // 수직 동기화 신호
  output wire Nblank,        // ADV7123 변환기 제어 신호
  output reg activeArea,     // 활성 화면 영역 표시
  output wire Nsync          // TFT 화면 동기화 및 제어 신호
);

  // 내부 신호 선언
  reg [9:0] Hcnt;  // 열 카운터
  reg [9:0] Vcnt;  // 행 카운터
  wire video;
  
  // 상수 선언
  localparam HM = 799;   // 수평 최대 크기
  localparam HD = 640;   // 수평 표시 영역
  localparam HF = 16;    // 수평 프론트 포치
  localparam HB = 48;    // 수평 백 포치
  localparam HR = 96;    // 수평 동기화 시간
  
  localparam VM = 524;   // 수직 최대 크기
  localparam VD = 480;   // 수직 표시 영역
  localparam VF = 10;    // 수직 프론트 포치
  localparam VB = 33;    // 수직 백 포치
  localparam VR = 2;     // 수직 리트레이스
  
  // 초기화
  initial begin
    Hcnt = 10'b0;
    Vcnt = 10'b1000001000;
    activeArea = 1'b0;
  end
  
  // 행/열 카운터 제어
  always @(posedge CLK25 or negedge rst_n) begin
    if (!rst_n) begin
      Hcnt <= 10'b0;
      Vcnt <= 10'b1000001000;
      activeArea <= 1'b0;
    end else begin
      if (Hcnt == HM) begin
        Hcnt <= 10'b0;
        if (Vcnt == VM) begin
          Vcnt <= 10'b0;
          activeArea <= 1'b1;
        end else begin
          if (Vcnt < (240-1))
            activeArea <= 1'b1;
          Vcnt <= Vcnt + 1'b1;
        end
      end else begin
        if (Hcnt == (320-1))
          activeArea <= 1'b0;
        Hcnt <= Hcnt + 1'b1;
      end
    end
  end
  
  // 수평 동기화 신호 생성
  always @(posedge CLK25 or negedge rst_n) begin
    if (!rst_n)
      Hsync <= 1'b1;
    else if ((Hcnt >= (HD+HF)) && (Hcnt <= (HD+HF+HR-1)))
      Hsync <= 1'b0;
    else
      Hsync <= 1'b1;
  end
  
  // 수직 동기화 신호 생성
  always @(posedge CLK25 or negedge rst_n) begin
    if (!rst_n)
      Vsync <= 1'b1;
    else if ((Vcnt >= (VD+VF)) && (Vcnt <= (VD+VF+VR-1)))
      Vsync <= 1'b0;
    else
      Vsync <= 1'b1;
  end
  
  // 기타 신호 생성
  assign Nsync = 1'b1;
  assign video = ((Hcnt < HD) && (Vcnt < VD)) ? 1'b1 : 1'b0;
  assign Nblank = video;
  assign clkout = CLK25;

endmodule