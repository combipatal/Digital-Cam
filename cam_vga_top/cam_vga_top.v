// =============================================================================
// == Top Module: cam_vga_top (수정됨 - FIFO 데이터 흐름 개선)
// == ---------------------------------------------------------------------------
// == OV7670 카메라 영상을 VGA로 출력하는 최상위 모듈
// =============================================================================
module cam_vga_top (
    // --- Global Inputs ---
    input  wire CLOCK_50,       // 50MHz main clock from DE2-115
    input  wire KEY_RESET_N,    // Reset button (KEY[0], Active-Low)
    
    // --- OV7670 Camera I/F ---
    input  wire        CAM_PCLK,    // Pixel clock from camera
    input  wire        CAM_VSYNC,   // Frame sync
    input  wire        CAM_HREF,    // Line valid (HSYNC pin)
    input  wire [7:0]  CAM_DATA,    // Pixel data bus
    inout  wire        CAM_SIOC,    // I2C SCL
    inout  wire        CAM_SIOD,    // I2C SDA
    output  wire       clk_xclk,    // mclk for camera
	 
	 output reg ov7670_pwdn,  // PWDN 핀에 연결된 IO
    output reg ov7670_reset,  // RESET 핀에 연결된 IO
    
    // --- VGA Output ---
    output wire VGA_CLK,
    output wire VGA_HS,
    output wire VGA_VS,
    output wire VGA_BLANK_N,
    output wire VGA_SYNC_N,
    output wire [7:0] VGA_R,
    output wire [7:0] VGA_G,
    output wire [7:0] VGA_B,

    // --- Debug Outputs ---
    output wire LED_PLL_LOCKED, // PLL Lock 상태 표시 LED
    output wire LED_CFG_DONE,   // 카메라 설정 완료 표시 LED
    output wire LED_VSYNC,       // 카메라 VSYNC 수신 표시 LED
	 output wire LED_I2C_BUSY, // 디버깅용 LED 출력 포트 추가
	 output wire LED_PCLK_ACTIVITY, // 👈 [추가] PCLK 확인용 LED
	 output wire LED_RAW_VSYNC
	 
);

    // --- 1. Clock Generation ---
    wire clk_25MHz;
    wire pll_locked;
    
	assign clk_xclk = clk_24MHz;  // 카메라용 마스터 클럭
	assign LED_RAW_VSYNC = CAM_VSYNC;
	wire i2c_busy_signal; // 내부 wire 추가

always @(posedge CLOCK_50 or negedge KEY_RESET_N) begin
    if (!KEY_RESET_N) begin
        ov7670_pwdn  <= 1'b0;
        ov7670_reset <= 1'b1;
    end
end
	PLL PLL (
		.areset(),
		.inclk0(CLOCK_50),
		.c0(clk_25MHz),
		.c1(clk_24MHz),
		.locked(pll_locked)
		);
    assign LED_PLL_LOCKED = pll_locked;
	
    // --- 2. Reset Synchronization ---
    wire rstn_50m, rstn_25m, rstn_pclk;
    
    sync_reset #(.STAGES(3)) sync_rst_50m (.clk(CLOCK_50), .async_rstn(KEY_RESET_N), .sync_rstn(rstn_50m));
    sync_reset #(.STAGES(3)) sync_rst_25m (.clk(clk_25MHz), .async_rstn(KEY_RESET_N), .sync_rstn(rstn_25m));
    sync_reset #(.STAGES(3)) sync_rst_pclk(.clk(CAM_PCLK), .async_rstn(KEY_RESET_N), .sync_rstn(rstn_pclk));
		
		
	 reg [23:0] pclk_counter = 0;

	// CAM_PCLK를 클럭으로, rstn_pclk를 리셋으로 사용하는 카운터
	always @(posedge CAM_PCLK or negedge rstn_pclk) begin
		 if (!rstn_pclk)
			  pclk_counter <= 0;
		 else
			  pclk_counter <= pclk_counter + 1;
	end
	// 카운터의 최상위 비트를 사용해 LED를 천천히 깜빡이게 함
	assign LED_PCLK_ACTIVITY = pclk_counter[23]; // 👈 [추가]


    // --- 3. VGA Timing Generation ---
    wire [9:0] h_count, v_count;
    wire h_sync, v_sync;
    wire video_on;
    vga_controller vga_ctrl (
        .clk(clk_25MHz),
        .reset_n(rstn_25m),
        .h_sync(h_sync),
        .v_sync(v_sync),
        .video_on(video_on),
        .h_count(h_count),
        .v_count(v_count)
    );
    assign VGA_CLK     = clk_25MHz;
    assign VGA_HS      = h_sync;
    assign VGA_VS      = v_sync;
    assign VGA_BLANK_N = video_on;
    assign VGA_SYNC_N  = 1'b0;

    // --- 4. Camera Interface Logic ---
    wire i_scl, i_sda, o_scl, o_sda;
    assign CAM_SIOC = o_scl ? 1'bz : 1'b0;
    assign CAM_SIOD = o_sda ? 1'bz : 1'b0;
    assign i_scl    = CAM_SIOC;
    assign i_sda    = CAM_SIOD;

    wire cam_wr;
    wire [11:0] cam_wdata;
    wire cam_cfg_done;
    wire cam_vsync_out;
    
    // 카메라 초기화 제어 로직 수정
    reg cfg_init_done = 0;
    reg cfg_init_pulse = 0;
    
    always @(posedge CLOCK_50 or negedge rstn_50m) begin
        if(!rstn_50m) begin
            cfg_init_done <= 1'b0;
            cfg_init_pulse <= 1'b0;
        end else begin
            if (!cfg_init_done && !cam_cfg_done) begin
                cfg_init_pulse <= 1'b1;
                cfg_init_done <= 1'b1;
            end else if (cam_cfg_done) begin
                cfg_init_pulse <= 1'b0;
            end
        end
    end

    cam_top #(.T_CFG_CLK(20)) cam_inst ( // 50MHz이므로 T_CLK=20ns
        .i_cfg_clk   (CLOCK_50),
        .i_rstn      (rstn_50m),
		   .i_pclk_rstn (rstn_pclk),     // 👈 [추가] 캡처 로직에는 PCLK 리셋 전달
        .i_cam_pclk  (CAM_PCLK),
        .i_cam_vsync (CAM_VSYNC),
        .i_cam_href  (CAM_HREF),
        .i_cam_data  (CAM_DATA),
        .i_scl(i_scl), .i_sda(i_sda),
        .o_scl(o_scl), .o_sda(o_sda),
        .obuf_wr        (cam_wr),
        .obuf_wdata     (cam_wdata),
        .i_cfg_init  (cfg_init_pulse),
        .o_cfg_done  (cam_cfg_done),
		  .o_cfg_busy  (i2c_busy_signal),
        .o_sof       (cam_vsync_out)
    );
    assign LED_CFG_DONE = cam_cfg_done;
    assign LED_VSYNC    = cam_vsync_out;
	 assign LED_I2C_BUSY = i2c_busy_signal; // wire를 실제 LED에 연결
    // --- 5. Asynchronous FIFO ---
    wire [11:0] fifo_rdata;
    wire        fifo_empty;
    wire        fifo_full;
    wire        fifo_rd;

    // FIFO 읽기 로직 수정: 더 적극적으로 읽기
    assign fifo_rd = !fifo_empty; // video_on 조건 제거

        fifo_async u_fifo (
        .wrclk   (CAM_PCLK),
        .wrreq    (cam_wr && !fifo_full),
        .data  (cam_wdata),
        .wrfull     (fifo_full),
        .rdclk   (clk_25MHz),
        .aclr  (!rstn_25m), // 👈 [수정] rstn_25m -> !rstn_25m
        .rdreq    (fifo_rd),
        .q  (fifo_rdata),
        .rdempty    (fifo_empty)
    );

    // --- 6. Display Path Logic with Debug Info ---
    reg [7:0] vga_r, vga_g, vga_b;
    reg [11:0] last_valid_data = 12'h0F0; // 초기값: 녹색
    
    // 디버그용 카운터들
    reg [15:0] debug_counter = 0;
    reg cam_vsync_detected = 0;
    reg cam_href_detected = 0;
    
    // VSYNC과 HREF 감지
    always @(posedge CLOCK_50 or negedge rstn_50m) begin
        if (!rstn_50m) begin
            cam_vsync_detected <= 0;
            cam_href_detected <= 0;
        end else begin
            if (CAM_VSYNC) cam_vsync_detected <= 1;
            if (CAM_HREF) cam_href_detected <= 1;
        end
    end
    
    always @(posedge clk_25MHz or negedge rstn_25m) begin
        if(!rstn_25m) begin
            {vga_r, vga_g, vga_b} <= 24'h000000;
            last_valid_data <= 12'h0F0;
            debug_counter <= 0;
        end else if(video_on) begin
            debug_counter <= debug_counter + 1;
            
            if(!fifo_empty && fifo_rd) begin
                // FIFO에서 읽은 데이터 사용
                last_valid_data <= fifo_rdata;
                vga_r <= {fifo_rdata[11:8], fifo_rdata[11:8]};
                vga_g <= {fifo_rdata[7:4],  fifo_rdata[7:4]};
                vga_b <= {fifo_rdata[3:0],  fifo_rdata[3:0]};
            end else begin
                // 디버그 패턴 표시
                if (!cam_cfg_done) begin
                    // 설정 중: 빨간색
                    {vga_r, vga_g, vga_b} <= 24'hFF0000;
                end else if (!cam_vsync_detected) begin
                    // VSYNC 없음: 주황색
                    {vga_r, vga_g, vga_b} <= 24'hFF8000;
                end else if (!cam_href_detected) begin
                    // HREF 없음: 노란색  
                    {vga_r, vga_g, vga_b} <= 24'hFFFF00;
                end else if (fifo_empty) begin
                    // FIFO 비어있음: 테스트 패턴 (체크보드)
                    if ((h_count[4] ^ v_count[4]) == 1'b1)
                        {vga_r, vga_g, vga_b} <= 24'hFFFFFF; // 흰색
                    else
                        {vga_r, vga_g, vga_b} <= 24'h808080; // 회색
                end else begin
                    // 마지막 데이터 유지
                    vga_r <= {last_valid_data[11:8], last_valid_data[11:8]};
                    vga_g <= {last_valid_data[7:4],  last_valid_data[7:4]};
                    vga_b <= {last_valid_data[3:0],  last_valid_data[3:0]};
                end
            end
        end else begin
            // 비디오 영역 밖은 검은색
            {vga_r, vga_g, vga_b} <= 24'h000000;
        end
    end

    assign VGA_R = vga_r;
    assign VGA_G = vga_g;
    assign VGA_B = vga_b;

endmodule

// =============================================================================
// == Module: sync_reset
// =============================================================================
module sync_reset #( parameter STAGES = 2 ) (
    input wire clk,
    input wire async_rstn,
    output wire sync_rstn
);
    reg [STAGES-1:0] rst_sync_reg;
    always @(posedge clk or negedge async_rstn) begin
        if(!async_rstn)
            rst_sync_reg <= {STAGES{1'b0}};
        else
            rst_sync_reg <= {rst_sync_reg[STAGES-2:0], 1'b1};
    end
    assign sync_rstn = rst_sync_reg[STAGES-1];
endmodule



