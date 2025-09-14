module VGA(
  input wire CLK25,         // 25MHz 입력 클럭
  output wire clkout,       // ADV7123 및 TFT 화면으로 출력 클럭
  output reg Hsync,         // VGA 화면용 수평 동기화 신호
  output reg Vsync,         // VGA 화면용 수직 동기화 신호
  output wire Nblank,       // ADV7123 N/A 변환기 제어 신호
  output reg activeArea,    // 활성화 영역 표시
  output wire Nsync         // TFT 화면 동기화 및 제어 신호
);

  // 내부 신호 선언
  reg [9:0] Hcnt = 10'b0;     // 열 카운터
  reg [9:0] Vcnt = 10'h208;   // 행 카운터
  wire video;
  
  // 상수 정의
  localparam HM = 799;  // 최대 수평 크기 (800)
  localparam HD = 640;  // 디스플레이 수평 크기
  localparam HF = 16;   // 프론트 포치
  localparam HB = 48;   // 백 포치
  localparam HR = 96;   // 동기화 시간
  localparam VM = 524;  // 최대 수직 크기 (525)
  localparam VD = 480;  // 디스플레이 수직 크기
  localparam VF = 10;   // 프론트 포치
  localparam VB = 33;   // 백 포치
  localparam VR = 2;    // 리트레이스

  // 열/행 카운터 프로세스
  always @(posedge CLK25) begin
    if (Hcnt == HM) begin
      Hcnt <= 10'b0;
      if (Vcnt == VM) begin
        Vcnt <= 10'b0;
        activeArea <= 1'b1;
      end else begin
        if (Vcnt < 240-1) begin
          activeArea <= 1'b1;
        end
        Vcnt <= Vcnt + 1;
      end
    end else begin
      if (Hcnt == 320-1) begin
        activeArea <= 1'b0;
      end
      Hcnt <= Hcnt + 1;
    end
  end

  // 수평 동기화 신호 생성
  always @(posedge CLK25) begin
    if (Hcnt >= (HD+HF) && Hcnt <= (HD+HF+HR-1)) begin // Hcnt >= 656 && Hcnt <= 751
      Hsync <= 1'b0;
    end else begin
      Hsync <= 1'b1;
    end
  end

  // 수직 동기화 신호 생성
  always @(posedge CLK25) begin
    if (Vcnt >= (VD+VF) && Vcnt <= (VD+VF+VR-1)) begin // Vcnt >= 490 && Vcnt <= 491
      Vsync <= 1'b0;
    end else begin
      Vsync <= 1'b1;
    end
  end

  // ADV7123 변환기 제어 신호
  assign Nsync = 1'b1;
  assign video = ((Hcnt < HD) && (Vcnt < VD)) ? 1'b1 : 1'b0; // 640x480 전체 해상도 사용
  assign Nblank = video;
  assign clkout = CLK25;

endmodule
