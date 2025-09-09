// VHDL 소스 파일: top_level.vhd
// 프로젝트 이름: "digital cam implementation #4"
// OV7670 카메라 모듈을 DE2-115 보드에 연결하여 VGA 모니터로 영상을 출력하는 최상위 모듈입니다.
// 일반 비디오 모드와 실시간 에지 검출 비디오 모드를 지원합니다. [cite: 37]

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

    // Internal Wires and Regs

    // Clock signals from PLL
    wire clk_100;
    wire clk_100_3ns;
    wire clk_50_camera;
    wire clk_25_vga;
    wire dll_locked;

    // "Done" flags from processing units
    wire done_BW;
    wire done_ED;
    wire done_capture_new_frame;

    // Frame Buffer 1 signals
    reg         wren_buf_1;
    reg [16:0]  wraddress_buf_1;
    reg [11:0]  wrdata_buf_1;
    reg [16:0]  rdaddress_buf_1;
    wire [11:0] rddata_buf_1;

    // Muxed sources for Frame Buffer 1
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

    // Muxed sources for Frame Buffer 2
    wire        wren_buf2_from_do_ED;
    wire [16:0] wraddress_buf2_from_do_ED;
    wire [11:0] wrdata_buf2_from_do_ED;

    // User controls (debounced)
    wire resend_reg_values;
    wire normal_or_edgedetect;
    wire reset_manual;
    wire reset_automatic;
    wire reset_global;

    // FSM control signals
    reg         reset_BW_entity;
    reg         reset_ED_entity;
    reg         call_black_white;
    reg         call_edge_detection;
    wire        call_black_white_synchronized;
    wire        call_edge_detection_synchronized;

    // RGB and VGA signals
    wire [7:0]  red, green, blue;
    wire        activeArea;
    wire        nBlank;
    wire        vsync;
    reg [11:0]  data_to_rgb;

    // State Machine
    localparam [2:0] S0_RESET               = 3'd0,
                     S1_RESET_BW            = 3'd1,
                     S2_PROCESS_BW          = 3'd2,
                     S3_DONE_BW             = 3'd3,
                     S4_RESET_ED            = 3'd4,
                     S5_PROCESS_ED          = 3'd5,
                     S6_DONE_ED             = 3'd6,
                     S7_NORMAL_VIDEO_MODE   = 3'd7;

    reg [2:0] state_current, state_next;

    // State Register (Sequential)
    always @(posedge clk_25_vga or posedge reset_global) begin
        if (reset_global) begin
            state_current <= S0_RESET;
        end else begin
            state_current <= state_next;
        end
    end

    // Next State Logic and Outputs (Combinational)
    always @(*) begin
        // Default assignments
        state_next = state_current;
        reset_BW_entity = 1'b0;
        reset_ED_entity = 1'b0;
        call_black_white = 1'b0;
        call_edge_detection = 1'b0;

        case (state_current)
            S0_RESET: begin
                reset_BW_entity = 1'b1;
                reset_ED_entity = 1'b1;
                if (!normal_or_edgedetect) begin // Normal video mode
                    state_next = S7_NORMAL_VIDEO_MODE;
                    data_to_rgb = rddata_buf_1;
                    wren_buf_1 = wren_buf1_from_ov7670_capture;
                    wraddress_buf_1 = wraddress_buf1_from_ov7670_capture;
                    wrdata_buf_1 = wrdata_buf1_from_ov7670_capture;
                    rdaddress_buf_1 = rdaddress_buf12_from_addr_gen;
                    wren_buf_2 = 1'b0; // disabled
                    wraddress_buf_2 = wraddress_buf2_from_do_ED; // don't care
                    wrdata_buf_2 = wrdata_buf2_from_do_ED; // don't care
                    rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
                end else begin // Real-time edge detection mode
                    state_next = S1_RESET_BW;
                    data_to_rgb = rddata_buf_2;
                    wren_buf_1 = wren_buf1_from_do_BW;
                    wraddress_buf_1 = wraddress_buf1_from_do_BW;
                    wrdata_buf_1 = wrdata_buf1_from_do_BW;
                    rdaddress_buf_1 = rdaddress_buf1_from_do_BW;
                    wren_buf_2 = 1'b0; // disabled
                    wraddress_buf_2 = wraddress_buf2_from_do_ED; // don't care
                    wrdata_buf_2 = wrdata_buf2_from_do_ED; // don't care
                    rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
                end
            end
            S1_RESET_BW: begin
                reset_BW_entity = 1'b1;
                state_next = S2_PROCESS_BW;
                data_to_rgb = rddata_buf_2;
                wren_buf_1 = wren_buf1_from_do_BW;
                wraddress_buf_1 = wraddress_buf1_from_do_BW;
                wrdata_buf_1 = wrdata_buf1_from_do_BW;
                rdaddress_buf_1 = rdaddress_buf1_from_do_BW;
                wren_buf_2 = 1'b0;
                rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
            end
            S2_PROCESS_BW: begin
                call_black_white = 1'b1;
                if (!done_BW) begin
                    state_next = S2_PROCESS_BW;
                end else begin
                    state_next = S3_DONE_BW;
                end
                data_to_rgb = rddata_buf_2;
                wren_buf_1 = wren_buf1_from_do_BW;
                wraddress_buf_1 = wraddress_buf1_from_do_BW;
                wrdata_buf_1 = wrdata_buf1_from_do_BW;
                rdaddress_buf_1 = rdaddress_buf1_from_do_BW;
                wren_buf_2 = 1'b0;
                rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
            end
            S3_DONE_BW: begin
                reset_BW_entity = 1'b1;
                state_next = S4_RESET_ED;
                data_to_rgb = rddata_buf_2;
                wren_buf_1 = 1'b0;
                rdaddress_buf_1 = rdaddress_buf1_from_do_BW;
                wren_buf_2 = 1'b0;
                rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
            end
            S4_RESET_ED: begin
                reset_ED_entity = 1'b1;
                state_next = S5_PROCESS_ED;
                data_to_rgb = rddata_buf_2;
                wren_buf_1 = 1'b0;
                rdaddress_buf_1 = rdaddress_buf1_from_do_ED;
                wren_buf_2 = wren_buf2_from_do_ED;
                wraddress_buf_2 = wraddress_buf2_from_do_ED;
                wrdata_buf_2 = wrdata_buf2_from_do_ED;
                rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
            end
            S5_PROCESS_ED: begin
                call_edge_detection = 1'b1;
                if (!done_ED) begin
                    state_next = S5_PROCESS_ED;
                end else begin
                    state_next = S6_DONE_ED;
                end
                data_to_rgb = rddata_buf_2;
                wren_buf_1 = 1'b0;
                rdaddress_buf_1 = rdaddress_buf1_from_do_ED;
                wren_buf_2 = wren_buf2_from_do_ED;
                wraddress_buf_2 = wraddress_buf2_from_do_ED;
                wrdata_buf_2 = wrdata_buf2_from_do_ED;
                rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
            end
            S6_DONE_ED: begin
                reset_ED_entity = 1'b1;
                state_next = S7_NORMAL_VIDEO_MODE;
                data_to_rgb = rddata_buf_2;
                wren_buf_1 = 1'b0;
                rdaddress_buf_1 = rdaddress_buf12_from_addr_gen;
                wren_buf_2 = 1'b0;
                rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
            end
            S7_NORMAL_VIDEO_MODE: begin
                if (!normal_or_edgedetect) begin // Normal video mode
                    state_next = S7_NORMAL_VIDEO_MODE;
                    data_to_rgb = rddata_buf_1;
                    wren_buf_1 = wren_buf1_from_ov7670_capture;
                    wraddress_buf_1 = wraddress_buf1_from_ov7670_capture;
                    wrdata_buf_1 = wrdata_buf1_from_ov7670_capture;
                    rdaddress_buf_1 = rdaddress_buf12_from_addr_gen;
                    wren_buf_2 = 1'b0;
                    rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
                end else begin // Edge detection mode
                    if (!done_capture_new_frame) begin
                        state_next = S7_NORMAL_VIDEO_MODE; // Wait for a new frame
                    end else begin
                        state_next = S0_RESET; // Start new BW+ED cycle
                    end
                    data_to_rgb = rddata_buf_2;
                    wren_buf_1 = wren_buf1_from_ov7670_capture;
                    wraddress_buf_1 = wraddress_buf1_from_ov7670_capture;
                    wrdata_buf_1 = wrdata_buf1_from_ov7670_capture;
                    rdaddress_buf_1 = rdaddress_buf12_from_addr_gen;
                    wren_buf_2 = 1'b0;
                    rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;
                end
            end
            default: state_next = S0_RESET;
        endcase
    end

    // --- Sub-module Instantiations ---

    // Clock generation using PLL
    my_altpll Inst_four_clocks_pll (
        .areset (1'b0),
        .inclk0 (clk_50),
        .c0     (clk_100),
        .c1     (clk_100_3ns),
        .c2     (clk_50_camera),
        .c3     (clk_25_vga),
        .locked (dll_locked)
    );

    // Debouncing for slide switches
    debounce Inst_debounce_resend (
        .clk    (clk_100),
        .reset  (reset_global),
        .sw     (slide_sw_resend_reg_values),
        .db     (resend_reg_values)
    );

    debounce Inst_debounce_normal_or_edgedetect (
        .clk    (clk_100),
        .reset  (reset_global),
        .sw     (slide_sw_NORMAL_OR_EDGEDETECT),
        .db     (normal_or_edgedetect)
    );

    // Reset logic
    assign reset_manual = ~btn_RESET; // Active low button
    assign reset_automatic = 1'b0; // TODO: Implement auto-reset
    assign reset_global = reset_manual | reset_automatic;

    // Frame Buffers (RAM)
    frame_buffer Inst_frame_buf_1 (
        .rdaddress (rdaddress_buf_1),
        .rdclock   (clk_25_vga),
        .q         (rddata_buf_1),
        .wrclock   (clk_25_vga),
        .wraddress (wraddress_buf_1),
        .data      (wrdata_buf_1),
        .wren      (wren_buf_1)
    );

    frame_buffer Inst_frame_buf_2 (
        .rdaddress (rdaddress_buf_2),
        .rdclock   (clk_25_vga),
        .q         (rddata_buf_2),
        .wrclock   (clk_25_vga),
        .wraddress (wraddress_buf_2),
        .data      (wrdata_buf_2),
        .wren      (wren_buf_2)
    );

    // Camera related blocks
    ov7670_controller Inst_ov7670_controller (
        .clk             (clk_50_camera),
        .resend          (resend_reg_values),
        .config_finished (LED_config_finished),
        .sioc            (ov7670_sioc),
        .siod            (ov7670_siod),
        .reset           (ov7670_reset),
        .pwdn            (ov7670_pwdn),
        .xclk            (ov7670_xclk)
    );

    ov7670_capture Inst_ov7670_capture (
        .pclk         (ov7670_pclk),
        .vsync        (ov7670_vsync),
        .href         (ov7670_href),
        .d            (ov7670_data),
        .addr         (wraddress_buf1_from_ov7670_capture),
        .dout         (wrdata_buf1_from_ov7670_capture),
        .we           (wren_buf1_from_ov7670_capture),
        .end_of_frame (done_capture_new_frame)
    );

    // VGA related blocks
    VGA Inst_VGA (
        .CLK25      (clk_25_vga),
        .clkout     (vga_CLK),
        .Hsync      (vga_hsync),
        .Vsync      (vsync),
        .Nblank     (nBlank),
        .Nsync      (vga_sync_N),
        .activeArea (activeArea)
    );

    RGB Inst_RGB (
        .Din    (data_to_rgb),
        .Nblank (activeArea),
        .R      (red),
        .G      (green),
        .B      (blue)
    );

    assign vga_r = red;
    assign vga_g = green;
    assign vga_b = blue;
    assign vga_vsync = vsync;
    assign vga_blank_N = nBlank;

    // Address Generator for reading frame buffers
    Address_Generator Inst_Address_Generator (
        .rst_i   (1'b0),
        .CLK25   (clk_25_vga),
        .enable  (activeArea),
        .vsync   (vsync),
        .address (rdaddress_buf12_from_addr_gen)
    );
    
    // Synchronize filter calls with VSYNC
    assign call_black_white_synchronized = call_black_white & (~vsync);
    assign call_edge_detection_synchronized = call_edge_detection & (~vsync);

    // Image Processing blocks
    do_black_white Inst_black_white (
        .rst_i         (reset_BW_entity),
        .clk_i         (clk_25_vga),
        .enable_filter (call_black_white_synchronized),
        .led_done      (done_BW),
        .rdaddr_buf1   (rdaddress_buf1_from_do_BW),
        .din_buf1      (rddata_buf_1),
        .wraddr_buf1   (wraddress_buf1_from_do_BW),
        .dout_buf1     (wrdata_buf1_from_do_BW),
        .we_buf1       (wren_buf1_from_do_BW)
    );

    do_edge_detection Inst_edge_detection (
        .rst_i               (reset_ED_entity),
        .clk_i               (clk_25_vga),
        .enable_sobel_filter (call_edge_detection_synchronized),
        .led_sobel_done      (done_ED),
        .rdaddr_buf1         (rdaddress_buf1_from_do_ED),
        .din_buf1            (rddata_buf_1),
        .wraddr_buf2         (wraddress_buf2_from_do_ED),
        .dout_buf2           (wrdata_buf2_from_do_ED),
        .we_buf2             (wren_buf2_from_do_ED)
    );
    
    // Status LEDs
    assign LED_dll_locked = dll_locked;
    assign LED_done = done_BW | done_ED;

endmodule