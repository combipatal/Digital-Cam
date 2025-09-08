`timescale 1ns / 1ps
`default_nettype none 

/*
 *  Uses X,Y pixel counters from VGA driver
 *  to form an address generator to read from BRAM; output
 *  RGB pixel data from BRAM during active video region;  
 *  wraps VGA sync pulses 
 *
 *  NOTE:  
 *  - QVGA (320x240) image is displayed in the center of a 
 *    VGA (640x480) screen.
 */

module vga_top
    (   input wire          i_clk25m,
        input wire          i_rstn_clk25m,
        
        // VGA driver signals
        output wire [9:0]   o_VGA_x,
        output wire [9:0]   o_VGA_y, 
        output wire         o_VGA_vsync,
        output wire         o_VGA_hsync, 
        output wire         o_VGA_video,
        output wire [3:0]   o_VGA_red,
        output wire [3:0]   o_VGA_green,
        output wire [3:0]   o_VGA_blue, 
        
        // VGA read from BRAM 
        input  wire [11:0] i_pix_data, 
        output wire [16:0] o_pix_addr
    );
	 
    // 1. Define the area where the 320x240 image will be displayed on the 640x480 screen
    localparam IMG_X_START = 160;
    localparam IMG_X_END   = 480; // 160 + 320
    localparam IMG_Y_START = 120;
    localparam IMG_Y_END   = 360; // 120 + 240

    wire w_active_area;

    // 2. Instantiate VGA driver to get timing signals
    vga_driver
    #(  .hDisp(640), 
        .hFp(16), 
        .hPulse(96), 
        .hBp(48), 
        .vDisp(480), 
        .vFp(10), 
        .vPulse(2),
        .vBp(33)                )
    vga_timing_signals
    (   .i_clk(i_clk25m         ),
        .i_rstn(i_rstn_clk25m   ),
        
        // VGA timing signals
        .o_x_counter(o_VGA_x    ),
        .o_y_counter(o_VGA_y    ),
        .o_video(o_VGA_video    ), 
        .o_vsync(o_VGA_vsync    ),
        .o_hsync(o_VGA_hsync    )
    );
    
    // 3. Generate BRAM read address based on VGA coordinates
    assign w_active_area = (o_VGA_x >= IMG_X_START) && (o_VGA_x < IMG_X_END) &&
                           (o_VGA_y >= IMG_Y_START) && (o_VGA_y < IMG_Y_END);

    wire [8:0] mem_x; // 320 -> 9 bits
    wire [7:0] mem_y; // 240 -> 8 bits
    
    assign mem_x = o_VGA_x - IMG_X_START;
    assign mem_y = o_VGA_y - IMG_Y_START;

    // Final memory address for BRAM
    assign o_pix_addr = mem_y * 320 + mem_x;
    
    // 4. Determine final RGB output
    // If inside the 'active area', output data from BRAM. Otherwise, output black.
    assign o_VGA_red   = w_active_area ? i_pix_data[11:8] : 4'h0;
    assign o_VGA_green = w_active_area ? i_pix_data[7:4]  : 4'h0;
    assign o_VGA_blue  = w_active_area ? i_pix_data[3:0]  : 4'h0;
			 
endmodule
