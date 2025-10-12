// ============================================================================
// Module: color_tracker
// Description: Checks if an HSV pixel falls within a specified color range,
//              selectable via an input port.
//
// Inputs:
//   clk:           Clock signal
//   rst_n:       Asynchronous active-low reset
//   valid_in:    Input data valid signal
//   color_select:  Selects the target color (00:Red, 01:Green, 10:Blue)
//   h_in:        Hue component input
//   s_in:        Saturation component input
//   v_in:        Value component input
//
// Outputs:
//   valid_out:   Output data valid signal
//   is_target_out: 1 if the pixel is within the target range, else 0.
//
// Latency: 2 clock cycles
// ============================================================================
module color_tracker # (
    parameter DATA_WIDTH = 8
) (
    input wire clk,
    input wire rst_n,
    input wire valid_in,
    input wire [1:0] color_select, // 00: Red, 01: Green, 10: Blue

    input wire [DATA_WIDTH-1:0] h_in,
    input wire [DATA_WIDTH-1:0] s_in,
    input wire [DATA_WIDTH-1:0] v_in,

    output reg valid_out,
    output reg is_target_out
);

    // --- HSV Thresholds for different colors (8-bit scale) ---
    // Red (wraps around 0)
    localparam RED_H_MIN1 = 8'd0;
    localparam RED_H_MAX1 = 8'd15;   // ~22 deg
    localparam RED_H_MIN2 = 8'd240;  // ~338 deg
    localparam RED_H_MAX2 = 8'd255;
    localparam RED_S_MIN  = 8'd140;  // 더 선명한 빨강 감지 (120 -> 140)
    localparam RED_V_MIN  = 8'd90;   // 더 밝은 빨강만 감지 (70 -> 90)

    // Green
    localparam GREEN_H_MIN = 8'd60;  // ~85 deg
    localparam GREEN_H_MAX = 8'd110; // ~155 deg
    localparam GREEN_S_MIN = 8'd80;
    localparam GREEN_V_MIN = 8'd70;

    // Blue
    localparam BLUE_H_MIN = 8'd150; // ~211 deg
    localparam BLUE_H_MAX = 8'd190; // ~267 deg
    localparam BLUE_S_MIN = 8'd80;
    localparam BLUE_V_MIN = 8'd70;

    // Registers for selected thresholds
    reg [DATA_WIDTH-1:0] h_min1, h_max1, h_min2, h_max2, s_min, v_min;
    reg use_wrap_around; // Flag to handle red's hue wrap-around

    // Pipeline registers
    reg [DATA_WIDTH-1:0] h_in_s1, s_in_s1, v_in_s1;
    reg h_match_s1, s_match_s1, v_match_s1;
    reg valid_in_s1;

    // Stage 0: Select thresholds based on color_select
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Default to Red
            h_min1 <= RED_H_MIN1;
            h_max1 <= RED_H_MAX1;
            h_min2 <= RED_H_MIN2;
            h_max2 <= RED_H_MAX2;
            s_min  <= RED_S_MIN;
            v_min  <= RED_V_MIN;
            use_wrap_around <= 1'b1;
        end else begin
            case (color_select)
                2'b00: begin // Red
                    h_min1 <= RED_H_MIN1;
                    h_max1 <= RED_H_MAX1;
                    h_min2 <= RED_H_MIN2;
                    h_max2 <= RED_H_MAX2;
                    s_min  <= RED_S_MIN;
                    v_min  <= RED_V_MIN;
                    use_wrap_around <= 1'b1;
                end
                2'b01: begin // Green
                    h_min1 <= GREEN_H_MIN;
                    h_max1 <= GREEN_H_MAX;
                    h_min2 <= 0; // Not used
                    h_max2 <= 0; // Not used
                    s_min  <= GREEN_S_MIN;
                    v_min  <= GREEN_V_MIN;
                    use_wrap_around <= 1'b0;
                end
                2'b10: begin // Blue
                    h_min1 <= BLUE_H_MIN;
                    h_max1 <= BLUE_H_MAX;
                    h_min2 <= 0; // Not used
                    h_max2 <= 0; // Not used
                    s_min  <= BLUE_S_MIN;
                    v_min  <= BLUE_V_MIN;
                    use_wrap_around <= 1'b0;
                end
                default: begin // Default to Red
                    h_min1 <= RED_H_MIN1;
                    h_max1 <= RED_H_MAX1;
                    h_min2 <= RED_H_MIN2;
                    h_max2 <= RED_H_MAX2;
                    s_min  <= RED_S_MIN;
                    v_min  <= RED_V_MIN;
                    use_wrap_around <= 1'b1;
                end
            endcase
        end
    end

    // Stage 1: Perform comparison
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_in_s1 <= 1'b0;
            h_match_s1 <= 1'b0;
            s_match_s1 <= 1'b0;
            v_match_s1 <= 1'b0;
            h_in_s1 <= 0;
            s_in_s1 <= 0;
            v_in_s1 <= 0;
        end else begin
            valid_in_s1 <= valid_in;
            h_in_s1 <= h_in;
            s_in_s1 <= s_in;
            v_in_s1 <= v_in;

            if (valid_in) begin
                if (use_wrap_around) begin
                    h_match_s1 <= ((h_in >= h_min1) && (h_in <= h_max1)) || ((h_in >= h_min2) && (h_in <= h_max2));
                end else begin
                    h_match_s1 <= (h_in >= h_min1) && (h_in <= h_max1);
                end
                s_match_s1 <= (s_in >= s_min);
                v_match_s1 <= (v_in >= v_min);
            end else begin
                h_match_s1 <= 1'b0;
                s_match_s1 <= 1'b0;
                v_match_s1 <= 1'b0;
            end
        end
    end

    // Stage 2: Final decision
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            is_target_out <= 1'b0;
        end else begin
            valid_out <= valid_in_s1;
            if (valid_in_s1) begin
                is_target_out <= h_match_s1 && s_match_s1 && v_match_s1;
            end else begin
                is_target_out <= 1'b0;
            end
        end
    end

endmodule