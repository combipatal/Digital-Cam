// VGA 컨트롤러 - 640x480 @ 60Hz, 25MHz 픽셀 클럭
module VGA (
    input  wire CLK25,         // 25MHz 클럭 입력
    input  wire [15:0] pixel_data, // 픽셀 데이터 입력
    output wire clkout,        // ADV7123 및 TFT 화면용 클럭 출력
    output reg  Hsync,         // 수평 동기화
    output reg  Vsync,         // 수직 동기화
    output wire Nblank,        // DAC용 블랭킹 신호
    output reg  activeArea,    // 활성 디스플레이 영역 (320x240 윈도우)
    output wire Nsync,         // TFT용 동기화 신호
    output wire [16:0] pixel_address // 현재 픽셀 주소
);

    // VGA 타이밍 파라미터 - 640x480 @ 60Hz
    parameter HM = 799;  // 전체 수평 픽셀 수 - 1
    parameter HD = 640;  // 수평 디스플레이 픽셀 수
    parameter HF = 16;   // 수평 프론트 포치
    parameter HB = 48;   // 수평 백 포치
    parameter HR = 96;   // 수평 동기화 펄스
    
    parameter VM = 524;  // 전체 수직 라인 수 - 1
    parameter VD = 480;  // 수직 디스플레이 라인 수
    parameter VF = 10;   // 수직 프론트 포치
    parameter VB = 33;   // 수직 백 포치
    parameter VR = 2;    // 수직 동기화 펄스
    
    // 카운터들
    reg [9:0] Hcnt = 10'd0;        // 수평 카운터
    reg [9:0] Vcnt = 10'd520;      // 수직 카운터 (520으로 초기화)
    wire video;                    // 비디오 활성 신호
    
    // 픽셀 주소 생성 (320x240 = 76800 픽셀)
    reg [16:0] pixel_addr = 17'h00000;  // 픽셀 주소 카운터
    assign pixel_address = pixel_addr;
    
    // 320x240 윈도우를 위한 픽셀 카운팅
    always @(posedge CLK25) begin
        if (Hcnt == HM) begin  // 라인 끝
            Hcnt <= 10'd0;     // 수평 카운터 리셋
            if (Vcnt == VM) begin  // 프레임 끝
                Vcnt <= 10'd0;     // 수직 카운터 리셋
                pixel_addr <= 17'h00000;  // 픽셀 주소 리셋
            end else begin
                Vcnt <= Vcnt + 1'b1;  // 수직 카운터 증가
            end
        end else begin
            Hcnt <= Hcnt + 1'b1;  // 수평 카운터 증가
        end
        
        // 픽셀 주소 카운팅 (중앙 320x240 활성 영역에서만)
        if ((Hcnt >= 10'd160 && Hcnt < 10'd480) && (Vcnt >= 10'd120 && Vcnt < 10'd360)) begin
            if (pixel_addr < 17'd76799) begin
                pixel_addr <= pixel_addr + 1'b1;  // 다음 픽셀 주소
            end
        end
    end
    
    // 320x240 윈도우를 위한 활성 영역 생성 (중앙 정렬: (160,120) 시작)
    always @(posedge CLK25) begin
        if ((Hcnt >= 10'd160 && Hcnt < 10'd480) && (Vcnt >= 10'd120 && Vcnt < 10'd360)) begin
            activeArea <= 1'b1;  // 활성 영역
        end else begin
            activeArea <= 1'b0;  // 비활성 영역
        end
    end
    
    // 수평 동기화 생성
    always @(posedge CLK25) begin
        if (Hcnt >= (HD + HF) && Hcnt <= (HD + HF + HR - 1))  // 656~751 구간
            Hsync <= 1'b0;  // 수평 동기화 활성 (로우)
        else
            Hsync <= 1'b1;  // 수평 동기화 비활성 (하이)
    end
    
    // 수직 동기화 생성
    always @(posedge CLK25) begin
        if (Vcnt >= (VD + VF) && Vcnt <= (VD + VF + VR - 1))  // 490~491 구간
            Vsync <= 1'b0;  // 수직 동기화 활성 (로우)
        else
            Vsync <= 1'b1;  // 수직 동기화 비활성 (하이)
    end
    
    // 출력 할당
    assign Nsync = 1'b1;  // TFT 동기화 신호 (항상 하이)
    assign video = (Hcnt < HD) && (Vcnt < VD);  // 전체 640x480 해상도
    assign Nblank = video;  // 블랭킹 신호 (비디오 활성과 동일)
    assign clkout = CLK25;  // 클럭 출력
    
endmodule