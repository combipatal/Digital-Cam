// VGA 타이밍 신호 생성 모듈
// 640x480 @ 60Hz 해상도를 기준으로 Hsync, Vsync 등 VGA 표준 신호를 생성합니다.

module VGA (
    input      CLK25,      // 25.175 MHz 픽셀 클럭
    output     clkout,     // ADV7123 및 TFT 화면으로 나가는 출력 클럭
    output reg Hsync,      // 수평 동기화 신호
    output reg Vsync,      // 수직 동기화 신호
    output     Nblank,     // ADV7123 N/A 컨버터 제어 신호
    output reg activeArea, // 유효 픽셀 데이터 구간 표시
    output     Nsync       // TFT 화면 동기화 및 제어 신호
);

    // --- VGA 640x480 @ 60Hz 타이밍 상수 ---
    // 수평 타이밍 (단위: 픽셀 클럭)
    localparam H_DISPLAY      = 640; // 화면 표시 영역
    localparam H_FRONT_PORCH  = 16;  // Front Porch
    localparam H_SYNC_PULSE   = 96;  // 동기화 펄스 폭
    localparam H_BACK_PORCH   = 48;  // Back Porch
    localparam H_TOTAL        = H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 총 800

    // 수직 타이밍 (단위: 라인)
    localparam V_DISPLAY      = 480; // 화면 표시 영역
    localparam V_FRONT_PORCH  = 10;  // Front Porch
    localparam V_SYNC_PULSE   = 2;   // 동기화 펄스 폭
    localparam V_BACK_PORCH   = 33;  // Back Porch
    localparam V_TOTAL        = V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 총 525

    // 수평(Hcnt), 수직(Vcnt) 카운터
    reg [9:0] Hcnt = 0;
    reg [9:0] Vcnt = 0;

    // --- 카운터 로직 ---
    always @(posedge CLK25) begin
        if (Hcnt == H_TOTAL - 1) begin
            Hcnt <= 0;
            if (Vcnt == V_TOTAL - 1) begin
                Vcnt <= 0;
            end else begin
                Vcnt <= Vcnt + 1;
            end
        end else begin
            Hcnt <= Hcnt + 1;
        end
    end

    // --- Hsync 및 Vsync 신호 생성 ---
    always @(posedge CLK25) begin
        // Hsync: Display + Front Porch 구간 이후 Sync Pulse 구간 동안 low
        if ((Hcnt >= H_DISPLAY + H_FRONT_PORCH) && (Hcnt < H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE))
            Hsync <= 1'b0;
        else
            Hsync <= 1'b1;

        // Vsync: Display + Front Porch 구간 이후 Sync Pulse 구간 동안 low
        if ((Vcnt >= V_DISPLAY + V_FRONT_PORCH) && (Vcnt < V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE))
            Vsync <= 1'b0;
        else
            Vsync <= 1'b1;
    end
    
    // --- Active Area 및 Blank 신호 생성 ---
    // activeArea: 실제 픽셀 데이터가 유효한 640x480 디스플레이 영역
    wire video_on = (Hcnt < H_DISPLAY) && (Vcnt < V_DISPLAY);
    
    // Nblank 신호는 video_on 신호와 동일하게 할당
    assign Nblank = video_on;
    
    // VHDL 코드의 동작을 반영: activeArea는 320x240 영역에서만 활성화
    always @(posedge CLK25) begin
        if ((Hcnt < 320) && (Vcnt < 240))
            activeArea <= 1'b1;
        else
            activeArea <= 1'b0;
    end

    // --- 기타 출력 ---
    assign Nsync = 1'b1;   // ADV7123 제어를 위해 사용 (여기서는 상시 '1')
    assign clkout = CLK25; // 입력 클럭을 그대로 출력

endmodule
