`timescale 1ns / 1ps

module top_module(
    input wire clk, rst_n,
    input wire[3:0] key, // key[1:0] for increasing/decreasing threshold for edge detection, key[2] to change display between raw video or edge detected video
    input wire sw0, // Switch 0 for camera register resend
    
    // Camera pinouts
    input wire cmos_pclk, cmos_href, cmos_vsync,
    input wire[7:0] cmos_db,
    inout cmos_sda, cmos_scl, 
    output wire cmos_rst_n, cmos_pwdn, cmos_xclk,
    
    // Debugging
    output wire[17:0] led, 
    
    // No SDRAM interface needed for BRAM implementation
    
    // VGA output - RGB888 format
    output wire[7:0] vga_out_r,
    output wire[7:0] vga_out_g,
    output wire[7:0] vga_out_b,
    output wire vga_out_vs, vga_out_hs,
    output wire vga_out_sync_n,
    output wire vga_out_blank_n,
    output wire vga_out_clk
);
 
    // Wires for data path
    wire[15:0] camera_fifo_dout;
    wire camera_fifo_empty;
    wire[15:0] camera_fifo_data_count; // 16-bit for 64K FIFO
    
    wire[15:0] vga_pixel_data;
    wire vga_data_valid;
    wire[11:0] vga_pixel_x, vga_pixel_y;
    
    // Wires for control signals
    wire clk_vga;
    wire vga_rd_en;
    wire locked_vga;
    reg[7:0] threshold = 0;
    reg sobel = 0;
    
    // Debounced key presses
    wire key1_tick, key2_tick, key3_tick;
    
    // Switch debounce
    wire sw0_tick;

    // Register operation for sobel filter controls
    always @(posedge clk, negedge rst_n) begin
        if(!rst_n) begin
            threshold <= 8'd100;
            sobel <= 0;
        end
        else begin
            if (key1_tick) threshold <= threshold + 1; // decrease sensitivity
            if (key2_tick) threshold <= threshold - 1; // increase sensitivity
            if (key3_tick) sobel <= !sobel; // toggle raw/sobel video
        end
    end
    
    // Module Instantiations
    
    // Camera Interface: Captures video from OV7670 and puts it into a FIFO
    camera_interface m0 (
        .clk(clk),
        .rst_n(rst_n && locked_vga), // VGA PLL이 lock될 때까지 reset 유지
        .key(key),
        .resend_config(sw0_tick), // Switch 0 for camera register resend
        // Camera FIFO outputs
        .rd_en(rd_camera_fifo), // Read enable from BRAM interface
        .rdclk(clk), // Use main clock for BRAM interface
        .dout(camera_fifo_dout),
        .empty(camera_fifo_empty),
        .data_count(camera_fifo_data_count),
        // Camera pinouts
        .cmos_pclk(cmos_pclk),
        .cmos_href(cmos_href),
        .cmos_vsync(cmos_vsync),
        .cmos_db(cmos_db),
        .cmos_sda(cmos_sda),
        .cmos_scl(cmos_scl), 
        .cmos_rst_n(cmos_rst_n),
        .cmos_pwdn(cmos_pwdn),
        .cmos_xclk(cmos_xclk),
        // Debugging
        .led(led[3:0])
    );
     
    // BRAM Interface: Reads from camera FIFO, stores frame in BRAM, processes with Sobel, outputs to VGA
    bram_interface m1 (
        .clk(clk),
        .rst_n(rst_n && locked_vga),
        // Camera FIFO interface
        .camera_fifo_count(camera_fifo_data_count),
        .camera_fifo_data(camera_fifo_dout),
        .rd_camera_fifo(rd_camera_fifo),
        // VGA interface
        .vga_rd_en(vga_rd_en),
        .vga_pixel_x(vga_pixel_x),
        .vga_pixel_y(vga_pixel_y),
        .vga_pixel_data(vga_pixel_data),
        .vga_data_valid(vga_data_valid),
        // Control signals
        .sobel_mode(sobel),
        .led_status(led[7:4])
    );
     
    // VGA Interface: Reads from BRAM and displays the image on the monitor
    vga_interface m2 (
        .clk(clk), // Use main 50MHz clock
        .rst_n(rst_n && locked_vga),
        .sobel(sobel),
        // BRAM inputs
        .empty_fifo(~vga_data_valid), // Use vga_data_valid to determine if data is available
        .din(vga_pixel_data),
        // VGA control signals
        .clk_vga(clk_vga),
        .rd_en(vga_rd_en), // to bram_interface
        .threshold(threshold),
        // Pixel coordinates output
        .pixel_x(vga_pixel_x),
        .pixel_y(vga_pixel_y),
        // VGA output pins
        .vga_out_r(vga_out_r),
        .vga_out_g(vga_out_g),
        .vga_out_b(vga_out_b),
        .vga_out_vs(vga_out_vs),
        .vga_out_hs(vga_out_hs),
        .vga_out_sync_n(vga_out_sync_n),
        .vga_out_blank_n(vga_out_blank_n),
        .vga_out_clk(vga_out_clk)
    );
     
    // Debounce logic for keys
    debounce_explicit m3 (
        .clk(clk),
        .rst_n(rst_n),
        .sw(!key[0]),
        .db_level(),
        .db_tick(key1_tick)
    );
     
    debounce_explicit m4 (
        .clk(clk),
        .rst_n(rst_n),
        .sw(!key[1]),
        .db_level(),
        .db_tick(key2_tick)
    );
     
    debounce_explicit m5 (
        .clk(clk),
        .rst_n(rst_n),
        .sw(!key[2]),
        .db_level(),
        .db_tick(key3_tick)
    );
    
    // Switch 0 debounce for camera register resend
    debounce_explicit m6 (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw0),
        .db_level(),
        .db_tick(sw0_tick)
    );
    
    // PLL for VGA clock (25MHz)
    pll_25MHz m7 (
        .inclk0(clk),
        .c0(clk_vga),
        .areset(~rst_n),
        .locked(locked_vga)
    );
    
    // 디버깅용 LED 할당
    assign led[17:8] = {
        1'b0,               // LED[17]: Reserved
        locked_vga,         // LED[16]: VGA PLL lock  
        vga_data_valid,     // LED[15]: VGA data valid
        sobel,              // LED[14]: Sobel mode
        1'b0,               // LED[13]: Reserved
        1'b0,               // LED[12]: Reserved
        1'b0,               // LED[11]: Reserved
        1'b0,               // LED[10]: Reserved
        1'b0,               // LED[9]: Reserved
        1'b0                // LED[8]: Reserved
    };
     
endmodule