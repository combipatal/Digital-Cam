// Revised Canny edge detector for 8-bit grayscale streams
// - Proper 3x3 window formed with two line buffers (IMG_WIDTH deep)
// - Computes Sobel magnitude + direction, applies NMS + hysteresis
// - Output pixel corresponds to (x-1, y-1) of the input stream
module canny_3x3_gray8 #(
    parameter integer IMG_WIDTH = 320
)(
    input  wire        clk,
    input  wire        enable,
    input  wire [7:0]  pixel_in,
    input  wire [16:0] pixel_addr,   // kept for interface compatibility (unused)
    input  wire        vsync,
    input  wire        active_area,
    input  wire [7:0]  threshold_low,
    input  wire [7:0]  threshold_high,
    output reg  [7:0]  pixel_out,
    output reg         canny_ready
);

    wire _unused_addr = &{1'b0, pixel_addr};

    // ------------------------------------------------------------------
    // Timing helpers: detect frame/line boundaries
    // ------------------------------------------------------------------
    reg vsync_prev  = 1'b1;
    reg active_prev = 1'b0;
    always @(posedge clk) begin
        vsync_prev  <= vsync;
        active_prev <= active_area;
    end

    wire frame_reset = vsync_prev & ~vsync;          // VSYNC falling edge
    wire line_start  =  active_area & ~active_prev;  // rising edge of active window
    wire line_end    = ~active_area &  active_prev;  // falling edge of active window

    wire pixel_valid = enable && active_area;

    // ------------------------------------------------------------------
    // Stage-0: 3x3 pixel window (two line buffers + horizontal shift regs)
    // ------------------------------------------------------------------
    localparam integer COL_BITS = (IMG_WIDTH <= 256) ? 8 :
                                   (IMG_WIDTH <= 512) ? 9 : 10;

    reg [COL_BITS-1:0] col = {COL_BITS{1'b0}};   // 0 .. IMG_WIDTH-1
    reg [9:0] row = 10'd0;  // counts active lines

    reg [7:0] line1 [0:IMG_WIDTH-1]; // previous line (y-1)
    reg [7:0] line2 [0:IMG_WIDTH-1]; // line y-2

    reg [7:0] cur_0 = 8'd0, cur_1 = 8'd0, cur_2 = 8'd0;
    reg [7:0] l1_0  = 8'd0, l1_1  = 8'd0, l1_2  = 8'd0;
    reg [7:0] l2_0  = 8'd0, l2_1  = 8'd0, l2_2  = 8'd0;

    wire [7:0] line1_tap = line1[col];
    wire [7:0] line2_tap = line2[col];

    always @(posedge clk) begin
        if (frame_reset) begin
            col <= {COL_BITS{1'b0}};
            row <= 10'd0;
            cur_0 <= 8'd0; cur_1 <= 8'd0; cur_2 <= 8'd0;
            l1_0  <= 8'd0; l1_1  <= 8'd0; l1_2  <= 8'd0;
            l2_0  <= 8'd0; l2_1  <= 8'd0; l2_2  <= 8'd0;
        end else begin
            if (line_start) begin
                col <= {COL_BITS{1'b0}};
                cur_0 <= 8'd0; cur_1 <= 8'd0; cur_2 <= 8'd0;
                l1_0  <= 8'd0; l1_1  <= 8'd0; l1_2  <= 8'd0;
                l2_0  <= 8'd0; l2_1  <= 8'd0; l2_2  <= 8'd0;
            end else if (pixel_valid && (col < IMG_WIDTH-1)) begin
                col <= col + 1'b1;
            end

            if (line_end) begin
                if (row < 10'd1023)
                    row <= row + 1'b1;
            end

            if (pixel_valid) begin
                cur_2 <= cur_1; cur_1 <= cur_0; cur_0 <= pixel_in;
                l1_2  <= l1_1;  l1_1  <= l1_0;  l1_0  <= line1_tap;
                l2_2  <= l2_1;  l2_1  <= l2_0;  l2_0  <= line2_tap;

                line2[col] <= line1_tap;
                line1[col] <= pixel_in;
            end
        end
    end

    wire window_ready = pixel_valid && (row >= 10'd2) && (col >= 2);
    wire border_flag  = pixel_valid && ((row < 10'd2) || (col < 2));

    // Current 3x3 window taps (center is l1_1)
    wire [7:0] p00 = l2_2;
    wire [7:0] p01 = l2_1;
    wire [7:0] p02 = l2_0;
    wire [7:0] p10 = l1_2;
    wire [7:0] p11 = l1_1;
    wire [7:0] p12 = l1_0;
    wire [7:0] p20 = cur_2;
    wire [7:0] p21 = cur_1;
    wire [7:0] p22 = cur_0;

    // Sobel intermediate terms
    wire [10:0] gx_pos = {3'b000,p02} + {2'b00,p12,1'b0} + {3'b000,p22};
    wire [10:0] gx_neg = {3'b000,p00} + {2'b00,p10,1'b0} + {3'b000,p20};
    wire [10:0] gy_pos = {3'b000,p00} + {2'b00,p01,1'b0} + {3'b000,p02};
    wire [10:0] gy_neg = {3'b000,p20} + {2'b00,p21,1'b0} + {3'b000,p22};

    wire signed [11:0] gx_signed_next = {1'b0,gx_pos} - {1'b0,gx_neg};
    wire signed [11:0] gy_signed_next = {1'b0,gy_pos} - {1'b0,gy_neg};

    wire [10:0] gx_abs_next = (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
    wire [10:0] gy_abs_next = (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);

    wire [11:0] mag_sum_next = {1'b0,gx_abs_next} + {1'b0,gy_abs_next};

    wire [10:0] ax_next = gx_signed_next[11] ? (~gx_signed_next[10:0] + 11'd1) : gx_signed_next[10:0];
    wire [10:0] ay_next = gy_signed_next[11] ? (~gy_signed_next[10:0] + 11'd1) : gy_signed_next[10:0];

    wire [1:0] dir_next = (ay_next <= (ax_next >> 1))        ? 2'b00 :
                          (ax_next <= (ay_next >> 1))        ? 2'b10 :
                          ((gx_signed_next[11] ^ gy_signed_next[11]) ? 2'b01 : 2'b11);

    // ------------------------------------------------------------------
    // Stage-1: register coordinates, validity, and Sobel sums
    // ------------------------------------------------------------------
    reg [COL_BITS-1:0] col_s1 = {COL_BITS{1'b0}};
    reg [9:0] row_s1 = 10'd0;
    reg       active_s1 = 1'b0;
    reg       window_valid_s1 = 1'b0;
    reg       border_s1 = 1'b0;

    reg [11:0] mag_sum_s1 = 12'd0;
    reg [1:0]  dir_raw_s1 = 2'b00;

    always @(posedge clk) begin
        if (frame_reset) begin
            col_s1 <= {COL_BITS{1'b0}};
            row_s1 <= 10'd0;
            active_s1 <= 1'b0;
            window_valid_s1 <= 1'b0;
            border_s1 <= 1'b0;
            mag_sum_s1 <= 12'd0;
            dir_raw_s1 <= 2'b00;
        end else begin
            col_s1 <= col;
            row_s1 <= row;
            active_s1 <= pixel_valid;
            window_valid_s1 <= window_ready;
            border_s1 <= border_flag;

            if (window_ready) begin
                mag_sum_s1 <= mag_sum_next;
                dir_raw_s1 <= dir_next;
            end else begin
                mag_sum_s1 <= 12'd0;
                dir_raw_s1 <= 2'b00;
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage-2: clamp magnitude, quantize direction, track coordinates
    // ------------------------------------------------------------------
    reg [COL_BITS-1:0] col_s2 = {COL_BITS{1'b0}};
    reg [9:0] row_s2 = 10'd0;
    reg       active_s2 = 1'b0;
    reg       window_valid_s2 = 1'b0;
    reg       border_s2 = 1'b0;

    reg [7:0] mag_s2 = 8'd0;
    reg [1:0] dir_s2 = 2'b00;

    always @(posedge clk) begin
        if (frame_reset) begin
            col_s2 <= {COL_BITS{1'b0}};
            row_s2 <= 10'd0;
            active_s2 <= 1'b0;
            window_valid_s2 <= 1'b0;
            border_s2 <= 1'b0;
            mag_s2 <= 8'd0;
            dir_s2 <= 2'b00;
        end else begin
            col_s2 <= col_s1;
            row_s2 <= row_s1;
            active_s2 <= active_s1;
            window_valid_s2 <= window_valid_s1;
            border_s2 <= border_s1;

            if (window_valid_s1 && !border_s1) begin
                mag_s2 <= (mag_sum_s1[11:8] != 4'b0000) ? 8'hFF : mag_sum_s1[7:0];
                dir_s2 <= dir_raw_s1;
            end else begin
                mag_s2 <= 8'd0;
                dir_s2 <= 2'b00;
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage-3: magnitude/direction line buffers to build 3x3 mag window
    // ------------------------------------------------------------------
    reg [7:0] mag_line1 [0:IMG_WIDTH-1];
    reg [7:0] mag_line2 [0:IMG_WIDTH-1];
    reg [1:0] dir_line1 [0:IMG_WIDTH-1];
    reg [1:0] dir_line2 [0:IMG_WIDTH-1];

    reg [7:0] mag_cur0 = 8'd0, mag_cur1 = 8'd0, mag_cur2 = 8'd0;
    reg [7:0] mag_l1_0 = 8'd0, mag_l1_1 = 8'd0, mag_l1_2 = 8'd0;
    reg [7:0] mag_l2_0 = 8'd0, mag_l2_1 = 8'd0, mag_l2_2 = 8'd0;

    reg [1:0] dir_mid0 = 2'b00, dir_mid1 = 2'b00, dir_mid2 = 2'b00;

    reg [COL_BITS-1:0] col_s3 = {COL_BITS{1'b0}};
    reg [9:0] row_s3 = 10'd0;
    reg       active_s3 = 1'b0;
    reg       window_valid_s3 = 1'b0;
    reg       border_s3 = 1'b0;

    wire [7:0] mag_l1_tap = mag_line1[col_s2];
    wire [7:0] mag_l2_tap = mag_line2[col_s2];
    wire [1:0] dir_l1_tap = dir_line1[col_s2];

    wire [7:0] mag_store = (window_valid_s2 && !border_s2) ? mag_s2 : 8'd0;
    wire [1:0] dir_store = (window_valid_s2 && !border_s2) ? dir_s2 : 2'b00;

    always @(posedge clk) begin
        if (frame_reset) begin
            mag_cur0 <= 8'd0; mag_cur1 <= 8'd0; mag_cur2 <= 8'd0;
            mag_l1_0 <= 8'd0; mag_l1_1 <= 8'd0; mag_l1_2 <= 8'd0;
            mag_l2_0 <= 8'd0; mag_l2_1 <= 8'd0; mag_l2_2 <= 8'd0;
            dir_mid0 <= 2'b00; dir_mid1 <= 2'b00; dir_mid2 <= 2'b00;
            col_s3 <= {COL_BITS{1'b0}};
            row_s3 <= 10'd0;
            active_s3 <= 1'b0;
            window_valid_s3 <= 1'b0;
            border_s3 <= 1'b0;
        end else begin
            col_s3 <= col_s2;
            row_s3 <= row_s2;
            active_s3 <= active_s2;
            window_valid_s3 <= window_valid_s2;
            border_s3 <= border_s2;

            if (active_s2) begin
                mag_line2[col_s2] <= mag_l1_tap;
                mag_line1[col_s2] <= mag_store;
                dir_line2[col_s2] <= dir_line1[col_s2];
                dir_line1[col_s2] <= dir_store;

                if (col_s2 == 0) begin
                    mag_cur2 <= 8'd0; mag_cur1 <= 8'd0; mag_cur0 <= mag_store;
                    mag_l1_2 <= 8'd0; mag_l1_1 <= 8'd0; mag_l1_0 <= mag_l1_tap;
                    mag_l2_2 <= 8'd0; mag_l2_1 <= 8'd0; mag_l2_0 <= mag_l2_tap;
                    dir_mid2 <= 2'b00; dir_mid1 <= 2'b00; dir_mid0 <= dir_l1_tap;
                end else begin
                    mag_cur2 <= mag_cur1;
                    mag_cur1 <= mag_cur0;
                    mag_cur0 <= mag_store;
                    mag_l1_2 <= mag_l1_1;
                    mag_l1_1 <= mag_l1_0;
                    mag_l1_0 <= mag_l1_tap;
                    mag_l2_2 <= mag_l2_1;
                    mag_l2_1 <= mag_l2_0;
                    mag_l2_0 <= mag_l2_tap;
                    dir_mid2 <= dir_mid1;
                    dir_mid1 <= dir_mid0;
                    dir_mid0 <= dir_l1_tap;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage-4: Non-maximum suppression & double threshold hysteresis
    // ------------------------------------------------------------------
    wire [7:0] m00 = mag_l2_2;
    wire [7:0] m01 = mag_l2_1;
    wire [7:0] m02 = mag_l2_0;
    wire [7:0] m10 = mag_l1_2;
    wire [7:0] m11 = mag_l1_1;
    wire [7:0] m12 = mag_l1_0;
    wire [7:0] m20 = mag_cur2;
    wire [7:0] m21 = mag_cur1;
    wire [7:0] m22 = mag_cur0;

    wire [1:0] dir_center = dir_mid1;

    wire [7:0] nb_a = (dir_center == 2'b00) ? m10 :
                      (dir_center == 2'b10) ? m01 :
                      (dir_center == 2'b01) ? m02 :
                                              m00;

    wire [7:0] nb_b = (dir_center == 2'b00) ? m12 :
                      (dir_center == 2'b10) ? m21 :
                      (dir_center == 2'b01) ? m20 :
                                              m22;

    wire       nms_keep = (m11 >= nb_a) && (m11 >= nb_b);
    wire [7:0] nms_mag  = nms_keep ? m11 : 8'd0;

    wire is_strong_center = (nms_mag >= threshold_high);
    wire is_weak_center   = (nms_mag >= threshold_low);

    wire neigh_strong =
        (m00 >= threshold_high) | (m01 >= threshold_high) | (m02 >= threshold_high) |
        (m10 >= threshold_high) | (m12 >= threshold_high) |
        (m20 >= threshold_high) | (m21 >= threshold_high) | (m22 >= threshold_high);

    wire final_valid = window_valid_s3 && active_s3 && !border_s3;

    always @(posedge clk) begin
        if (frame_reset) begin
            pixel_out   <= 8'd0;
            canny_ready <= 1'b0;
        end else if (final_valid) begin
            if (is_strong_center || (is_weak_center && neigh_strong))
                pixel_out <= 8'hFF;
            else
                pixel_out <= 8'h00;
            canny_ready <= 1'b1;
        end else begin
            pixel_out   <= 8'h00;
            canny_ready <= 1'b0;
        end
    end

endmodule
