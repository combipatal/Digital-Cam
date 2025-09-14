`timescale 1ns / 1ps

module bram_frame_buffer(
    input wire clk,
    input wire rst_n,
    
    // Write interface (from camera)
    input wire wr_en,
    input wire [15:0] wr_data,
    input wire [16:0] wr_addr, // 320x240 = 76800 pixels
    
    // Read interface (to VGA)
    input wire rd_en,
    input wire [16:0] rd_addr,
    output reg [15:0] rd_data,
    
    // Control signals
    input wire sobel_mode // 0: original, 1: sobel processed
);

    // Single BRAM for current frame (320x240)
    reg [15:0] frame_buffer [0:76799]; // 320x240 = 76800 pixels
    
    // Write to BRAM
    always @(posedge clk) begin
        if (wr_en && rst_n) begin
            frame_buffer[wr_addr] <= wr_data;
        end
    end
    
    // Read from BRAM
    always @(posedge clk) begin
        if (rst_n) begin
            rd_data <= frame_buffer[rd_addr];
        end
    end
    

endmodule
