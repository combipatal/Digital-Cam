module digital_cam_impl3(
  input wire clk_50,
  input wire slide_sw_RESET,             // 전체 시스템 리셋
  input wire slide_sw_resend_reg_values, // OV7670 레지스터 다시 쓰기
  output wire LED_config_finished,       // 카메라 레지스터 쓰기 완료 알림
  output wire LED_dll_locked,            // PLL 잠금 알림
  input wire btn_take_snapshot,          // KEY0
  input wire btn_display_snapshot,       // KEY1
  input wire btn_do_black_white,         // KEY2
  input wire btn_do_edge_detection,      // KEY3
    
  output wire vga_hsync,
  output wire vga_vsync,
  output wire [7:0] vga_r,
  output wire [7:0] vga_g,
  output wire [7:0] vga_b,
  output wire vga_blank_N,
  output wire vga_sync_N,
  output wire vga_CLK,
    
  input wire ov7670_pclk,
  output wire ov7670_xclk,
  input wire ov7670_vsync,
  input wire ov7670_href,
  input wire [7:0] ov7670_data,
  output wire ov7670_sioc,
  inout wire ov7670_siod,
  output wire ov7670_pwdn,
  output wire ov7670_reset,
    
  output wire LED_done,                  // 스냅샷 SDRAM 가져오기 완료, 흑백 완료, 엣지 검출 완료
  
  // SDRAM 관련 신호
  output wire [12:0] DRAM_ADDR,
  output wire DRAM_BA_0,
  output wire DRAM_BA_1,
  output wire DRAM_CAS_N,
  output wire DRAM_CKE,
  output wire DRAM_CLK,
  output wire DRAM_CS_N,
  inout wire [15:0] DRAM_DQ,
  output wire DRAM_LDQM,
  output wire DRAM_UDQM,
  output wire DRAM_RAS_N,
  output wire DRAM_WE_N
);

  // 클럭 신호
  wire clk_100;         // clk0: 100 MHz
  wire clk_100_3ns;     // clk1: 100 MHz (위상 조정 -3ns)
  wire clk_50_camera;   // clk2: 50 MHz
  wire clk_25_vga;      // clk3: 25 MHz
  wire dll_locked;
  wire done_snapshot = 1'b0;
  wire done_BW = 1'b0;
  wire done_ED = 1'b0;

  // 버퍼 1 신호 (비디오 모드에서는 address_generator에서 rd 주소, 25MHz 클럭 사용)
  // 스냅샷 모드에서는 sdram_rw에서 rd 주소, 25MHz 클럭 사용
  wire wren_buf_1;
  wire [16:0] wraddress_buf_1;
  wire [11:0] wrdata_buf_1;
  wire [16:0] rdaddress_buf_1;
  wire [11:0] rddata_buf_1;
  
  // 버퍼 1 입력 신호 (다른 엔티티에서 생성)
  wire wren_buf1_from_ov7670_capture;
  wire [16:0] rdaddress_buf12_from_addr_gen; // 버퍼 1과 버퍼 2 모두에 연결
  wire [16:0] rdaddress_buf1_from_sdram_rw;
  
  // 버퍼 2 신호 (스냅샷 이미지 저장, 그레이 이미지 변환, 엣지 검출 이미지 저장)
  wire wren_buf_2;
  wire [16:0] wraddress_buf_2;
  wire [11:0] wrdata_buf_2;
  wire [16:0] rdaddress_buf_2;
  wire [11:0] rddata_buf_2;
  
  // 버퍼 2 제어 신호 (SDRAM에서 읽고 버퍼 2에 쓰기)
  wire wren_buf2_from_sdram_rw;
  wire [16:0] wraddress_buf2_from_sdram_rw;
  wire [11:0] wrdata_buf2_from_sdram_rw;
  
  // 버퍼 2 제어 신호 (흑백 변환)
  wire [16:0] rdaddress_buf2_from_do_BW;
  wire wren_buf2_from_do_BW;
  wire [16:0] wraddress_buf2_from_do_BW;
  wire [11:0] wrdata_buf2_from_do_BW;
  
  // 버퍼 2 제어 신호 (엣지 검출)
  wire [16:0] rdaddress_buf2_from_do_ED;
  wire wren_buf2_from_do_ED;
  wire [16:0] wraddress_buf2_from_do_ED;
  wire [11:0] wrdata_buf2_from_do_ED;
  
  // 사용자 제어 신호
  wire resend_reg_values;
  wire take_snapshot;
  wire display_snapshot;
  wire call_black_white;
  wire call_edge_detection;
  reg take_snapshot_synchronized = 1'b0;
  reg display_snapshot_synchronized = 1'b0;
  reg call_black_white_synchronized = 1'b0;
  reg call_edge_detection_synchronized = 1'b0;
  
  // 리셋 신호
  wire reset_global;
  wire reset_manual;
  wire reset_automatic = 1'b0;
  reg reset_sdram_interface;
  reg reset_BW_entity;
  reg reset_ED_entity;

  // RGB 관련 신호
  wire [7:0] red, green, blue;
  wire activeArea;
  wire nBlank;
  wire vSync;
  reg [11:0] data_to_rgb;

  // SDRAM 관련 신호
  wire [1:0] dram_bank;
  wire [24:0] addr_i;
  wire [31:0] dat_i;
  wire [31:0] dat_o;
  wire we_i;
  wire ack_o;
  wire stb_i;
  wire cyc_i;

  // 입력 신호 처리 (푸시 버튼 반전)
  assign take_snapshot = ~btn_take_snapshot;       // KEY0
  assign display_snapshot = ~btn_display_snapshot; // KEY1
  assign call_black_white = ~btn_do_black_white;   // KEY2
  assign call_edge_detection = ~btn_do_edge_detection; // KEY3
  
  // VGA 출력 할당
  assign vga_r = red;
  assign vga_g = green;
  assign vga_b = blue;
  assign vga_vsync = vSync;
  assign vga_blank_N = nBlank;
  
  // LED 출력 할당
  assign LED_dll_locked = 1'b1; // dll_locked;
  assign LED_done = (done_snapshot | done_BW | done_ED);
  
  // DRAM 뱅크 연결
  assign DRAM_BA_1 = dram_bank[1];
  assign DRAM_BA_0 = dram_bank[0];
  
  // vsync가 0일 때만 프레임과 동기화된 신호 생성
  always @(posedge clk_100) begin
    take_snapshot_synchronized <= take_snapshot & (~vSync);
    display_snapshot_synchronized <= display_snapshot & (~vSync);
    call_black_white_synchronized <= call_black_white & (~vSync);
    call_edge_detection_synchronized <= call_edge_detection & (~vSync);
  end
  
  // 리셋 신호 생성
  assign reset_manual = slide_sw_RESET;
  assign reset_global = (reset_manual | reset_automatic);
  
  // 리셋 펄스 생성
  always @(posedge clk_100) begin
    if (reset_global) begin
      reset_sdram_interface <= 1'b1;
      reset_BW_entity <= 1'b1;
      reset_ED_entity <= 1'b1;
    end
    else if ((take_snapshot == 1'b0 && display_snapshot == 1'b0 && 
             call_black_white == 1'b0 && call_edge_detection == 1'b0) && 
             (done_snapshot || done_BW || done_ED)) begin
      reset_sdram_interface <= 1'b1;
      reset_BW_entity <= 1'b1;
      reset_ED_entity <= 1'b1;
    end
    else begin
      reset_sdram_interface <= 1'b0;
      reset_BW_entity <= 1'b0;
      reset_ED_entity <= 1'b0;
    end
  end
  
  // 버퍼 멀티플렉싱
  reg wren_buf_1_reg;
  reg [16:0] rdaddress_buf_1_reg;
  reg wren_buf_2_reg;
  reg [16:0] wraddress_buf_2_reg;
  reg [11:0] wrdata_buf_2_reg;
  reg [16:0] rdaddress_buf_2_reg;
  reg [11:0] data_to_rgb_reg;

  always @(posedge clk_100) begin
    if (take_snapshot) begin
      wren_buf_1_reg <= 1'b0; // 스냅샷 중 버퍼 1 쓰기 비활성화
      rdaddress_buf_1_reg <= rdaddress_buf1_from_sdram_rw;
      wren_buf_2_reg <= wren_buf2_from_sdram_rw;
      wraddress_buf_2_reg <= wraddress_buf2_from_sdram_rw;
      wrdata_buf_2_reg <= wrdata_buf2_from_sdram_rw;
      rdaddress_buf_2_reg <= rdaddress_buf12_from_addr_gen;
      data_to_rgb_reg <= rddata_buf_2;
    end
    else if (display_snapshot) begin
      wren_buf_1_reg <= 1'b0; // 버퍼 1 쓰기 비활성화
      rdaddress_buf_1_reg <= rdaddress_buf12_from_addr_gen;
      wren_buf_2_reg <= wren_buf2_from_sdram_rw;
      wraddress_buf_2_reg <= wraddress_buf2_from_sdram_rw;
      wrdata_buf_2_reg <= wrdata_buf2_from_sdram_rw;
      rdaddress_buf_2_reg <= rdaddress_buf12_from_addr_gen;
      data_to_rgb_reg <= rddata_buf_2;
    end
    else if (call_black_white) begin
      wren_buf_1_reg <= 1'b0;
      rdaddress_buf_1_reg <= rdaddress_buf12_from_addr_gen;
      wren_buf_2_reg <= wren_buf2_from_do_BW;
      wraddress_buf_2_reg <= wraddress_buf2_from_do_BW;
      wrdata_buf_2_reg <= wrdata_buf2_from_do_BW;
      
      if (done_BW == 1'b0) begin
        rdaddress_buf_2_reg <= rdaddress_buf2_from_do_BW;
      end else begin
        rdaddress_buf_2_reg <= rdaddress_buf12_from_addr_gen;
      end
      
      data_to_rgb_reg <= rddata_buf_2;
    end
    else if (call_edge_detection) begin
      wren_buf_1_reg <= 1'b0;
      rdaddress_buf_1_reg <= rdaddress_buf12_from_addr_gen;
      wren_buf_2_reg <= wren_buf2_from_do_ED;
      wraddress_buf_2_reg <= wraddress_buf2_from_do_ED;
      wrdata_buf_2_reg <= wrdata_buf2_from_do_ED;
      
      if (done_ED == 1'b0) begin
        rdaddress_buf_2_reg <= rdaddress_buf2_from_do_ED;
      end else begin
        rdaddress_buf_2_reg <= rdaddress_buf12_from_addr_gen;
      end
      
      data_to_rgb_reg <= rddata_buf_2;
    end
    else begin // 기본 비디오 모드
      wren_buf_1_reg <= wren_buf1_from_ov7670_capture;
      rdaddress_buf_1_reg <= rdaddress_buf12_from_addr_gen;
      wren_buf_2_reg <= wren_buf2_from_sdram_rw;
      wraddress_buf_2_reg <= wraddress_buf2_from_sdram_rw;
      wrdata_buf_2_reg <= wrdata_buf2_from_sdram_rw;
      rdaddress_buf_2_reg <= rdaddress_buf12_from_addr_gen;
      data_to_rgb_reg <= rddata_buf_1;
    end
  end
  
  assign wren_buf_1 = wren_buf_1_reg;
  assign rdaddress_buf_1 = rdaddress_buf_1_reg;
  assign wren_buf_2 = wren_buf_2_reg;
  assign wraddress_buf_2 = wraddress_buf_2_reg;
  assign wrdata_buf_2 = wrdata_buf_2_reg;
  assign rdaddress_buf_2 = rdaddress_buf_2_reg;
  assign data_to_rgb = data_to_rgb_reg;

  // PLL 인스턴스
  my_altpll four_clocks_pll (
    .areset(1'b0),
    .inclk0(clk_50),
    .c0(clk_100),
    .c1(clk_100_3ns),
    .c2(clk_50_camera),
    .c3(clk_25_vga),
    .locked(dll_locked)
  );
  
  // 디바운싱 인스턴스
  debounce Inst_debounce_resend (
    .clk(clk_25_vga),
    .i(slide_sw_resend_reg_values),
    .o(resend_reg_values)
  );
  
  // 프레임 버퍼 인스턴스
  frame_buffer Inst_frame_buf_1 (
    .rdaddress(rdaddress_buf_1),
    .rdclock(clk_25_vga),
    .q(rddata_buf_1),
    .wrclock(ov7670_pclk),
    .wraddress(wraddress_buf_1),
    .data(wrdata_buf_1),
    .wren(wren_buf_1)
  );
  
  frame_buffer Inst_frame_buf_2 (
    .rdaddress(rdaddress_buf_2),
    .rdclock(clk_25_vga),
    .q(rddata_buf_2),
    .wrclock(clk_25_vga),
    .wraddress(wraddress_buf_2),
    .data(wrdata_buf_2),
    .wren(wren_buf_2)
  );
  
  // OV7670 카메라 제어 인스턴스
  ov7670_controller Inst_ov7670_controller (
    .clk(clk_50_camera),
    .resend(resend_reg_values),
    .config_finished(LED_config_finished),
    .sioc(ov7670_sioc),
    .siod(ov7670_siod),
    .reset(ov7670_reset),
    .pwdn(ov7670_pwdn),
    .xclk(ov7670_xclk)
  );
  
  ov7670_capture Inst_ov7670_capture (
    .pclk(ov7670_pclk),
    .vsync(ov7670_vsync),
    .href(ov7670_href),
    .d(ov7670_data),
    .addr(wraddress_buf_1),
    .dout(wrdata_buf_1),
    .we(wren_buf1_from_ov7670_capture)
  );
  
  // VGA 관련 인스턴스
  VGA Inst_VGA (
    .CLK25(clk_25_vga),
    .clkout(vga_CLK),
    .Hsync(vga_hsync),
    .Vsync(vSync),
    .Nblank(nBlank),
    .Nsync(vga_sync_N),
    .activeArea(activeArea)
  );
  
  RGB Inst_RGB (
    .Din(data_to_rgb),
    .Nblank(activeArea),
    .R(red),
    .G(green),
    .B(blue)
  );
  
  Address_Generator Inst_Address_Generator (
    .rst_i(1'b0),
    .CLK25(clk_25_vga),
    .enable(activeArea),
    .vsync(vSync),
    .address(rdaddress_buf12_from_addr_gen)
  );
  
  // SDRAM 관련 인스턴스
  sdram_controller Inst_sdram_controller (
    .clk_i(clk_100),
    .dram_clk_i(clk_100_3ns),
    .rst_i(reset_sdram_interface),
    .dll_locked(dll_locked),
    .dram_addr(DRAM_ADDR),
    .dram_bank(dram_bank),
    .dram_cas_n(DRAM_CAS_N),
    .dram_cke(DRAM_CKE),
    .dram_clk(DRAM_CLK),
    .dram_cs_n(DRAM_CS_N),
    .dram_dq(DRAM_DQ),
    .dram_ldqm(DRAM_LDQM),
    .dram_udqm(DRAM_UDQM),
    .dram_ras_n(DRAM_RAS_N),
    .dram_we_n(DRAM_WE_N),
    .addr_i(addr_i),
    .dat_i(dat_i),
    .dat_o(dat_o),
    .we_i(we_i),
    .ack_o(ack_o),
    .stb_i(stb_i),
    .cyc_i(cyc_i)
  );
  
  sdram_rw Inst_sdram_rw (
    .clk_i(clk_25_vga),
    .rst_i(reset_sdram_interface),
    .addr_i(addr_i),
    .dat_i(dat_i),
    .dat_o(dat_o),
    .we_i(we_i),
    .ack_o(ack_o),
    .stb_i(stb_i),
    .cyc_i(cyc_i),
    .addr_buf2(wraddress_buf2_from_sdram_rw),
    .dout_buf2(wrdata_buf2_from_sdram_rw),
    .we_buf2(wren_buf2_from_sdram_rw),
    .addr_buf1(rdaddress_buf1_from_sdram_rw),
    .din_buf1(rddata_buf_1),
    .take_snapshot(take_snapshot_synchronized),
    .display_snapshot(display_snapshot_synchronized),
    .led_done(done_snapshot)
  );
  
  // 흑백(그레이스케일) 필터 인스턴스
  do_black_white Inst_black_white (
    .rst_i(reset_BW_entity),
    .clk_i(clk_25_vga),
    .enable_filter(call_black_white_synchronized),
    .led_done(done_BW),
    .rdaddr_buf2(rdaddress_buf2_from_do_BW),
    .din_buf2(rddata_buf_2),
    .wraddr_buf2(wraddress_buf2_from_do_BW),
    .dout_buf2(wrdata_buf2_from_do_BW),
    .we_buf2(wren_buf2_from_do_BW)
  );
  
  // 엣지 검출 필터 인스턴스
  do_edge_detection Inst_edge_detection (
    .rst_i(reset_ED_entity),
    .clk_i(clk_25_vga),
    .enable_sobel_filter(call_edge_detection_synchronized),
    .led_sobel_done(done_ED),
    .rdaddr_buf2(rdaddress_buf2_from_do_ED),
    .din_buf2(rddata_buf_2),
    .wraddr_buf2(wraddress_buf2_from_do_ED),
    .dout_buf2(wrdata_buf2_from_do_ED),
    .we_buf2(wren_buf2_from_do_ED)
  );

endmodule
