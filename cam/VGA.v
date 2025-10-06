// VGA 컨트롤러 - 640x480 @ 60Hz, 25MHz 픽셀 클럭
// [개선 사항]
// 1. PREFETCH 값 2 → 8로 증가 (SDRAM + FIFO 지연 보상)
// 2. 주소 생성 로직 안정화

module VGA (
    input  wire CLK25,         // 25MHz 픽셀 클럭 입력
    input  wire [15:0] pixel_data, // 현재 픽셀 데이터 (미사용)
    output wire clkout,        // ADV7123 / TFT 패널 출력 클럭
    output reg  Hsync,         // 수평 동기 신호
    output reg  Vsync,         // 수직 동기 신호
    output wire Nblank,        // DAC 블랭크 제어 신호
    output reg  activeArea,    // 320x240 유효 화면 영역 플래그
    output wire Nsync,         // TFT 동기 보조 신호
    output wire [16:0] pixel_address // 현재 요청할 픽셀 주소
);

    // VGA 타이밍 파라미터 - 640x480 @ 60Hz
    parameter HM = 799;  // 전체 수평 카운트 - 1
    parameter HD = 640;  // 수평 유효 영상 구간
    parameter HF = 16;   // 수평 프런트 포치
    parameter HB = 48;   // 수평 백 포치
    parameter HR = 96;   // 수평 동기 펄스 폭
    
    parameter VM = 524;  // 전체 수직 카운트 - 1
    parameter VD = 480;  // 수직 유효 영상 구간
    parameter VF = 10;   // 수직 프런트 포치
    parameter VB = 33;   // 수직 백 포치
    parameter VR = 2;    // 수직 동기 펄스 폭
    
    // 타이밍 카운터
    reg [9:0] Hcnt = 10'd0;        // 수평 카운터
    reg [9:0] Vcnt = 10'd520;      // 수직 카운터 (520으로 초기화)
    wire video;                    // 전체 VGA 유효 신호

    // 320x240 유효 영역 및 프리페치 설정
    localparam [9:0] H_ACTIVE_START = 10'd160;
    localparam [9:0] H_ACTIVE_END   = 10'd480;
    localparam [9:0] V_ACTIVE_START = 10'd120;
    localparam [9:0] V_ACTIVE_END   = 10'd360;
    
    // *** PREFETCH 증가: 2 → 8 ***
    // SDRAM latency (6-8 clocks @ 100MHz) + FIFO delay (4-5) + CDC (2-3)
    // = 약 12-16 클럭 (100MHz) ≈ 3-4 클럭 (25MHz)
    // 안전 마진 포함하여 8 클럭 프리페치
    localparam integer PREFETCH = 8;
    
    localparam [9:0] H_READ_START = H_ACTIVE_START - PREFETCH; // 152
    localparam [9:0] H_READ_END   = H_ACTIVE_END   - PREFETCH; // 472

    wire in_active_v  = (Vcnt >= V_ACTIVE_START) && (Vcnt < V_ACTIVE_END);
    wire read_window  = in_active_v &&
                        (Hcnt >= H_READ_START) && (Hcnt < H_READ_END);

    // 프레임 버퍼 주소 (320x240 = 76800 픽셀)
    reg [16:0] pixel_addr = 17'h00000;  // 현재 요청할 주소
    assign pixel_address = pixel_addr;  // 상위 모듈에 직접 전달
    
    // 320x240 영역 기준 주소 및 타이밍 카운터
    always @(posedge CLK25) begin
        if (Hcnt == HM) begin  // 수평 카운터 종료
            Hcnt <= 10'd0;
            if (Vcnt == VM) begin  // 프레임 종료
                Vcnt <= 10'd0;
                pixel_addr <= 17'h00000;  // 새 프레임 시작 시 주소 리셋
            end else begin
                Vcnt <= Vcnt + 1'b1;
            end
        end else begin
            Hcnt <= Hcnt + 1'b1;
        end
        
        // 프리페치 구간에서 주소 증가
        if (read_window) begin
            if (pixel_addr < 17'd76799) begin
                pixel_addr <= pixel_addr + 1'b1;
            end
        end
    end
    
    // 320x240 유효 화면 영역 플래그 (센터 기준: 160,120 시작)
    always @(posedge CLK25) begin
        if ((Hcnt >= H_ACTIVE_START && Hcnt < H_ACTIVE_END) && in_active_v) begin
            activeArea <= 1'b1;
        end else begin
            activeArea <= 1'b0;
        end
    end
    
    // 수평 동기 생성
    always @(posedge CLK25) begin
        if (Hcnt >= (HD + HF) && Hcnt <= (HD + HF + HR - 1))  // 656~751 구간
            Hsync <= 1'b0;
        else
            Hsync <= 1'b1;
    end
    
    // 수직 동기 생성
    always @(posedge CLK25) begin
        if (Vcnt >= (VD + VF) && Vcnt <= (VD + VF + VR - 1))  // 490~491 구간
            Vsync <= 1'b0;
        else
            Vsync <= 1'b1;
    end
    
    // 출력 제어
    assign Nsync = 1'b1;  // TFT 동기 입력은 상시 하이 유지
    assign video = (Hcnt < HD) && (Vcnt < VD);  // 전체 640x480 유효 영상
    assign Nblank = video;  // 블랭크 신호: 유효 영상 구간에만 하이
    assign clkout = CLK25;  // 픽셀 클럭 그대로 출력
    
endmodule