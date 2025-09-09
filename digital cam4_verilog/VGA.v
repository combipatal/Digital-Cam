// VHDL 소스 파일: vga.vhd
// VGA 타이밍 신호 생성기

module VGA (
    input wire          CLK25,      // 25 MHz 입력 클럭
    output wire         clkout,     // 출력 클럭
    output wire         Hsync,      // 수평 동기화 신호
    output wire         Vsync,      // 수직 동기화 신호
    output wire         Nblank,     // Blank 신호 (active high)
    output wire         activeArea, // 유효 데이터 표시 영역 신호
    output wire         Nsync       // Sync 신호 (TFT용)
);

    // VGA 타이밍 파라미터 (640x480 @ 60Hz 기준)
    // 수평 타이밍 (Horizontal)
    localparam H_DISPLAY      = 640; // 표시 영역
    localparam H_FRONT_PORCH  = 16;  // Front Porch
    localparam H_SYNC_PULSE   = 96;  // Sync Pulse
    localparam H_BACK_PORCH   = 48;  // Back Porch
    localparam H_TOTAL        = H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    // 수직 타이밍 (Vertical)
    localparam V_DISPLAY      = 480; // 표시 영역
    localparam V_FRONT_PORCH  = 10;  // Front Porch
    localparam V_SYNC_PULSE   = 2;   // Sync Pulse
    localparam V_BACK_PORCH   = 33;  // Back Porch
    localparam V_TOTAL        = V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

    reg [9:0] Hcnt = 0; // 수평 카운터
    reg [9:0] Vcnt = 0; // 수직 카운터

    // 수평 및 수직 카운터 로직
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

    // Hsync, Vsync 신호 생성 (active low)
    assign Hsync = ~((Hcnt >= H_DISPLAY + H_FRONT_PORCH) && (Hcnt < H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE));
    assign Vsync = ~((Vcnt >= V_DISPLAY + V_FRONT_PORCH) && (Vcnt < V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE));

    // 유효 데이터 표시 영역(activeArea) 신호 생성
    assign activeArea = (Hcnt < H_DISPLAY) && (Vcnt < V_DISPLAY);
    
    // 기타 출력 신호
    assign Nblank = activeArea;
    assign Nsync = 1'b1; // ADV7123용 신호
    assign clkout = CLK25;

endmodule