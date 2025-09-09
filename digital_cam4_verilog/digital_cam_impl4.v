// VHDL 소스 파일: top_level.vhd
// 프로젝트 이름: "digital cam implementation #4"
// [최종 진단용 버전] 흑백 필터만 테스트하도록 FSM을 단순화

module digital_cam_impl4 (
    // Clock and Reset
    input wire          clk_50,
    input wire          btn_RESET, // KEY0; manual reset

    // User Controls
    input wire          slide_sw_resend_reg_values,
    input wire          slide_sw_NORMAL_OR_EDGEDETECT, // 0: normal, 1: edge detection

    // VGA Interface
    output wire         vga_hsync,
    output wire         vga_vsync,
    output wire [7:0]   vga_r,
    output wire [7:0]   vga_g,
    output wire [7:0]   vga_b,
    output wire         vga_blank_N,
    output wire         vga_sync_N,
    output wire         vga_CLK,

    // OV7670 Camera Interface
    input wire          ov7670_pclk,
    output wire         ov7670_xclk,
    input wire          ov7670_vsync,
    input wire          ov7670_href,
    input wire  [7:0]   ov7670_data,
    output wire         ov7670_sioc,
    inout  wire         ov7670_siod,
    output wire         ov7670_pwdn,
    output wire         ov7670_reset,

    // Status LEDs
    output wire         LED_config_finished,
    output wire         LED_dll_locked,
    output wire         LED_done
);
// --- Internal Wires and Regs ---
    wire clk_100, clk_100_3ns, clk_50_camera, clk_25_vga, dll_locked;
    wire done_BW, done_ED, done_capture_new_frame;
    reg  done_capture_sync_r1, done_capture_sync_r2;
    wire done_capture_new_frame_sync;
    wire clk_buf1_write;

    // Frame Buffer 1 signals
    reg         wren_buf_1;
    reg [16:0]  wraddress_buf_1;
    reg [11:0]  wrdata_buf_1;
    reg [16:0]  rdaddress_buf_1;
    wire [11:0] rddata_buf_1;
    wire [16:0] rdaddress_buf12_from_addr_gen;
    wire [16:0] rdaddress_buf1_from_do_BW;
    wire [16:0] rdaddress_buf1_from_do_ED;
    wire        wren_buf1_from_ov7670_capture;
    wire [16:0] wraddress_buf1_from_ov7670_capture;
    wire [11:0] wrdata_buf1_from_ov7670_capture;
    wire        wren_buf1_from_do_BW;
    wire [16:0] wraddress_buf1_from_do_BW;
    wire [11:0] wrdata_buf1_from_do_BW;

    // Frame Buffer 2 signals
    reg         wren_buf_2;
    reg [16:0]  wraddress_buf_2;
    reg [11:0]  wrdata_buf_2;
    reg [16:0]  rdaddress_buf_2;
    wire [11:0] rddata_buf_2;
    wire        wren_buf2_from_do_ED;
    wire [16:0] wraddress_buf2_from_do_ED;
    wire [11:0] wrdata_buf2_from_do_ED;

    // User controls
    wire resend_reg_values;
    wire normal_or_edgedetect;
    wire reset_manual, reset_automatic, reset_global;

    // FSM control signals
    reg  call_black_white;
    reg  call_edge_detection;

    // VGA signals
    wire [7:0] red, green, blue;
    wire nBlank, vsync;
    reg [11:0] data_to_rgb;
    wire [9:0] vga_hcnt, vga_vcnt;
    wire image_enable;

    // --- [수정] FSM 상태 정의 (4비트 확장 및 S8 추가) ---
    localparam [3:0] S0_RESET               = 4'd0,
                     S1_RESET_BW            = 4'd1,
                     S2_PROCESS_BW          = 4'd2,
                     S3_DONE_BW             = 4'd3,
                     S4_RESET_ED            = 4'd4,
                     S5_PROCESS_ED          = 4'd5,
                     S6_DONE_ED             = 4'd6,
                     S7_NORMAL_VIDEO_MODE   = 4'd7,
                     S8_DISPLAY_HOLD        = 4'd8;
    reg [3:0] state_current, state_next;

    // --- [수정] FSM 상태 레지스터 ---
    always @(posedge clk_25_vga or posedge reset_global) begin
        if (reset_global) begin
            state_current <= S7_NORMAL_VIDEO_MODE;
        end else begin
            state_current <= state_next;
        end
    end

    // --- [수정] FSM Next State Logic (흑백만 테스트하는 최종 진단용 버전) ---
        always @(*) begin
        // --- 기본값 설정 ---
        state_next = state_current;
        call_black_white = 1'b0;
        call_edge_detection = 1'b0;
        
        // 데이터 경로 기본 설정: 평상시에는 카메라 라이브 영상을 버퍼1에 쓰고, 버퍼1을 표시
        wren_buf_1 = wren_buf1_from_ov7670_capture;
        wraddress_buf_1 = wraddress_buf1_from_ov7670_capture;
        wrdata_buf_1 = wrdata_buf1_from_ov7670_capture;
        rdaddress_buf_1 = rdaddress_buf12_from_addr_gen;
        wren_buf_2 = 1'b0;
        rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
        data_to_rgb = rddata_buf_1;

        case (state_current)
            S7_NORMAL_VIDEO_MODE: begin
                // 스위치를 올리면 처리 시작
                if (normal_or_edgedetect) begin
                    state_next = S0_RESET;
                end
            end
            
            S0_RESET:       state_next = S1_RESET_BW;
            S1_RESET_BW:    state_next = S2_PROCESS_BW;

            S2_PROCESS_BW: begin
                call_black_white = 1'b1;
                // BW 모듈이 버퍼1을 읽고 쓰도록 제어권을 넘겨줌
                wren_buf_1 = wren_buf1_from_do_BW;
                wraddress_buf_1 = wraddress_buf1_from_do_BW;
                wrdata_buf_1 = wrdata_buf1_from_do_BW;
                rdaddress_buf_1 = rdaddress_buf1_from_do_BW;
                
                // BW 처리가 끝나면 다음 단계로
                if (done_BW) begin
                    state_next = S3_DONE_BW;
                end
            end

            S3_DONE_BW:     state_next = S4_RESET_ED;
            S4_RESET_ED:    state_next = S5_PROCESS_ED;

            S5_PROCESS_ED: begin
                call_edge_detection = 1'b1;
                // ED 모듈이 버퍼1을 읽고, 버퍼2에 쓰도록 제어권을 넘겨줌
                rdaddress_buf_1 = rdaddress_buf1_from_do_ED;
                wren_buf_1 = 1'b0; // ED 처리중에는 버퍼1에 쓰지 않음
                
                wren_buf_2 = wren_buf2_from_do_ED;
                wraddress_buf_2 = wraddress_buf2_from_do_ED;
                wrdata_buf_2 = wrdata_buf2_from_do_ED;
                
                // 처리 중에는 이전 결과(버퍼2)를 보여줌 (초기엔 검은화면)
                data_to_rgb = rddata_buf_2;

                // ED 처리가 끝나면 다음 단계로
                if (done_ED) begin
                    state_next = S6_DONE_ED;
                end
            end

            S6_DONE_ED:     state_next = S8_DISPLAY_HOLD;

            S8_DISPLAY_HOLD: begin
                // 모든 처리가 끝난 후, 최종 결과물(버퍼2)을 계속 보여주며 멈춤
                state_next = S8_DISPLAY_HOLD;
                data_to_rgb = rddata_buf_2;
                wren_buf_1 = 1'b0;
                wren_buf_2 = 1'b0;
            end

            default: state_next = S7_NORMAL_VIDEO_MODE;
        endcase
    end

    // --- Sub-module Instantiations ---
    assign clk_buf1_write = (state_current == S2_PROCESS_BW) ? clk_25_vga : ov7670_pclk;

    always @(posedge clk_25_vga or posedge reset_global) begin
        if (reset_global) begin
            done_capture_sync_r1 <= 1'b0;
            done_capture_sync_r2 <= 1'b0;
        end else begin
            done_capture_sync_r1 <= done_capture_new_frame;
            done_capture_sync_r2 <= done_capture_sync_r1;
        end
    end
    assign done_capture_new_frame_sync = done_capture_sync_r2;

    my_altpll Inst_four_clocks_pll ( .areset(1'b0), .inclk0(clk_50), .c0(clk_100), .c1(clk_100_3ns), .c2(clk_50_camera), .c3(clk_25_vga), .locked(dll_locked) );

    // --- [수정] Resend 스위치 기능 강제 비활성화 ---
    assign resend_reg_values = 1'b0;
    
    debounce Inst_debounce_normal_or_edgedetect ( .clk(clk_100), .reset(reset_global), .sw(slide_sw_NORMAL_OR_EDGEDETECT), .db(normal_or_edgedetect) );

    assign reset_manual = ~btn_RESET;
    assign reset_automatic = 1'b0;
    assign reset_global = reset_manual | reset_automatic;

    frame_buffer Inst_frame_buf_1 ( .rdaddress(rdaddress_buf_1), .rdclock(clk_25_vga), .q(rddata_buf_1), .wrclock(clk_buf1_write), .wraddress(wraddress_buf_1), .data(wrdata_buf_1), .wren(wren_buf_1) );
    frame_buffer Inst_frame_buf_2 ( .rdaddress(rdaddress_buf_2), .rdclock(clk_25_vga), .q(rddata_buf_2), .wrclock(clk_25_vga), .wraddress(wraddress_buf_2), .data(wrdata_buf_2), .wren(wren_buf_2) );

    ov7670_controller Inst_ov7670_controller ( .clk(clk_50_camera), .resend(resend_reg_values), .config_finished(LED_config_finished), .sioc(ov7670_sioc), .siod(ov7670_siod), .reset(ov7670_reset), .pwdn(ov7670_pwdn), .xclk(ov7670_xclk) );
    
    // 이 테스트에서는 clr_end_of_frame 신호가 필요 없으므로 연결하지 않습니다.
    ov7670_capture Inst_ov7670_capture ( .pclk(ov7670_pclk), .vsync(ov7670_vsync), .href(ov7670_href), .d(ov7670_data), .addr(wraddress_buf1_from_ov7670_capture), .dout(wrdata_buf1_from_ov7670_capture), .we(wren_buf1_from_ov7670_capture), .end_of_frame(done_capture_new_frame) );

    VGA Inst_VGA ( .CLK25(clk_25_vga), .clkout(vga_CLK), .Hsync(vga_hsync), .Vsync(vsync), .Nblank(nBlank), .Nsync(vga_sync_N), .activeArea(), .Hcnt_out(vga_hcnt), .Vcnt_out(vga_vcnt) );
    RGB Inst_RGB ( .Din(data_to_rgb), .Nblank(image_enable), .R(red), .G(green), .B(blue) );
    Address_Generator Inst_Address_Generator ( .rst_i(reset_global), .CLK25(clk_25_vga), .Hcnt(vga_hcnt), .Vcnt(vga_vcnt), .address(rdaddress_buf12_from_addr_gen), .enable_out(image_enable) );
    
    assign vga_r = red;
    assign vga_g = green;
    assign vga_b = blue;
    assign vga_vsync = vsync;
    assign vga_blank_N = nBlank;

    // --- [수정] Vsync 연동 로직 제거 ---
    do_black_white Inst_black_white ( .rst_i(reset_global), .clk_i(clk_25_vga), .enable_filter(call_black_white), .led_done(done_BW), .rdaddr_buf1(rdaddress_buf1_from_do_BW), .din_buf1(rddata_buf_1), .wraddr_buf1(wraddress_buf1_from_do_BW), .dout_buf1(wrdata_buf1_from_do_BW), .we_buf1(wren_buf1_from_do_BW) );
    do_edge_detection Inst_edge_detection ( .rst_i(reset_global), .clk_i(clk_25_vga), .enable_sobel_filter(call_edge_detection), .led_sobel_done(done_ED), .rdaddr_buf1(rdaddress_buf1_from_do_ED), .din_buf1(rddata_buf_1), .wraddr_buf2(wraddress_buf2_from_do_ED), .dout_buf2(wrdata_buf2_from_do_ED), .we_buf2(wren_buf2_from_do_ED) );

    assign LED_dll_locked = dll_locked;
    assign LED_done = done_BW | done_ED;

endmodule