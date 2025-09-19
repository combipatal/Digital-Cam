// canny_3x3_gray8.v
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
            mag2[0]   <= 8'h00; /* mag2[1] assigned in mag block */    mag2[2]   <= 8'h00;
            mag3[0]   <= 8'h00; mag3[1]   <= 8'h00; // mag3[2] is driven in separate block
        end else if (enable && valid_addr && active_area) begin
            if (!reset_done) begin
                if (init_counter < 3'd2) begin
                    init_counter <= init_counter + 1'b1;
                end else begin
                    reset_done <= 1'b1;
                end
                // Always shift, even during init phase, after clearing
                cache1[0] <= cache1[1]; cache1[1] <= cache1[2]; cache1[2] <= cache2[1];
                cache2[0] <= cache2[1]; cache2[1] <= cache2[2]; cache2[2] <= cache3[1];
                cache3[0] <= cache3[1]; cache3[1] <= cache3[2]; cache3[2] <= pixel_in;
                
                mag1[0]   <= mag1[1]; mag1[1]   <= mag1[2]; mag1[2]   <= mag2[1];
                mag2[0]   <= mag2[1]; // mag2[1] updated in separate block
                mag2[2]   <= mag3[1];
                mag3[0]   <= mag3[1]; mag3[1]   <= mag3[2]; // mag3[2] updated in separate block
            end else begin
                // steady shifting
                cache1[0] <= cache1[1]; cache1[1] <= cache1[2]; cache1[2] <= cache2[1];
                cache2[0] <= cache2[1]; cache2[1] <= cache2[2]; cache2[2] <= cache3[1];
                cache3[0] <= cache3[1]; cache3[1] <= cache3[2]; cache3[2] <= pixel_in;
                
                mag1[0]   <= mag1[1]; mag1[1]   <= mag1[2]; mag1[2]   <= mag2[1];
                mag2[0]   <= mag2[1]; // mag2[1] is updated in separate block
                mag2[2]   <= mag3[1];
                mag3[0]   <= mag3[1]; mag3[1]   <= mag3[2]; // do not assign mag3[2] here
            end
        end
    end

    // Sobel magnitude (11-bit intermediate)
    reg  [10:0] gx_abs;
    reg  [10:0] gy_abs;
    reg  [10:0] mag;
    wire [10:0] gx_pos = {3'b000,p02} + {2'b00,p12,1'b0} + {3'b000,p22};
    wire [10:0] gx_neg = {3'b000,p00} + {2'b00,p10,1'b0} + {3'b000,p20};
    wire [10:0] gy_pos = {3'b000,p00} + {2'b00,p01,1'b0} + {3'b000,p02};
    wire [10:0] gy_neg = {3'b000,p20} + {2'b00,p21,1'b0} + {3'b000,p22};
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
            mag3[2] <= mag8; // place current magnitude at window tail
            mag2[1] <= mag3[0]; // update center of magnitude window, remove feedback loop
        end else begin
            mag3[2] <= 8'h00;
            mag2[1] <= 8'h00;
        end
    end

    // Approximate Non-Maximum Suppression (NMS)
    wire [7:0] center_mag = mag2[1];
    wire [1:0] dir_sel; // Simplified direction selection
    // Simplified NMS check (compare with immediate neighbors along gradient direction)
    assign dir_sel = (gy_abs > gx_abs) ? ((gx_abs < (gy_abs>>1)) ? 2'b10 : 2'b11) : ((gy_abs < (gx_abs>>1)) ? 2'b00 : 2'b01);
    
    wire [7:0] nb_a = (dir_sel == 2'b00) ? mag2[0] : (dir_sel == 2'b10) ? mag1[1] : (dir_sel == 2'b01) ? mag1[2] : mag1[0];
    wire [7:0] nb_b = (dir_sel == 2'b00) ? mag2[2] : (dir_sel == 2'b10) ? mag3[1] : (dir_sel == 2'b01) ? mag3[0] : mag3[2];
    wire       nms_keep  = (center_mag >= nb_a) && (center_mag >= nb_b);
    wire [7:0] nms_mag   = nms_keep ? center_mag : 8'd0;

    // Hysteresis thresholding with 8-neighbor strong-edge promotion
    wire is_strong_center = (nms_mag >= threshold_high);
    wire is_weak_center   = (nms_mag >= threshold_low);

    wire neigh_strong =
        (mag1[0] >= threshold_high) | (mag1[1] >= threshold_high) | (mag1[2] >= threshold_high) |
        (mag2[0] >= threshold_high) | /* center */                  (mag2[2] >= threshold_high) |
        (mag3[0] >= threshold_high) | (mag3[1] >= threshold_high) | (mag3[2] >= threshold_high);

    // 수정: Hysteresis 결과를 최종 출력으로 연결
    always @(posedge clk) begin
        if (window_valid) begin
            // 강한 엣지이거나, 약한 엣지이면서 주변에 강한 엣지가 있는 경우에만 엣지로 판단
            if (is_strong_center || (is_weak_center && neigh_strong)) begin
                pixel_out <= 8'hFF; // 엣지는 흰색
            end else begin
                pixel_out <= 8'h00; // 엣지가 아니면 검은색
            end
            canny_ready <= 1'b1;
        end else begin
            pixel_out   <= 8'h00;
            canny_ready <= 1'b0;
        end
    end

endmodule