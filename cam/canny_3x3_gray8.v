// Canny-like edge detector (hysteresis only, no explicit NMS) for 8-bit grayscale
// - Input should be pre-blurred (e.g., Gaussian) to suppress noise
// - Computes Sobel magnitude, then applies double threshold with 8-neighbor hysteresis
// - Note: This is a lightweight approximation (no full non-maximum suppression)
module canny_3x3_gray8 (
    input  wire        clk,
    input  wire        enable,
    input  wire [7:0]  pixel_in,
    input  wire [16:0] pixel_addr,
    input  wire        vsync,
    input  wire        active_area,
    input  wire [7:0]  threshold_low,
    input  wire [7:0]  threshold_high,
    output reg  [7:0]  pixel_out,
    output reg         canny_ready
);

    // init and vsync edge
    reg vsync_prev = 1'b0;
    reg active_prev = 1'b0;
    always @(posedge clk) begin
        vsync_prev  <= vsync;
        active_prev <= active_area;
    end

    reg        reset_done = 1'b0;
    reg [2:0]  init_counter = 3'd0;

    // 3x3 pixel caches
    reg [7:0] cache1 [0:2];
    reg [7:0] cache2 [0:2];
    reg [7:0] cache3 [0:2];

    // 3x3 magnitude caches (8-bit clamped magnitude)
    reg [7:0] mag1 [0:2];
    reg [7:0] mag2 [0:2];
    reg [7:0] mag3 [0:2];

    // simple guards
    wire valid_addr = 1'b1;

    // window taps
    wire [7:0] p00 = cache1[0];
    wire [7:0] p01 = cache1[1];
    wire [7:0] p02 = cache1[2];
    wire [7:0] p10 = cache2[0];
    wire [7:0] p11 = cache2[1];
    wire [7:0] p12 = cache2[2];
    wire [7:0] p20 = cache3[0];
    wire [7:0] p21 = cache3[1];
    wire [7:0] p22 = cache3[2];

    wire window_valid = enable && reset_done && valid_addr && active_area;

    // line/window maintenance for pixels and magnitudes
    always @(posedge clk) begin
        if ((vsync && !vsync_prev) || (active_area && !active_prev)) begin
            reset_done   <= 1'b0;
            init_counter <= 3'd0;
            cache1[0] <= 8'h00; cache1[1] <= 8'h00; cache1[2] <= 8'h00;
            cache2[0] <= 8'h00; cache2[1] <= 8'h00; cache2[2] <= 8'h00;
            cache3[0] <= 8'h00; cache3[1] <= 8'h00; cache3[2] <= 8'h00;
            mag1[0]   <= 8'h00; mag1[1]   <= 8'h00; mag1[2]   <= 8'h00;
            mag2[0]   <= 8'h00;              /* mag2[1] assigned in mag block */    mag2[2]   <= 8'h00;
            mag3[0]   <= 8'h00; mag3[1]   <= 8'h00; // mag3[2] is driven in separate block
        end else if (enable && valid_addr && active_area) begin
            if (!reset_done) begin
                if (init_counter < 3'd2) begin
                    init_counter <= init_counter + 1'b1;
                    cache1[0] <= 8'h00; cache1[1] <= 8'h00; cache1[2] <= 8'h00;
                    cache2[0] <= 8'h00; cache2[1] <= 8'h00; cache2[2] <= 8'h00;
                    cache3[0] <= 8'h00; cache3[1] <= 8'h00; cache3[2] <= 8'h00;
                    mag1[0]   <= 8'h00; mag1[1]   <= 8'h00; mag1[2]   <= 8'h00;
                    mag2[0]   <= 8'h00;              /* mag2[1] assigned in mag block */    mag2[2]   <= 8'h00;
                    mag3[0]   <= 8'h00; mag3[1]   <= 8'h00; // mag3[2] is driven in separate block
                end else begin
                    reset_done <= 1'b1;
                    // shift pixel window
                    cache1[0] <= cache1[1]; cache1[1] <= cache1[2]; cache1[2] <= cache2[1];
                    cache2[0] <= cache2[1]; cache2[1] <= cache2[2]; cache2[2] <= cache3[1];
                    cache3[0] <= cache3[1]; cache3[1] <= cache3[2]; cache3[2] <= pixel_in;
                    // shift mag window (current pixel mag will be filled later in pipeline)
                    mag1[0]   <= mag1[1]; mag1[1]   <= mag1[2]; mag1[2]   <= mag2[1];
                    mag2[0]   <= mag2[1]; mag2[1]   <= mag2[2]; mag2[2]   <= mag3[1];
                    mag3[0]   <= mag3[1]; mag3[1]   <= mag3[2];

                    // mag3[2] will be assigned with current magnitude below
                end
            end else begin
                // steady shifting
                cache1[0] <= cache1[1];
                cache1[1] <= cache1[2];
                cache1[2] <= cache2[1];
                cache2[0] <= cache2[1];
                cache2[1] <= cache2[2];
                cache2[2] <= cache3[1];
                cache3[0] <= cache3[1];
                cache3[1] <= cache3[2];
                cache3[2] <= pixel_in;
                mag1[0]   <= mag1[1];
                mag1[1]   <= mag1[2];
                mag1[2]   <= mag2[1];
                mag2[0]   <= mag2[1];
                /* mag2[1] updated in mag write block */
                mag2[2]   <= mag3[1];
                mag3[0]   <= mag3[1];
                mag3[1]   <= mag3[2];
                // do not assign mag3[2] here; it is assigned in the mag write block
            end
        end
    end

    // Sobel magnitude (11-bit intermediate) and direction (signed)
    reg  [10:0] gx_abs;
    reg  [10:0] gy_abs;
    reg  [10:0] mag;
    wire [10:0] gx_pos = {3'b000,p02} + {2'b00,p12,1'b0} + {3'b000,p22};
    wire [10:0] gx_neg = {3'b000,p00} + {2'b00,p10,1'b0} + {3'b000,p20};
    wire [10:0] gy_pos = {3'b000,p00} + {2'b00,p01,1'b0} + {3'b000,p02};
    wire [10:0] gy_neg = {3'b000,p20} + {2'b00,p21,1'b0} + {3'b000,p22};
    // signed gradients (11-bit signed range fits the differences)
    wire signed [11:0] gx_signed = {1'b0,gx_pos} - {1'b0,gx_neg};
    wire signed [11:0] gy_signed = {1'b0,gy_pos} - {1'b0,gy_neg};
    always @(posedge clk) begin
        if (window_valid) begin
            gx_abs <= (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
            gy_abs <= (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
            mag    <= gx_abs + gy_abs;
        end else begin
            gx_abs <= 11'd0;
            gy_abs <= 11'd0;
            mag    <= 11'd0;
        end
    end

    // Clamp to 8-bit and write into magnitude window tail
    wire [7:0] mag8 = (mag[10:8] != 3'b000) ? 8'hFF : mag[7:0];
    always @(posedge clk) begin
        if (window_valid) begin
            mag3[2] <= mag8;  // place current magnitude at window tail
        end else begin
            mag3[2] <= 8'h00;
        end
    end

    // Approximate Non-Maximum Suppression (single-pass, backward-only neighbors)
    // Quantize gradient direction into 0,45,90,135 deg sectors
    wire [10:0] ax = (gx_signed[11]) ? (~gx_signed[10:0] + 11'd1) : gx_signed[10:0];
    wire [10:0] ay = (gy_signed[11]) ? (~gy_signed[10:0] + 11'd1) : gy_signed[10:0];
    // dir_sel: 2'b00=0deg(h), 01=45deg, 10=90deg(v), 11=135deg
    wire [1:0] dir_sel = (ay <= (ax >> 1))        ? 2'b00 : // closer to horizontal
                         (ax <= (ay >> 1))        ? 2'b10 : // closer to vertical
                         ((gx_signed[11] ^ gy_signed[11]) ? 2'b01 : 2'b11);

    // Use center of magnitude window for symmetric NMS
    wire [7:0] center_mag = mag2[1];
    // pick forward/backward neighbors along quantized gradient
    wire [7:0] nb_a = (dir_sel == 2'b00) ? mag2[0] :            // 0 deg: left
                     (dir_sel == 2'b10) ? mag1[1] :            // 90 deg: up
                     (dir_sel == 2'b01) ? mag1[2] :            // 45 deg: up-right
                                          mag1[0];             // 135 deg: up-left
    wire [7:0] nb_b = (dir_sel == 2'b00) ? mag2[2] :            // 0 deg: right
                     (dir_sel == 2'b10) ? mag3[1] :            // 90 deg: down
                     (dir_sel == 2'b01) ? mag3[0] :            // 45 deg: down-left
                                          mag3[2];             // 135 deg: down-right
    wire       nms_keep  = (center_mag >= nb_a) && (center_mag >= nb_b);
    wire [7:0] nms_mag   = nms_keep ? center_mag : 8'd0;

    // Hysteresis thresholding with 8-neighbor strong-edge promotion (on NMS magnitude)
    // strong if >= high
    // weak if >= low and at least one neighbor strong
    wire is_strong_center = (nms_mag >= threshold_high);
    wire is_weak_center   = (nms_mag >= threshold_low);

    // neighbor strong check (previously latched magnitudes in window)
    wire neigh_strong =
        (mag1[0] >= threshold_high) | (mag1[1] >= threshold_high) | (mag1[2] >= threshold_high) |
        (mag2[0] >= threshold_high) | (mag2[1] >= threshold_high) | (mag2[2] >= threshold_high) |
        (mag3[0] >= threshold_high) | (mag3[1] >= threshold_high);

    always @(posedge clk) begin
        if (window_valid) begin
            if (is_strong_center) begin
                pixel_out <= 8'hFF;
            end else if (is_weak_center && neigh_strong) begin
                pixel_out <= 8'hFF;
            end else begin
                pixel_out <= 8'h00;
            end
            canny_ready <= 1'b1;
        end else begin
            pixel_out   <= 8'h00;
            canny_ready <= 1'b0;
        end
    end

endmodule


