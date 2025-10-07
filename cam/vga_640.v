// VGA 컨트롤러 - 640x480 @ 60Hz, 25MHz 픽셀 클럭
// 320x240 영상을 2배 확대하여 640x480 전체 화면 출력
module vga_640 (
    input  wire CLK25,         // 25MHz 픽셀 클럭 입력
    input  wire [15:0] pixel_data, // 현재 픽셀 데이터 (미사용)
    output wire clkout,        // ADV7123 / TFT 패널 출력 클럭
    output reg  Hsync,         // 수평 동기 신호
    output reg  Vsync,         // 수직 동기 신호
    output wire Nblank,        // DAC 블랭크 제어 신호
    output reg  activeArea,    // 640x480 유효 화면 영역 플래그
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

    // 640x480 전체 유효 영역 및 프리페치 설정
    localparam integer PREFETCH = 5;  // 메모리 읽기 지연 (RAM 2클럭)
    
    // 320x240 원본 영상 좌표 계산 (2배 확대)
    wire [8:0] src_x = Hcnt[9:1];  // Hcnt / 2 (0~319)
    wire [8:0] src_y = Vcnt[9:1];  // Vcnt / 2 (0~239)
    
    // 프리페치를 고려한 읽기 윈도우
    // 640 픽셀 = 320 원본 픽셀 x 2
    // 수평: 0~639, 수직: 0~479 전체 영역
    wire in_active_h = (Hcnt < HD);
    wire in_active_v = (Vcnt < VD);
    
    // 프리페치 구간 계산
    localparam [9:0] H_READ_END = HD - PREFETCH;  // 638
    // 마지막 복제 클럭까지 데이터를 유지하기 위해 <= 사용
    wire read_window = in_active_v && (Hcnt <= H_READ_END);

    // 프레임 버퍼 주소 (320x240 = 76800 픽셀)
    reg [16:0] pixel_addr = 17'h00000;  // 현재 요청할 주소
    assign pixel_address = pixel_addr;  // 상위 모듈에 직접 전달
    
    // 라인 시작 주소 (각 라인의 첫 픽셀 주소)
    reg [16:0] line_start_addr = 17'h00000;
    reg [16:0] next_line_addr = 17'h00000;  // 다음 라인 주소 미리 계산
    
    // 원본 320x240 기준 주소 계산 (2배 확대)
    // 각 원본 픽셀이 2x2로 표시되므로, 2 픽셀마다 주소 증가
    // 각 라인도 2번 반복되므로 홀수 라인에서는 같은 라인 주소 사용
    
    always @(posedge CLK25) begin
        if (Hcnt == HM) begin  // 수평 카운터 종료
            Hcnt <= 10'd0;
            
            // 다음 라인의 시작 주소로 전환
            line_start_addr <= next_line_addr;
            pixel_addr <= next_line_addr;
            
            if (Vcnt == VM) begin  // 프레임 종료
                Vcnt <= 10'd0;
                line_start_addr <= 17'h00000;
                next_line_addr <= 17'h00000;
                pixel_addr <= 17'h00000;
            end else begin
                Vcnt <= Vcnt + 1'b1;
                // 다음 라인 시작 주소 미리 계산
                // 현재가 짝수 라인이면 다음(홀수) 라인은 같은 주소
                // 현재가 홀수 라인이면 다음(짝수) 라인은 320 증가
                if (Vcnt < VD - 1) begin
                    if (Vcnt[0] == 1'b0) begin
                        // 짝수 라인 → 홀수 라인: 같은 주소 유지
                        next_line_addr <= next_line_addr;
                    end else begin
                        // 홀수 라인 → 짝수 라인: 320 증가
                        next_line_addr <= next_line_addr + 17'd320;
                    end
                end
            end
        end else begin
            Hcnt <= Hcnt + 1'b1;
            
            // 프리페치 구간에서 주소 증가
            // 복제의 두 번째 클럭(Hcnt[0]==1)에서만 주소 증가 (2배 확대)
            if (read_window && Hcnt[0] == 1'b1) begin
                if (pixel_addr < 17'd76799) begin
                    pixel_addr <= pixel_addr + 1'b1;
                end
            end
        end
    end
    
    // 640x480 전체 유효 화면 영역 플래그
    always @(posedge CLK25) begin
        if (in_active_h && in_active_v) begin
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

