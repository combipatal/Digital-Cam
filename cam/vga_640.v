// =================================================================================
// VGA 컨트롤러 (vga_640)
// =================================================================================
// 이 모듈은 320x240 해상도의 소스 이미지를 640x480@60Hz VGA 표준에 맞게
// 2배 업스케일링(Nearest Neighbour 방식)하여 출력하는 역할을 합니다.
//
// 주요 기능:
// 1. 640x480@60Hz VGA 타이밍 신호(Hsync, Vsync 등)를 생성합니다.
// 2. 현재 VGA 화면의 픽셀 좌표(640x480)를 소스 프레임 버퍼의 주소(320x240)에 매핑합니다.
// 3. 업스케일링을 위해 각 픽셀과 라인을 두 번씩 반복하여 읽도록 주소를 계산합니다.
//    - 예: 소스 (x, y) -> 화면 (2x, 2y), (2x+1, 2y), (2x, 2y+1), (2x+1, 2y+1)
// 4. 'activeArea' 신호를 통해 현재 유효한 디스플레이 영역(640x480)을 하위 모듈에 알립니다.
// =================================================================================
module vga_640 (
    input  wire        CLK25,          // 25.175MHz의 픽셀 클럭 입력
    output wire        clkout,         // 비디오 DAC(ADV7123)으로 전달되는 픽셀 클럭
    output reg         Hsync,          // 수평 동기화 신호 (active-low)
    output reg         Vsync,          // 수직 동기화 신호 (active-low)
    output wire        Nblank,         // 블랭킹 신호 (active-high, 유효 영상 구간에서 1)
    output reg         activeArea,     // 유효 영상 구간(640x480) 표시 신호
    output reg [16:0]  pixel_address   // 프레임 버퍼에서 읽어올 픽셀 주소 (320x240 기준)
);

    // --- 640x480 @ 60Hz VGA 타이밍 파라미터 ---
    // 수평 타이밍 (단위: 픽셀 클럭)
    localparam integer HM = 799;  // 전체 수평 길이 (800) - 1
    localparam integer HD = 640;  // 수평 해상도 (화면에 보이는 영역)
    localparam integer HF = 16;   // 수평 프론트 포치 (Sync 펄스 전 대기 시간)
    localparam integer HR = 96;   // 수평 Sync 펄스 폭
    localparam integer HB = 48;   // 수평 백 포치 (Sync 펄스 후 대기 시간)

    // 수직 타이밍 (단위: 라인)
    localparam integer VM = 524;  // 전체 수직 길이 (525) - 1
    localparam integer VD = 480;  // 수직 해상도 (화면에 보이는 영역)
    localparam integer VF = 10;   // 수직 프론트 포치
    localparam integer VR = 2;    // 수직 Sync 펄스 폭
    localparam integer VB = 33;   // 수직 백 포치

    // --- 수평/수직 카운터 ---
    // Hcnt: 현재 픽셀의 수평 위치 (0 ~ 799)
    // Vcnt: 현재 픽셀의 수직 위치 (0 ~ 524)
    reg [9:0] Hcnt = 10'd0;
    reg [9:0] Vcnt = 10'd0;

    // --- 타이밍 카운터 증가 로직 ---
    always @(posedge CLK25) begin
        if (Hcnt == HM) begin // 한 라인의 끝에 도달하면
            Hcnt <= 10'd0;      // 수평 카운터 리셋
            if (Vcnt == VM) begin // 한 프레임의 끝에 도달하면
                Vcnt <= 10'd0;    // 수직 카운터 리셋
            end else begin
                Vcnt <= Vcnt + 1'b1; // 다음 라인으로 이동
            end
        end else begin
            Hcnt <= Hcnt + 1'b1; // 다음 픽셀로 이동
        end
    end

    // --- VGA 동기화 신호 생성 로직 (Active Low) ---
    // Hsync 생성: 수평 Sync 펄스 구간에서 0, 나머지 구간에서 1
    always @(posedge CLK25) begin
        if (Hcnt >= (HD + HF) && Hcnt < (HD + HF + HR))
            Hsync <= 1'b0;
        else
            Hsync <= 1'b1;
    end

    // Vsync 생성: 수직 Sync 펄스 구간에서 0, 나머지 구간에서 1
    always @(posedge CLK25) begin
        if (Vcnt >= (VD + VF) && Vcnt < (VD + VF + VR))
            Vsync <= 1'b0;
        else
            Vsync <= 1'b1;
    end

    // --- 유효 영상 구간 신호 생성 ---
    // video_active: Hcnt와 Vcnt가 실제 화면 표시 영역(640x480) 내에 있을 때 1
    wire video_active = (Hcnt < HD) && (Vcnt < VD);
    
    // Nblank: video_active와 동일. 이름 그대로 Blank가 아닌(Not Blank) 구간을 의미
    assign Nblank = video_active;
    
    // clkout: 입력 클럭을 그대로 DAC 클럭으로 사용
    assign clkout = CLK25;
    
    // 640x480 화면 좌표(Hcnt, Vcnt)를 320x240 소스 좌표(src_x, src_y)로 변환
    wire [8:0] src_x = Hcnt[9:1];      // 640 -> 320 (0..319)
    wire [8:0] src_y = Vcnt[9:1];      // 480 -> 240 (0..239)

    // 1차원 배열인 프레임 버퍼의 주소를 계산: address = (y * 너비) + x
    wire [16:0] line_base = {src_y, 8'b0} + {src_y, 6'b0};
    
    // HACK: 시스템의 다른 부분에 존재하는 알 수 없는 -1 오프셋으로 인해 발생하는
    // 화면 깨짐 현상을 보정하기 위해 주소에 1을 더함. 이는 증상을 해결하기 위한 임시방편.
    wire [16:0] addr_next = line_base + {8'b0, src_x} + 17'd1;
    
    always @(posedge CLK25) begin
        activeArea <= video_active;
        if (video_active)
            pixel_address <= addr_next;
        else
            pixel_address <= 17'd0;
    end

endmodule
