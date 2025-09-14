`timescale 1ns / 1ps

module top(
    // --- Port Declarations ---
    input wire clk,         // DE2-115 보드의 50MHz 클럭 입력
    input wire rst_n,
    input wire[3:0] key,
    // Camera
    input wire cmos_pclk, cmos_href, cmos_vsync,
    input wire[7:0] cmos_db,
    inout cmos_sda, cmos_scl, 
    output wire cmos_rst_n, cmos_pwdn, cmos_xclk,
    // Debugging LED
    output[3:0] led, 
    // SDRAM
    output wire sdram_clk,
    output wire sdram_cke, 
    output wire sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n, 
    output wire[12:0] sdram_addr,
    output wire[1:0] sdram_ba, 
    output wire[1:0] sdram_dqm, 
    inout[15:0] sdram_dq,
    // VGA
    output wire[7:0] vga_r,
    output wire[7:0] vga_g,
    output wire[7:0] vga_b,
    output wire vga_out_vs, vga_out_hs
);
 
    // --- Clock Wires ---
    wire clk_165_internal;
    wire clk_165_sdram_pin;
    wire clk_vga;
    wire clk_camera_xclk;
    wire pll_locked;
    
    // --- Internal Signals ---
    wire[15:0] dout_cam_fifo, din_vga_fifo;
    wire empty_vga_fifo;
    wire rd_en_vga;
    wire[9:0] data_count_cam_fifo;
    wire rd_en_cam_fifo;
    reg[7:0] threshold = 0;
    reg sobel = 0;
    wire key1_tick, key2_tick, key3_tick;

    // --- Key Input Logic ---
    always @(posedge clk) begin
        if(!rst_n) begin
            threshold <= 0;
            sobel <= 0;
        end
        else begin
            if(key1_tick) threshold <= threshold + 1;
            if(key2_tick) threshold <= threshold - 1;
            if(key3_tick) sobel <= !sobel;
        end
    end
    
    // --- 1. 통합 PLL 인스턴스 ---
    // (Wizard에서 생성한 모듈 이름이 다를 경우 이 부분만 수정)
    PLL_CLK clock_generator (
        .inclk0   (clk),
        .areset   (!rst_n),
        .c0       (clk_165_internal),
        .c1       (clk_165_sdram_pin),
        .locked   (pll_locked)
    );
	
	PLL_25Mhz clock_generator_1 (
		  .inclk0   (clk),
        .a0eset   (!rst_n),
        .c0       (clk_vga),
        .c1       (clk_camera_xclk),
        .locked   ()
		  );
	
    // --- 2. ODDR2 삭제 및 sdram_clk 직접 할당 ---
    assign sdram_clk = clk_165_sdram_pin;

    // --- Module Instantiations ---
    camera_interface i_camera_interface (
        .clk        (clk),
        .clk_100    (clk_165_internal), // 이름은 clk_100이지만 실제론 165MHz가 들어감
        .clk_sdram  (clk_165_internal), // FIFO 읽기 클럭
        .rst_n      (rst_n),
        .key        (key),
        .rd_en      (rd_en_cam_fifo),
        .data_count_r(data_count_cam_fifo),
        .dout       (dout_cam_fifo),
        .cmos_pclk  (cmos_pclk),
        .cmos_href  (cmos_href),
        .cmos_vsync (cmos_vsync),
        .cmos_db    (cmos_db),
        .cmos_sda   (cmos_sda),
        .cmos_scl   (cmos_scl), 
        .cmos_rst_n (cmos_rst_n),
        .cmos_pwdn  (cmos_pwdn),
        .cmos_xclk  (clk_camera_xclk), // PLL에서 생성된 24MHz 클럭
        .led        (led)
    );
     
    sdram_interface i_sdram_interface (
        .clk        (clk_165_internal),
        .rst_n      (rst_n),
        .clk_vga    (clk_vga),
        .rd_en      (rd_en_vga),
        .sobel      (sobel),
        .data_count_camera_fifo(data_count_cam_fifo),
        .din        (dout_cam_fifo),
        .rd_camera  (rd_en_cam_fifo),
        .empty_fifo (empty_vga_fifo),
        .dout       (din_vga_fifo),
        .sdram_cke  (sdram_cke), 
        .sdram_cs_n (sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n (sdram_we_n), 
        .sdram_addr (sdram_addr),
        .sdram_ba   (sdram_ba), 
        .sdram_dqm  (sdram_dqm),
        .sdram_dq   (sdram_dq)
    );
     
    vga_top i_vga_interface (
        .clk        (clk_vga),
        .rst_n      (rst_n),
        .sobel      (sobel),
        .empty_fifo (empty_vga_fifo),
        .din        (din_vga_fifo),
        .clk_vga    (clk_vga),
        .rd_en      (rd_en_vga),
        .threshold  (threshold),
        .vga_r  (vga_out_r),
        .vga_g  (vga_out_g),
        .vga_b  (vga_out_b),
        .vga_out_vs (vga_out_vs),
        .vga_out_hs (vga_out_hs)
    );
	 assign vga_r = {vga_out_r , 3'b111};
    assign vga_g = {vga_out_g , 3'b111};
	 assign vga_b = {vga_out_b , 3'b111};
	 
    debounce_explicit debounce_key0 (.clk(clk), .rst_n(rst_n), .sw(!key[0]), .db_level(), .db_tick(key1_tick));
    debounce_explicit debounce_key1 (.clk(clk), .rst_n(rst_n), .sw(!key[1]), .db_level(), .db_tick(key2_tick));
    debounce_explicit debounce_key2 (.clk(clk), .rst_n(rst_n), .sw(!key[2]), .db_level(), .db_tick(key3_tick));

endmodule