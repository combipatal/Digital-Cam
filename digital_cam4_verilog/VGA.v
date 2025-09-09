// VHDL 소스 파일: vga.vhd
// VGA 타이밍 신호 생성기
// Hcnt와 Vcnt를 외부에서 사용할 수 있도록 출력 포트를 추가했습니다.

module VGA (
    input wire          CLK25,      // 25 MHz 입력 클럭
    output wire         clkout,
    output wire         Hsync,
    output wire         Vsync,
    output wire         Nblank,
    output wire         activeArea,
    output wire         Nsync,
    // --- 추가된 출력 포트 ---
    output wire [9:0]   Hcnt_out,
    output wire [9:0]   Vcnt_out
);

    // VGA 타이밍 파라미터 (640x480 @ 60Hz)
    localparam H_DISPLAY      = 640;
    localparam H_FRONT_PORCH  = 16;
    localparam H_SYNC_PULSE   = 96;
    localparam H_BACK_PORCH   = 48;
    localparam H_TOTAL        = H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    localparam V_DISPLAY      = 480;
    localparam V_FRONT_PORCH  = 10;
    localparam V_SYNC_PULSE   = 2;
    localparam V_BACK_PORCH   = 33;
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
    assign Nsync = 1'b1;
    assign clkout = CLK25;
    
    // 카운터 값 외부 출력
    assign Hcnt_out = Hcnt;
    assign Vcnt_out = Vcnt;

endmodule
