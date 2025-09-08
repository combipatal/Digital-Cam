// module: cfg_rom.v
//
// Contains camera configuration. 1 cycle read delay.
// Register values from: 
// -> https://github.com/westonb/OV7670-Verilog/blob/master/src/OV7670_config_rom.v
//     - edited for RGB444 instead of RGB565
//
// Key takeaway is that OV7670 is configured to RGB444 output
// data frame format:  1)  { x, x, x, x, R[0], R[1], R[2], R[3] }
//                     2)  {G[0], G[1], G[2], G[3], B[0], B[1], B[2], B[3]}
`default_nettype none
//
module cfg_rom 
    (
    input  wire        i_clk,
    input  wire        i_rstn,

    input  wire [7:0]  i_addr,
    output reg  [15:0] o_data
    );

    always@(posedge i_clk) begin
        if(!i_rstn) o_data <= 0;
        else begin
            // in cfg_rom.v, replace the entire case statement with this one.

            case(i_addr)
					 // System Control
					 0: o_data <= 16'h12_80; // COM7: Software Reset
					 1: o_data <= 16'hFF_F0; // Special: 1ms Delay
					 
					 // Clock Control
					 2: o_data <= 16'h11_01; // CLKRC: Internal clock pre-scaler
					 
					 // Format and Resolution (VGA, RGB)
					 3: o_data <= 16'h12_06; // COM7: VGA, RGB 출력
					 4: o_data <= 16'h3a_04; // TSLB: UV 설정 (RGB 모드에 맞게 조정 필요)
					 5: o_data <= 16'h8c_02; // RGB444: Enable RGB444
					 6: o_data <= 16'h40_f0; // COM15: Full Range, RGB444 output (수정: D0 → F0)
					 7: o_data <= 16'h0c_00; // COM3: (default)
                8: o_data <= 16'h3e_00; // COM14: (default)
                9: o_data <= 16'h70_3a; // SCALING_XSC: (default)
                10: o_data <= 16'h71_35; // SCALING_YSC: (default)
                11: o_data <= 16'h72_11; // SCALING_DCWCTR: (default)
                12: o_data <= 16'h73_f0; // SCALING_PCLK_DIV: (default)
                13: o_data <= 16'ha2_02; // SCALING_PCLK_DELAY: (default)

                // Frame Timing and Sizing
                14: o_data <= 16'h17_13; // HSTART
                15: o_data <= 16'h18_01; // HSTOP
                16: o_data <= 16'h32_b6; // HREF
                17: o_data <= 16'h19_02; // VSTART
                18: o_data <= 16'h1a_7a; // VSTOP
                19: o_data <= 16'h03_0a; // VREF

                // Color Matrix for RGB
                20: o_data <= 16'h4f_80; // MTX1
                21: o_data <= 16'h50_80; // MTX2
                22: o_data <= 16'h51_00; // MTX3
                23: o_data <= 16'h52_22; // MTX4
                24: o_data <= 16'h53_5e; // MTX5
                25: o_data <= 16'h54_80; // MTX6
                26: o_data <= 16'h58_9e; // MTXS

                // General Configuration
                27: o_data <= 16'h0e_61; // COM5
                28: o_data <= 16'h13_e7; // COM8: Enable AGC, AEC, AWB
                29: o_data <= 16'h1e_31; // MVFP: Mirror/Flip settings
                30: o_data <= 16'h3d_c3; // COM13
                
                // End of configuration
                31: o_data <= 16'hFF_FF; // Special: End of ROM
                default: o_data <= 16'hFF_FF;
            endcase
        end
    end


endmodule