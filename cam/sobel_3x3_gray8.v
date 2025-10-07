// 3x3 Sobel Edge Detection Filter (8-bit grayscale) - 2-line buffer + boundary handling
// - Forms a real 3x3 window (stores y-1, y-2 lines + horizontal 3-tap shift registers)
// - Clamps pixels at left/top boundaries to edge values for valid output from first pixel
// - Pipeline latency: total 5 clocks (Sobel gradient calculation + threshold processing)
module sobel_3x3_gray8 #(
    parameter integer IMG_WIDTH  = 320,
    parameter integer IMG_HEIGHT = 240
)(
    input  wire        clk,
    input  wire        enable,
    input  wire [7:0]  pixel_in,
    input  wire [16:0] pixel_addr,   // legacy interface compatibility (unused)
    input  wire        vsync,
    input  wire        active_area,
    input  wire [7:0]  threshold,    // edge threshold
    output reg  [7:0]  pixel_out,
    output reg         sobel_ready
);

    localparam integer PIPE_LAT = 5; // Sobel internal pipeline latency

    // Extract coordinates from active_area (independent of pixel_addr)
    localparam integer COL_BITS = (IMG_WIDTH  <= 256) ? 8 :
                                  (IMG_WIDTH  <= 512) ? 9 : 10;
    localparam integer ROW_BITS = (IMG_HEIGHT <= 256) ? 8 :
                                  (IMG_HEIGHT <= 512) ? 9 : 10;

    reg [COL_BITS-1:0] x_coord = {COL_BITS{1'b0}};
    reg [ROW_BITS-1:0] y_coord = {ROW_BITS{1'b0}};

    // Frame/line boundary detection
    reg vsync_prev  = 1'b0;
    reg active_prev = 1'b0;
    always @(posedge clk) begin
        vsync_prev  <= vsync;
        active_prev <= active_area;
    end
    wire vsync_fall  = vsync_prev & ~vsync;
    wire active_rise = active_area & ~active_prev;
    wire active_fall = ~active_area & active_prev;
    wire frame_start = vsync_fall;
    wire line_start  = active_rise;

    // Coordinate counting
    always @(posedge clk) begin
        if (frame_start) begin
            x_coord <= {COL_BITS{1'b0}};
            y_coord <= {ROW_BITS{1'b0}};
        end else if (enable) begin
            if (active_rise) begin
                x_coord <= {COL_BITS{1'b0}};
            end else if (active_area) begin
                if (x_coord < IMG_WIDTH-1)
                    x_coord <= x_coord + 1'b1;
            end
            if (active_fall) begin
                if (y_coord < IMG_HEIGHT-1)
                    y_coord <= y_coord + 1'b1;
            end
        end
    end
    wire [COL_BITS-1:0] x_curr = line_start ? {COL_BITS{1'b0}} :
                                 (active_area ? ((x_coord == IMG_WIDTH-1) ? x_coord : (x_coord + 1'b1)) : x_coord);
    wire [COL_BITS-1:0] x = x_curr;
    wire [ROW_BITS-1:0] y = y_coord;

    // Align coordinates and pixel data to Sobel pipeline latency
    reg [COL_BITS-1:0] x_d1 = {COL_BITS{1'b0}}, x_d2 = {COL_BITS{1'b0}},
                         x_d3 = {COL_BITS{1'b0}}, x_d4 = {COL_BITS{1'b0}}, x_d5 = {COL_BITS{1'b0}};
    reg [ROW_BITS-1:0] y_d1 = {ROW_BITS{1'b0}}, y_d2 = {ROW_BITS{1'b0}},
                         y_d3 = {ROW_BITS{1'b0}}, y_d4 = {ROW_BITS{1'b0}}, y_d5 = {ROW_BITS{1'b0}};
    reg [7:0] pix_d1 = 8'd0, pix_d2 = 8'd0, pix_d3 = 8'd0, pix_d4 = 8'd0, pix_d5 = 8'd0;
    always @(posedge clk) begin
        if (enable && active_area) begin
            x_d1 <= x;   x_d2 <= x_d1;   x_d3 <= x_d2;   x_d4 <= x_d3;   x_d5 <= x_d4;
            y_d1 <= y;   y_d2 <= y_d1;   y_d3 <= y_d2;   y_d4 <= y_d3;   y_d5 <= y_d4;
            pix_d1 <= pixel_in; pix_d2 <= pix_d1; pix_d3 <= pix_d2; pix_d4 <= pix_d3; pix_d5 <= pix_d4;
        end else begin
            x_d1 <= {COL_BITS{1'b0}}; x_d2 <= {COL_BITS{1'b0}}; x_d3 <= {COL_BITS{1'b0}};
            x_d4 <= {COL_BITS{1'b0}}; x_d5 <= {COL_BITS{1'b0}};
            y_d1 <= {ROW_BITS{1'b0}}; y_d2 <= {ROW_BITS{1'b0}}; y_d3 <= {ROW_BITS{1'b0}};
            y_d4 <= {ROW_BITS{1'b0}}; y_d5 <= {ROW_BITS{1'b0}};
            pix_d1 <= 8'd0; pix_d2 <= 8'd0; pix_d3 <= 8'd0; pix_d4 <= 8'd0; pix_d5 <= 8'd0;
        end
    end

    // Two line buffers (ping-pong) + horizontal 3-tap shift registers
    reg [7:0] lb0 [0:IMG_WIDTH-1];
    reg [7:0] lb1 [0:IMG_WIDTH-1];
    reg       wr_sel = 1'b0; // toggles at each line start

    reg [7:0] top_sr0, top_sr1, top_sr2; // y-2
    reg [7:0] mid_sr0, mid_sr1, mid_sr2; // y-1
    reg [7:0] cur_sr0, cur_sr1, cur_sr2; // y

    // Internal valid signal (uses active_area directly since it's already delayed)
    wire window_valid = enable && active_area;

    // Read line buffers at current x position (before writing)
    wire [7:0] top_in = (wr_sel == 1'b0) ? lb0[x] : lb1[x]; // y-2
    wire [7:0] mid_in = (wr_sel == 1'b0) ? lb1[x] : lb0[x]; // y-1

    // Shift register updates and line buffer writes
    always @(posedge clk) begin
        if (frame_start) begin
            wr_sel <= 1'b0;
            top_sr0 <= 8'd0; top_sr1 <= 8'd0; top_sr2 <= 8'd0;
            mid_sr0 <= 8'd0; mid_sr1 <= 8'd0; mid_sr2 <= 8'd0;
            cur_sr0 <= 8'd0; cur_sr1 <= 8'd0; cur_sr2 <= 8'd0;
        end else begin
            if (line_start) begin
                wr_sel  <= ~wr_sel;
                top_sr0 <= 8'd0; top_sr1 <= 8'd0; top_sr2 <= 8'd0;
                mid_sr0 <= 8'd0; mid_sr1 <= 8'd0; mid_sr2 <= 8'd0;
                cur_sr0 <= 8'd0; cur_sr1 <= 8'd0; cur_sr2 <= 8'd0;
            end
            if (enable && active_area) begin
                top_sr2 <= top_sr1;  top_sr1 <= top_sr0;  top_sr0 <= top_in;
                mid_sr2 <= mid_sr1;  mid_sr1 <= mid_sr0;  mid_sr0 <= mid_in;
                cur_sr2 <= cur_sr1;  cur_sr1 <= cur_sr0;  cur_sr0 <= pixel_in;
                if (wr_sel == 1'b0) lb0[x] <= pixel_in; else lb1[x] <= pixel_in;
            end
        end
    end

    // Form 3x3 window from next-cycle shift results (including current pixel)
    wire [7:0] n_top_sr0 = top_in;
    wire [7:0] n_top_sr1 = top_sr0;
    wire [7:0] n_top_sr2 = top_sr1;
    wire [7:0] n_mid_sr0 = mid_in;
    wire [7:0] n_mid_sr1 = mid_sr0;
    wire [7:0] n_mid_sr2 = mid_sr1;
    wire [7:0] n_cur_sr0 = pixel_in;
    wire [7:0] n_cur_sr1 = cur_sr0;
    wire [7:0] n_cur_sr2 = cur_sr1;

    // Top/left 2 pixels are treated as border pixels and output black
    wire border_pixel = (x_d5 < 2) || (y_d5 < 2);

    // Boundary clamping: form complete 3x3 window from image boundaries
    wire [7:0] top_x0 = n_top_sr0;
    wire [7:0] top_x1 = (x == 0) ? n_top_sr0 : n_top_sr1;
    wire [7:0] top_x2 = (x == 0) ? n_top_sr0 : ((x == 1) ? n_top_sr1 : n_top_sr2);
    wire [7:0] mid_x0 = n_mid_sr0;
    wire [7:0] mid_x1 = (x == 0) ? n_mid_sr0 : n_mid_sr1;
    wire [7:0] mid_x2 = (x == 0) ? n_mid_sr0 : ((x == 1) ? n_mid_sr1 : n_mid_sr2);
    wire [7:0] cur_x0 = n_cur_sr0;
    wire [7:0] cur_x1 = (x == 0) ? n_cur_sr0 : n_cur_sr1;
    wire [7:0] cur_x2 = (x == 0) ? n_cur_sr0 : ((x == 1) ? n_cur_sr1 : n_cur_sr2);

    wire [7:0] selT_x0 = (y == 0) ? cur_x0 : ((y == 1) ? mid_x0 : top_x0);
    wire [7:0] selT_x1 = (y == 0) ? cur_x1 : ((y == 1) ? mid_x1 : top_x1);
    wire [7:0] selT_x2 = (y == 0) ? cur_x2 : ((y == 1) ? mid_x2 : top_x2);
    wire [7:0] selM_x0 = (y == 0) ? cur_x0 : mid_x0;
    wire [7:0] selM_x1 = (y == 0) ? cur_x1 : mid_x1;
    wire [7:0] selM_x2 = (y == 0) ? cur_x2 : mid_x2;

    // Final 3x3 pixel window
    wire [7:0] g00 = selT_x2; // (x-2, y-2)
    wire [7:0] g01 = selT_x1; // (x-1, y-2)
    wire [7:0] g02 = selT_x0; // (x  , y-2)
    wire [7:0] g10 = selM_x2; // (x-2, y-1)
    wire [7:0] g11 = selM_x1; // (x-1, y-1)
    wire [7:0] g12 = selM_x0; // (x  , y-1)
    wire [7:0] g20 = cur_x2;  // (x-2, y  )
    wire [7:0] g21 = cur_x1;  // (x-1, y  )
    wire [7:0] g22 = cur_x0;  // (x  , y  )

    // Sobel gradient calculation (stage 1: |Gx|, |Gy|, stage 2: magnitude/threshold)
    // Gx = [-1 0 +1; -2 0 +2; -1 0 +1]
    // Gy = [+1 +2 +1;  0 0  0; -1 -2 -1]
    reg [10:0] gx_abs;
    reg [10:0] gy_abs;
    reg [11:0] mag;
    wire [10:0] gx_pos = {3'b0,g02} + {2'b0,g12,1'b0} + {3'b0,g22};
    wire [10:0] gx_neg = {3'b0,g00} + {2'b0,g10,1'b0} + {3'b0,g20};
    wire [10:0] gy_pos = {3'b0,g00} + {2'b0,g01,1'b0} + {3'b0,g02};
    wire [10:0] gy_neg = {3'b0,g20} + {2'b0,g21,1'b0} + {3'b0,g22};

    reg [PIPE_LAT-1:0] vpipe = {PIPE_LAT{1'b0}};
    always @(posedge clk) begin
        if (frame_start) begin
            gx_abs <= 11'd0;
            gy_abs <= 11'd0;
            mag    <= 12'd0;
            vpipe <= {PIPE_LAT{1'b0}};
            pixel_out <= 8'd0;
            sobel_ready <= 1'b0;
        end else begin
            vpipe <= {vpipe[PIPE_LAT-2:0], window_valid};
            // stage 1: |Gx|, |Gy|
            if (window_valid) begin
                gx_abs <= (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
                gy_abs <= (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
            end else begin
                gx_abs <= 11'd0;
                gy_abs <= 11'd0;
            end
            // stage 2: magnitude + threshold output
            mag <= {1'b0,gx_abs} + {1'b0,gy_abs};
            if (vpipe[PIPE_LAT-1]) begin
                if (border_pixel) begin
                    // Top/left 2 pixels output 0 to prevent edge artifacts
                    pixel_out <= 8'h00;
                    sobel_ready <= 1'b0;
                end else begin
                    if ((mag[11:8] != 4'b0000 ? 8'hFF : mag[7:0]) >= threshold)
                        pixel_out <= 8'hFF;
                    else
                        pixel_out <= 8'h00;
                    sobel_ready <= 1'b1;
                end
            end else begin
                pixel_out <= 8'h00;
                sobel_ready <= 1'b0;
            end
        end
    end

endmodule
