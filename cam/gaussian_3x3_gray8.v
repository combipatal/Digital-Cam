// 3x3 Gaussian blur for 8-bit grayscale (streaming)
// - Uses two line buffers (image width deep) + 3-tap horizontal shift registers
// - filter_ready is asserted only when a full 3x3 window is valid
// - Designed for IMG_WIDTH = 320 by default (matches VGA active window)
module gaussian_3x3_gray8 #(
    parameter integer IMG_WIDTH = 320
)(
    input  wire        clk,
    input  wire        enable,
    input  wire [7:0]  pixel_in,
    input  wire [16:0] pixel_addr,   // unused (kept for interface compatibility)
    input  wire        vsync,        // active-low VSYNC from VGA controller
    input  wire        active_area,  // 1 during active 320x240 window
    output reg  [7:0]  pixel_out,
    output reg         filter_ready
);

    // Edge detectors
    reg vsync_prev  = 1'b1;
    reg active_prev = 1'b0;
    always @(posedge clk) begin
        vsync_prev  <= vsync;
        active_prev <= active_area;
    end

    wire vsync_fall  = vsync_prev & ~vsync;           // VSYNC goes low (frame start in this design)
    wire active_rise = active_area & ~active_prev;     // start of active line
    wire active_fall = ~active_area & active_prev;     // end of active line

    // Position within active window
    localparam integer COL_BITS = (IMG_WIDTH <= 256) ? 8 :
                                   (IMG_WIDTH <= 512) ? 9 : 10;

    reg [COL_BITS-1:0] col = {COL_BITS{1'b0}};   // 0..IMG_WIDTH-1
    reg [9:0] row = 10'd0;  // counts active lines, saturates

    // Two line buffers (previous two lines)
    reg [7:0] line1 [0:IMG_WIDTH-1]; // line N-1
    reg [7:0] line2 [0:IMG_WIDTH-1]; // line N-2

    // Horizontal 3-tap shift registers per line
    reg [7:0] cur_0 = 8'd0, cur_1 = 8'd0, cur_2 = 8'd0;  // current line taps (x, x-1, x-2)
    reg [7:0] l1_0  = 8'd0, l1_1  = 8'd0, l1_2  = 8'd0;  // line1 taps     (x, x-1, x-2)
    reg [7:0] l2_0  = 8'd0, l2_1  = 8'd0, l2_2  = 8'd0;  // line2 taps     (x, x-1, x-2)

    // One-cycle pipeline for the weighted sum
    reg [11:0] sum_blur = 12'd0; // max 16*255=4080

    // Delay valid by one cycle to align with sum pipeline
    reg active_d1 = 1'b0;
    reg window_valid_d1 = 1'b0;
    reg [7:0] pixel_in_d1 = 8'd0;   // pass-through source for border

    // Read taps from line buffers at current column (combinational read of reg array)
    wire [7:0] line1_tap = line1[col];
    wire [7:0] line2_tap = line2[col];
    // Border flag (top/left 2 pixels), delayed to stage-2
    reg border_d1 = 1'b0;

    // Stage-1: advance window and compute weighted sum
    always @(posedge clk) begin
        if (vsync_fall) begin
            // start of frame: reset position and taps
            col <= {COL_BITS{1'b0}};
            row <= 10'd0;
            {cur_0,cur_1,cur_2} <= 24'd0;
            {l1_0,l1_1,l1_2}    <= 24'd0;
            {l2_0,l2_1,l2_2}    <= 24'd0;
            sum_blur <= 12'd0;
            active_d1 <= 1'b0;
            window_valid_d1 <= 1'b0;
        end else if (enable) begin
            if (active_rise) begin
                // new active line: reset horizontal taps only
                col <= {COL_BITS{1'b0}};
                {cur_0,cur_1,cur_2} <= 24'd0;
                {l1_0,l1_1,l1_2}    <= 24'd0;
                {l2_0,l2_1,l2_2}    <= 24'd0;
                sum_blur <= 12'd0;
                // NOTE: row++ moved to active_fall
            end else if (active_area) begin
                // regular shift
                cur_2 <= cur_1; cur_1 <= cur_0; cur_0 <= pixel_in;
                l1_2  <= l1_1;  l1_1  <= l1_0;  l1_0  <= line1_tap;
                l2_2  <= l2_1;  l2_1  <= l2_0;  l2_0  <= line2_tap;

                // Gaussian Kernel:
                // [1 2 1]
                // [2 4 2]
                // [1 2 1]
                sum_blur <= (cur_2 * 1) + (cur_1 * 2) + (cur_0 * 1)
                          + (l1_2  * 2) + (l1_1  * 4) + (l1_0  * 2)
                          + (l2_2  * 1) + (l2_1  * 2) + (l2_0  * 1);
                
                // update line buffers
                line2[col] <= line1_tap;
                line1[col] <= pixel_in;

                if (col < IMG_WIDTH-1) col <= col + 1'b1;
            end else if (active_fall) begin
                // end of active line: now advance row
                if (row < 10'd1023) row <= row + 1'b1;
            end

            // pipeline-valid alignment
            active_d1       <= active_area;
            window_valid_d1 <= (row >= 10'd2) && (col >= 2) && active_area;
            pixel_in_d1     <= pixel_in;
            border_d1       <= active_area && ((row < 10'd2) || (col < 2));
        end
    end


    // Stage-2: normalize and output
    always @(posedge clk) begin
        if (enable && active_d1) begin
            if (border_d1) begin
                // 경계 픽셀 처리: 원본 픽셀을 그대로 통과시키고, filter_ready는 0으로 설정
                pixel_out   <= pixel_in_d1;
                filter_ready <= 1'b0;
            end else if (window_valid_d1) begin
                // valid 3x3 window -> filtered output
                pixel_out   <= sum_blur[11:4]; // sum / 16
                filter_ready <= 1'b1; 
            end else begin
                pixel_out   <= 8'h00;
                filter_ready <= 1'b0;
            end
        end else begin
            pixel_out   <= 8'h00;
            filter_ready <= 1'b0;
        end
    end

endmodule
