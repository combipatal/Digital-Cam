// ============================================================================
// Module: rgb_to_hsv
// Description: Pipelined RGB to HSV color space converter.
//
// Parameters:
//   DATA_WIDTH: Bit width of color components (default: 8)
//
// Inputs:
//   clk:         Clock signal
//   rst_n:       Asynchronous active-low reset
//   valid_in:    Input data valid signal
//   r_in:        Red component input
//   g_in:        Green component input
//   b_in:        Blue component input
//
// Outputs:
//   valid_out:   Output data valid signal
//   h_out:       Hue component output (0-255)
//   s_out:       Saturation component output (0-255)
//   v_out:       Value component output (0-255)
//
// Latency: 5 clock cycles
// ============================================================================
module rgb_to_hsv #(
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire rst_n,
    input wire valid_in,
    input wire [DATA_WIDTH-1:0] r_in,
    input wire [DATA_WIDTH-1:0] g_in,
    input wire [DATA_WIDTH-1:0] b_in,

    output reg valid_out,
    output reg [DATA_WIDTH-1:0] h_out,
    output reg [DATA_WIDTH-1:0] s_out,
    output reg [DATA_WIDTH-1:0] v_out
);

    // Pipeline stage registers
    // Stage 0: Input registers
    reg valid_s0;
    reg [DATA_WIDTH-1:0] r_s0, g_s0, b_s0;

    // Stage 1: Min/Max, Value, Delta
    reg valid_s1;
    reg [DATA_WIDTH-1:0] cmax_s1, cmin_s1, delta_s1, v_s1;
    reg [DATA_WIDTH-1:0] r_s1, g_s1, b_s1; // Pass through for Hue calc

    // Stage 2: Saturation
    reg valid_s2;
    reg [DATA_WIDTH-1:0] s_s2, v_s2;
    reg [DATA_WIDTH-1:0] cmax_s2, delta_s2;
    reg [DATA_WIDTH-1:0] r_s2, g_s2, b_s2;

    // Stage 3: Prepare for Hue (H)
    reg valid_s3;
    reg [DATA_WIDTH-1:0] s_s3, v_s3;
    reg [DATA_WIDTH-1:0] delta_s3;
    reg signed [DATA_WIDTH:0] r_m_g_s3, g_m_b_s3, b_m_r_s3; // Signed diffs
    reg cmax_is_r_s3, cmax_is_g_s3;

    // Stage 4: Hue calculation (part 1)
    reg valid_s4;
    reg [DATA_WIDTH-1:0] s_s4, v_s4;
    reg signed [DATA_WIDTH+7:0] h_num; // (diff * 255)
    reg [DATA_WIDTH+2:0] h_den; // (6 * delta)
    reg cmax_is_r_s4, cmax_is_g_s4;

    // Stage 5: Hue calculation (part 2) & Output
    reg valid_s5;
    reg [DATA_WIDTH-1:0] s_s5, v_s5;
    reg signed [DATA_WIDTH:0] h_div_res;
    reg cmax_is_r_s5, cmax_is_g_s5;

    // ============================================================================
    // Pipeline Stage 0: Input Register
    // ============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s0 <= 1'b0;
            r_s0 <= 0;
            g_s0 <= 0;
            b_s0 <= 0;
        end else begin
            valid_s0 <= valid_in;
            if (valid_in) begin
                r_s0 <= r_in;
                g_s0 <= g_in;
                b_s0 <= b_in;
            end
        end
    end

    // ============================================================================
    // Pipeline Stage 1: Find Cmax, Cmin, Delta, and V
    // ============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            cmax_s1 <= 0;
            cmin_s1 <= 0;
            delta_s1 <= 0;
            v_s1 <= 0;
            r_s1 <= 0;
            g_s1 <= 0;
            b_s1 <= 0;
        end else begin
            valid_s1 <= valid_s0;
            if (valid_s0) begin
                // Pass through for next stage
                r_s1 <= r_s0;
                g_s1 <= g_s0;
                b_s1 <= b_s0;

                // Find Cmax
                if (r_s0 >= g_s0 && r_s0 >= b_s0)
                    cmax_s1 <= r_s0;
                else if (g_s0 >= r_s0 && g_s0 >= b_s0)
                    cmax_s1 <= g_s0;
                else
                    cmax_s1 <= b_s0;

                // Find Cmin
                if (r_s0 <= g_s0 && r_s0 <= b_s0)
                    cmin_s1 <= r_s0;
                else if (g_s0 <= r_s0 && g_s0 <= b_s0)
                    cmin_s1 <= g_s0;
                else
                    cmin_s1 <= b_s0;
                
                // Calculate Delta and V
                delta_s1 <= cmax_s1 - cmin_s1;
                v_s1 <= cmax_s1;
            end
        end
    end

    // ============================================================================
    // Pipeline Stage 2: Calculate Saturation (S)
    // ============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s2 <= 1'b0;
            s_s2 <= 0;
            v_s2 <= 0;
            cmax_s2 <= 0;
            delta_s2 <= 0;
            r_s2 <= 0;
            g_s2 <= 0;
            b_s2 <= 0;
        end else begin
            valid_s2 <= valid_s1;
            if (valid_s1) begin
                // Pass through
                v_s2 <= v_s1;
                cmax_s2 <= cmax_s1;
                delta_s2 <= delta_s1;
                r_s2 <= r_s1;
                g_s2 <= g_s1;
                b_s2 <= b_s1;

                // Calculate S = (delta * 255) / Cmax
                if (cmax_s1 == 0) begin
                    s_s2 <= 0;
                end else begin
                    // Use a temporary wider register for multiplication
                    s_s2 <= ({delta_s1, 8'h00} - {delta_s1, 1'b0}) / cmax_s1; // (d*256 - d) / cmax
                end
            end
        end
    end

    // ============================================================================
    // Pipeline Stage 3: Prepare for Hue (H)
    // ============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s3 <= 1'b0;
            s_s3 <= 0;
            v_s3 <= 0;
            delta_s3 <= 0;
            r_m_g_s3 <= 0;
            g_m_b_s3 <= 0;
            b_m_r_s3 <= 0;
            cmax_is_r_s3 <= 0;
            cmax_is_g_s3 <= 0;
        end else begin
            valid_s3 <= valid_s2;
            if (valid_s2) begin
                // Pass through
                s_s3 <= s_s2;
                v_s3 <= v_s2;
                delta_s3 <= delta_s2;

                // Pre-calculate differences
                r_m_g_s3 <= {1'b0, r_s2} - {1'b0, g_s2};
                g_m_b_s3 <= {1'b0, g_s2} - {1'b0, b_s2};
                b_m_r_s3 <= {1'b0, b_s2} - {1'b0, r_s2};

                // Determine which component was max
                cmax_is_r_s3 <= (cmax_s2 == r_s2);
                cmax_is_g_s3 <= (cmax_s2 == g_s2);
            end
        end
    end

    // ============================================================================
    // Pipeline Stage 4: Hue Numerator/Denominator
    // ============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s4 <= 1'b0;
            s_s4 <= 0;
            v_s4 <= 0;
            h_num <= 0;
            h_den <= 0;
            cmax_is_r_s4 <= 0;
            cmax_is_g_s4 <= 0;
        end else begin
            valid_s4 <= valid_s3;
            if (valid_s3) begin
                // Pass through
                s_s4 <= s_s3;
                v_s4 <= v_s3;
                cmax_is_r_s4 <= cmax_is_r_s3;
                cmax_is_g_s4 <= cmax_is_g_s3;

                // Denominator is always 6 * delta
                h_den <= {delta_s3, 2'b0} + {delta_s3, 1'b0}; // delta*4 + delta*2

                // Select numerator based on max component
                if (cmax_is_r_s3) begin // Cmax is R
                    h_num <= g_m_b_s3 * 42; // (255/6) ~ 42.5
                end else if (cmax_is_g_s3) begin // Cmax is G
                    h_num <= b_m_r_s3 * 42;
                end else begin // Cmax is B
                    h_num <= r_m_g_s3 * 42;
                end
            end
        end
    end

    // ============================================================================
    // Pipeline Stage 5: Hue Division and Final Output
    // ============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s5 <= 1'b0;
            s_s5 <= 0;
            v_s5 <= 0;
            h_div_res <= 0;
            cmax_is_r_s5 <= 0;
            cmax_is_g_s5 <= 0;
            valid_out <= 1'b0;
            h_out <= 0;
            s_out <= 0;
            v_out <= 0;
        end else begin
            valid_s5 <= valid_s4;
            valid_out <= valid_s5; // Final output valid signal

            if (valid_s4) begin
                s_s5 <= s_s4;
                v_s5 <= v_s4;
                cmax_is_r_s5 <= cmax_is_r_s4;
                cmax_is_g_s5 <= cmax_is_g_s4;

                if (h_den == 0) begin
                    h_div_res <= 0;
                end else begin
                    h_div_res <= h_num / h_den;
                end
            end

            if (valid_s5) begin
                // Assign S and V outputs
                s_out <= s_s5;
                v_out <= v_s5;

                // Final Hue calculation with offsets
                if (cmax_is_r_s5) begin // Cmax is R
                    h_out <= (h_div_res < 0) ? h_div_res + 255 : h_div_res;
                end else if (cmax_is_g_s5) begin // Cmax is G
                    h_out <= h_div_res + 85; // Add 255/3
                end else begin // Cmax is B
                    h_out <= h_div_res + 170; // Add 2*255/3
                end
            end
        end
    end

endmodule
