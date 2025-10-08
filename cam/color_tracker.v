
// ============================================================================
// Module: color_tracker
// Description: Checks if an HSV pixel falls within a specified color range.
//
// Parameters:
//   DATA_WIDTH: Bit width of color components (default: 8)
//   H_MIN, H_MAX, H_MIN2, H_MAX2: Hue thresholds
//   S_MIN, V_MIN: Saturation and Value minimum thresholds
//
// Inputs:
//   clk:         Clock signal
//   rst_n:       Asynchronous active-low reset
//   valid_in:    Input data valid signal
//   h_in:        Hue component input
//   s_in:        Saturation component input
//   v_in:        Value component input
//
// Outputs:
//   valid_out:   Output data valid signal
//   is_target_out: 1 if the pixel is within the target range, else 0.
//
// Latency: 1 clock cycle
// ============================================================================
module color_tracker #(
    parameter DATA_WIDTH = 8,
    // Default thresholds for RED
    parameter H_MIN = 8'd0,
    parameter H_MAX = 8'd6,      // 8 degrees
    parameter H_MIN2 = 8'd249,    // 352 degrees
    parameter H_MAX2 = 8'd255,
    parameter S_MIN = 8'd151,    // S > 150
    parameter V_MIN = 8'd50,
    parameter V_MAX = 8'd200
)(
    input wire clk,
    input wire rst_n,
    input wire valid_in,
    input wire [DATA_WIDTH-1:0] h_in,
    input wire [DATA_WIDTH-1:0] s_in,
    input wire [DATA_WIDTH-1:0] v_in,

    output reg valid_out,
    output reg is_target_out
);

    reg h_match, s_match, v_match;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            is_target_out <= 1'b0;
            h_match <= 1'b0;
            s_match <= 1'b0;
            v_match <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                // Check Hue range (handles wrap-around for red)
                h_match <= ((h_in >= H_MIN) && (h_in <= H_MAX)) || ((h_in >= H_MIN2) && (h_in <= H_MAX2));
                
                // Check Saturation and Value range
                s_match <= (s_in >= S_MIN);
                v_match <= (v_in >= V_MIN) && (v_in <= V_MAX);

                // Final decision
                is_target_out <= h_match && s_match && v_match;
            end else begin
                is_target_out <= 1'b0;
            end
        end
    end

endmodule
