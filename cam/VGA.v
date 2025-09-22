// VGA 컨트롤러 - 640x480 @ 60Hz 타이밍 생성
// 25MHz 픽셀 클럭을 기반으로 VGA 모니터에 필요한 동기화 신호(Hsync, Vsync) 및
// 320x240 해상도의 영상을 화면 중앙에 표시하기 위한 주소와 제어 신호를 생성합니다.
module VGA (
    input  wire        CLK25,         // 25MHz 클럭 입력
    input  wire [15:0] pixel_data,    // RAM에서 읽어온 픽셀 데이터 (현재 모듈에서는 미사용)
    output wire        clkout,        // ADV7123 비디오 인코더 및 TFT 화면용 클럭 출력
    output reg         Hsync,         // 수평 동기화 신호
    output reg         Vsync,         // 수직 동기화 신호
    output wire        Nblank,        // DAC용 블랭킹 신호 (active low)
    output reg         activeArea,    // 320x240 영상의 유효 디스플레이 영역
    output wire        Nsync,         // TFT용 동기화 신호 (여기서는 미사용, 고정값 출력)
    output wire [16:0] pixel_address  // 프레임 버퍼에서 읽어올 픽셀 주소
);

    // VGA 타이밍 파라미터 (640x480 @ 60Hz 기준)
    // 수평 타이밍 (단위: 픽셀 클럭)
    parameter H_TOTAL   = 800; // 전체 한 라인 길이 (Hsync 포함)
    parameter H_DISPLAY = 640; // 화면에 표시되는 픽셀 수
    parameter H_FP      = 16;  // 수평 프론트 포치 (Front Porch)
    parameter H_SYNC    = 96;  // 수평 동기화 펄스 폭
    parameter H_BP      = 48;  // 수평 백 포치 (Back Porch)

    // 수직 타이밍 (단위: 라인)
    parameter V_TOTAL   = 525; // 전체 프레임 라인 수 (Vsync 포함)
    parameter V_DISPLAY = 480; // 화면에 표시되는 라인 수
    parameter V_FP      = 10;  // 수직 프론트 포치
    parameter V_SYNC    = 2;   // 수직 동기화 펄스 폭
    parameter V_BP      = 33;  // 수직 백 포치

    // 수평/수직 카운터
    reg [9:0] H_count = 10'd0; // 수평 카운터 (0 ~ H_TOTAL-1)
    reg [9:0] V_count = 10'd0; // 수직 카운터 (0 ~ V_TOTAL-1)
    
    // 320x240 영상을 중앙에 표시하기 위한 시작 좌표
    localparam H_START = (H_DISPLAY - 320) / 2; // (640-320)/2 = 160
    localparam V_START = (V_DISPLAY - 240) / 2; // (480-240)/2 = 120

    // 프레임 버퍼 주소 카운터
    reg [16:0] pixel_addr_reg = 17'h00000;
    assign pixel_address = pixel_addr_reg;
    
    // 카운터 및 주소 생성 로직
    always @(posedge CLK25) begin
        // 수평 카운터
        if (H_count == H_TOTAL - 1) begin
            H_count <= 10'd0;
            // 수직 카운터
            if (V_count == V_TOTAL - 1) begin
                V_count <= 10'd0;
            end else begin
                V_count <= V_count + 1'b1;
            end
        end else begin
            H_count <= H_count + 1'b1;
        end

        // 프레임 시작 시 픽셀 주소 리셋
        if (V_count == V_TOTAL - 1 && H_count == H_TOTAL - 1) begin
             pixel_addr_reg <= 17'h00000;
        end
        // 320x240 활성 영역 내에서만 픽셀 주소 증가
        else if (activeArea) begin
            if (pixel_addr_reg < 17'd76799) begin // 320*240 - 1
                pixel_addr_reg <= pixel_addr_reg + 1'b1;
            end
        end
    end
    
    // 320x240 윈도우를 위한 'activeArea' 신호 생성
    // (160, 120)에서 시작하여 (479, 359)에서 끝남
    always @(posedge CLK25) begin
        if ((H_count >= H_START) && (H_count < (H_START + 320)) &&
            (V_count >= V_START) && (V_count < (V_START + 240))) begin
            activeArea <= 1'b1;
        end else begin
            activeArea <= 1'b0;
        end
    end
    
    // 수평 동기화(Hsync) 신호 생성 (Active Low)
    always @(posedge CLK25) begin
        // Hsync 펄스 구간: (Display + Front Porch) ~ (Display + FP + Sync Pulse - 1)
        if (H_count >= (H_DISPLAY + H_FP) && H_count < (H_DISPLAY + H_FP + H_SYNC))
            Hsync <= 1'b0;
        else
            Hsync <= 1'b1;
    end
    
    // 수직 동기화(Vsync) 신호 생성 (Active Low)
    always @(posedge CLK25) begin
        // Vsync 펄스 구간: (Display + Front Porch) ~ (Display + FP + Sync Pulse - 1)
        if (V_count >= (V_DISPLAY + V_FP) && V_count < (V_DISPLAY + V_FP + V_SYNC))
            Vsync <= 1'b0;
        else
            Vsync <= 1'b1;
    end
    
    // 기타 출력 신호 할당
    assign Nsync = 1'b1; // TFT용 동기화 신호, 여기서는 사용하지 않으므로 High로 고정
    
    // 비디오 활성 영역 (전체 640x480)
    wire video_on = (H_count < H_DISPLAY) && (V_count < V_DISPLAY);
    assign Nblank = video_on; // 블랭킹 신호. 비디오가 활성일 때 High.
    
    assign clkout = CLK25; // 클럭 출력

endmodule