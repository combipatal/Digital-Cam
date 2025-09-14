`timescale 1ns / 1ps

module bram_sobel_filter(
    input wire clk,
    input wire rst_n,
    
    // Frame buffer interface
    output wire [16:0] fb_addr,
    input wire [15:0] fb_data,
    
    // Processed pixel output (real-time)
    output reg pixel_valid,
    output reg [15:0] pixel_data,
    
    // Control signals
    input wire start_process,
    output reg process_done
);

    // Sobel kernels
    localparam GX_1 = -1, GX_2 = 0, GX_3 = 1;
    localparam GX_4 = -2, GX_5 = 0, GX_6 = 2;
    localparam GX_7 = -1, GX_8 = 0, GX_9 = 1;
    
    localparam GY_1 = -1, GY_2 = -2, GY_3 = -1;
    localparam GY_4 = 0,  GY_5 = 0,  GY_6 = 0;
    localparam GY_7 = 1,  GY_8 = 2,  GY_9 = 1;
    
    localparam WIDTH = 320;
    localparam HEIGHT = 240;
    
    // 3x3 window pixels
    reg [15:0] p00, p01, p02; // Top row
    reg [15:0] p10, p11, p12; // Middle row  
    reg [15:0] p20, p21, p22; // Bottom row
    
    reg [8:0] x, y; // Current processing position
    reg [2:0] state;
    reg [16:0] fb_addr_reg;
    reg [1:0] pixel_count; // For loading 3x3 window
    
    localparam IDLE = 0;
    localparam LOAD_WINDOW = 1;
    localparam PROCESS = 2;
    
    // RGB565 to grayscale conversion
    function [7:0] rgb565_to_gray;
        input [15:0] rgb565;
        reg [7:0] r, g, b;
        begin
            r = {rgb565[15:11], rgb565[15:13]}; // 5-bit -> 8-bit
            g = {rgb565[10:5], rgb565[10:9]};   // 6-bit -> 8-bit
            b = {rgb565[4:0], rgb565[4:2]};     // 5-bit -> 8-bit
            rgb565_to_gray = (r * 76 + g * 150 + b * 29) >> 8;
        end
    endfunction
    
    // 3x3 convolution for Sobel edge detection
    function [15:0] sobel_convolution;
        input [7:0] p00, p01, p02;
        input [7:0] p10, p11, p12;
        input [7:0] p20, p21, p22;
        reg [15:0] gx, gy;
        reg [15:0] magnitude;
        reg [7:0] result_gray;
        begin
            // Gx convolution
            gx = (p02 + (p12 << 1) + p22) - (p00 + (p10 << 1) + p20);
            if (gx[15]) gx = -gx; // Absolute value
            
            // Gy convolution  
            gy = (p20 + (p21 << 1) + p22) - (p00 + (p01 << 1) + p02);
            if (gy[15]) gy = -gy; // Absolute value
            
            // Magnitude
            magnitude = gx + gy;
            
            // Clamp to 8-bit
            if (magnitude > 255) result_gray = 255;
            else result_gray = magnitude[7:0];
            
            // Convert back to RGB565 grayscale
            sobel_convolution = {result_gray[7:3], result_gray[7:2], result_gray[7:3]};
        end
    endfunction
    
    always @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            x <= 0;
            y <= 0;
            pixel_valid <= 0;
            pixel_data <= 0;
            process_done <= 0;
            fb_addr_reg <= 0;
            pixel_count <= 0;
            p00 <= 0; p01 <= 0; p02 <= 0;
            p10 <= 0; p11 <= 0; p12 <= 0;
            p20 <= 0; p21 <= 0; p22 <= 0;
        end else begin
            case (state)
                IDLE: begin
                    pixel_valid <= 0;
                    process_done <= 0;
                    if (start_process) begin
                        state <= LOAD_WINDOW;
                        y <= 1; // Start from y=1 (skip border)
                        x <= 1; // Start from x=1 (skip border)
                        pixel_count <= 0;
                        fb_addr_reg <= (1 * WIDTH) + 1; // (y*WIDTH + x)
                    end
                end
                
                LOAD_WINDOW: begin
                    // Load 3x3 window pixels
                    case (pixel_count)
                        2'd0: p00 <= fb_data;
                        2'd1: p01 <= fb_data;
                        2'd2: p02 <= fb_data;
                        2'd3: p10 <= fb_data;
                    endcase
                    
                    pixel_count <= pixel_count + 1;
                    fb_addr_reg <= fb_addr_reg + 1;
                    
                    if (pixel_count == 3) begin
                        state <= PROCESS;
                        pixel_count <= 0;
                    end
                end
                
                PROCESS: begin
                    if (y >= 1 && y < HEIGHT-1 && x >= 1 && x < WIDTH-1) begin
                        // Load remaining pixels and perform convolution
                        case (pixel_count)
                            2'd0: p11 <= fb_data;
                            2'd1: p12 <= fb_data;
                            2'd2: p20 <= fb_data;
                            2'd3: begin
                                p21 <= fb_data;
                                // Perform 3x3 convolution
                                pixel_data <= sobel_convolution(
                                    rgb565_to_gray(p00), rgb565_to_gray(p01), rgb565_to_gray(p02),
                                    rgb565_to_gray(p10), rgb565_to_gray(p11), rgb565_to_gray(p12),
                                    rgb565_to_gray(p20), rgb565_to_gray(p21), rgb565_to_gray(p22)
                                );
                                pixel_valid <= 1;
                            end
                        endcase
                        
                        pixel_count <= pixel_count + 1;
                        fb_addr_reg <= fb_addr_reg + 1;
                        
                        if (pixel_count == 3) begin
                            pixel_valid <= 0;
                            x <= x + 1;
                            if (x == WIDTH - 2) begin
                                x <= 1;
                                y <= y + 1;
                                if (y == HEIGHT - 2) begin
                                    state <= IDLE;
                                    process_done <= 1;
                                end else begin
                                    // Load new window for next row
                                    fb_addr_reg <= ((y + 1) * WIDTH) + 1;
                                    state <= LOAD_WINDOW;
                                end
                            end else begin
                                // Load new window for next column
                                fb_addr_reg <= (y * WIDTH) + (x + 1);
                                state <= LOAD_WINDOW;
                            end
                        end
                    end
                end
            endcase
        end
    end
    
    // Connect fb_addr_reg to fb_addr output
    assign fb_addr = fb_addr_reg;

endmodule
