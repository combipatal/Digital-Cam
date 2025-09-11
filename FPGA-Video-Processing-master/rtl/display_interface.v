//=============================================================
// display_interface 모듈
// 목적: 프레임 버퍼의 이미지 데이터를 HDMI 출력 형식으로 변환
// 기능: 
// - 프레임 버퍼 읽기 제어
// - 컬러/그레이스케일 모드 전환
// - HDMI 타이밍 생성 및 출력
//=============================================================
module display_interface 
    (
    input  wire        i_p_clk,      // 픽셀 클럭 입력 (기본 디스플레이 타이밍용)
    input  wire        i_tmds_clk,   // TMDS 클럭 입력 (픽셀 클럭의 10배)
    input  wire        i_rstn,       // 시스템 리셋 (active low)
    input  wire        i_mode,       // 출력 모드 선택 (1: 그레이스케일, 0: 컬러)

    // frame buffer interface
    output reg  [16:0] o_raddr,      // 프레임 버퍼 읽기 주소 (640*480 = 307,200)
    input  wire [11:0] i_rdata,      // 프레임 버퍼로부터 읽은 픽셀 데이터

    // VGA
    output wire [7:0]  o_VGA_R,
    output wire [7:0]  o_VGA_G,
    output wire [7:0]  o_VGA_B,
    output wire        o_VGA_HS,
    output wire        o_VGA_VS
    );


// =============================================================
//              내부 신호 및 레지스터 정의
// =============================================================
    reg  [16:0] nxt_raddr;           // 다음 프레임 버퍼 읽기 주소

    wire        vsync, hsync, active; // 수직/수평 동기화, 화면 활성 신호
    wire [9:0]  counterX, counterY;   // 현재 픽셀의 X/Y 좌표
    reg  [7:0]  red, green, blue;     // 8비트 RGB 색상 값
    reg  [1:0]  STATE, NEXT_STATE;
    localparam  STATE_INITIAL = 0,
                STATE_DELAY   = 1,
                STATE_IDLE    = 3,
                STATE_ACTIVE  = 2;
 
    //=============================================================
    // RGB 색상 할당
    // i_mode에 따라 그레이스케일 또는 컬러 모드로 변환
    // 그레이스케일: 모든 RGB 채널에 동일한 값 할당
    // 컬러: 12비트 데이터를 4비트씩 분리하여 RGB 채널에 할당
    always@* begin
        if(i_mode) begin
            red   = i_rdata;          // 그레이스케일 모드
            green = i_rdata;          // 모든 채널에
            blue  = i_rdata;          // 동일한 값 할당
        end
        else begin
            red   = {i_rdata[11:8], {4'hF} }; // 상위 4비트 + 밝기 보정
            green = {i_rdata[7:4],  {4'hF} }; // 중간 4비트 + 밝기 보정
            blue  = {i_rdata[3:0],  {4'hF} }; // 하위 4비트 + 밝기 보정
        end
    end

    // 상태 머신 조합 로직
    // 프레임 버퍼 읽기 주소와 상태 전이를 제어
    always@* begin
        nxt_raddr  = o_raddr;         // 기본값: 현재 주소 유지
        NEXT_STATE = STATE;           // 기본값: 현재 상태 유지
        case(STATE)

            // 초기 상태: 카메라 설정을 위해 2프레임 대기
            // 한 프레임(640x480)이 완료되면 STATE_DELAY로 전환
            STATE_INITIAL: begin
                NEXT_STATE = ((counterX == 320) && (counterY == 240)) ? STATE_DELAY:STATE_INITIAL; // 이전: 640, 480
            end

            STATE_DELAY: begin
                NEXT_STATE = ((counterX == 320) && (counterY == 240)) ? STATE_ACTIVE:STATE_DELAY; // 이전: 640, 480
            end
            
            STATE_IDLE: begin
                if((counterX == 415)&&((counterY==254)||(counterY<240))) begin // 이전: 799, 524, 480
                    nxt_raddr  = o_raddr + 1;
                    NEXT_STATE = STATE_ACTIVE;
                end
                else if(counterY > 239) begin // 이전: 479
                    nxt_raddr = 0;
                end
            end
               // 활성 상태: 프레임 버퍼에서 데이터 읽기
            STATE_ACTIVE: begin
                // 활성 영역이고 현재 라인 내부인 경우
                if(active && (counterX < 319)) begin // 이전: 639
                    // 마지막 픽셀(307199)이면 처음으로, 아니면 다음 주소로
                    nxt_raddr = (o_raddr == 76799) ? 0:o_raddr+1; // 이전: 307199
                end
                else begin
                    NEXT_STATE = STATE_IDLE;   // 대기 상태로 전환
                end
            end
        endcase
    end

    // registered logic
    always@(posedge i_p_clk) begin
        if(!i_rstn) begin
            o_raddr <= 0;
            STATE <= STATE_DELAY;
        end else begin
            o_raddr <= nxt_raddr;
            STATE   <= NEXT_STATE;
        end
    end
 // --- 기존 vtc 인스턴스 유지 ---
    // Video Timing Controller: hsync, vsync, active 신호를 생성합니다.
    vtc #(
    .COUNTER_WIDTH(10)
    )
    vtc_i (
    .i_clk         (i_p_clk  ),
    .i_rstn        (i_rstn   ), 
    .o_vsync       (vsync    ),
    .o_hsync       (hsync    ),
    .o_active      (active   ), // 화면에 픽셀이 표시되는 유효 영역
    .o_counterX    (counterX ),
    .o_counterY    (counterY )
    );

    // --- 수정된 부분: VGA 신호 할당 ---
    assign o_VGA_HS = hsync;
    assign o_VGA_VS = vsync;

    // 'active' 기간에만 RGB 데이터를 출력하고, 그 외 (blanking 기간)에는 검은색(0)을 출력합니다.
    // DE2-115의 DAC는 10비트이므로, 8비트 RGB 데이터를 상위 비트에 맞춰 확장합니다. (8'b_rrrr_rrrr -> 10'b_rrrr_rrrr_00)
    assign o_VGA_R = active ? red : 8'd0;
    assign o_VGA_G = active ? green : 8'd0;
    assign o_VGA_B = active ? blue : 8'd0;
    
endmodule