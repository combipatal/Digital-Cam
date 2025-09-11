// cfg_rom.v (수정 완료)
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
            case(i_addr)
                0:  o_data <= 16'h12_80; // reset     
                1:  o_data <= 16'hFF_F0; // delay 1ms
                2:  o_data <= 16'h12_08; // QVGA
                3:  o_data <= 16'h11_00; // CLKRC, PLL 1x
                4:  o_data <= 16'h0C_04; // COM3
                5:  o_data <= 16'h3E_19; // COM14
                6:  o_data <= 16'h04_00; // COM1
                7:  o_data <= 16'h8c_02; // RGB444
                8:  o_data <= 16'h40_d0; // COM15, RGB444, full output
                9:  o_data <= 16'h15_40; // [추가] COM10, HSYNC 활성화
                10: o_data <= 16'h3a_04; // TSLB
                11: o_data <= 16'h14_18; // COM9
                12: o_data <= 16'h4F_B3; // MTX1
                13: o_data <= 16'h50_B3; // MTX2
                14: o_data <= 16'h51_00; // MTX3
                15: o_data <= 16'h52_3d; // MTX4
                16: o_data <= 16'h53_A7; // MTX5
                17: o_data <= 16'h54_E4; // MTX6
                18: o_data <= 16'h58_9E; // MTXS
                19: o_data <= 16'h3D_C0; // COM13
                20: o_data <= 16'h17_13; // HSTART
                21: o_data <= 16'h18_01; // HSTOP
                22: o_data <= 16'h32_b6; // HREF
                23: o_data <= 16'h19_02; // VSTART
                24: o_data <= 16'h1A_7a; // VSTOP
                25: o_data <= 16'h03_0A; // VREF
                26: o_data <= 16'h0F_41; // COM6
                27: o_data <= 16'h1E_00; // MVFP
                28: o_data <= 16'h33_0B; // CHLF
                29: o_data <= 16'h3C_78; // COM12
                30: o_data <= 16'h69_00; // GFIX
                31: o_data <= 16'h74_00; // REG74
                32: o_data <= 16'hB0_84; // RSVD
                33: o_data <= 16'hB1_0c; // ABLC1
                34: o_data <= 16'hB2_0e; // RSVD
                35: o_data <= 16'hB3_80; // THL_ST
                36: o_data <= 16'h70_3a; // SCALING_XSC
                37: o_data <= 16'h71_35; // SCALING_YSC
                38: o_data <= 16'h72_11; // SCALING_DCWCTR
                39: o_data <= 16'h73_f1; // SCALING_PCLK_DIV
                40: o_data <= 16'ha2_02; // SCALING_PCLK_DELAY
                41: o_data <= 16'h7a_20; // SLOP
                42: o_data <= 16'h7b_10; // GAM1
                43: o_data <= 16'h7c_1e; // GAM2
                44: o_data <= 16'h7d_35; // GAM3
                45: o_data <= 16'h7e_5a; // GAM4
                46: o_data <= 16'h7f_69; // GAM5
                47: o_data <= 16'h80_76; // GAM6
                48: o_data <= 16'h81_80; // GAM7
                49: o_data <= 16'h82_88; // GAM8
                50: o_data <= 16'h83_8f; // GAM9
                51: o_data <= 16'h84_96; // GAM10
                52: o_data <= 16'h85_a3; // GAM11
                53: o_data <= 16'h86_af; // GAM12
                54: o_data <= 16'h87_c4; // GAM13
                55: o_data <= 16'h88_d7; // GAM14
                56: o_data <= 16'h89_e8; // GAM15
                57: o_data <= 16'h13_e0; // COM8, disable AGC/AEC
                58: o_data <= 16'h00_00; // GAIN
                59: o_data <= 16'h10_00; // AEC
                60: o_data <= 16'h0d_40; // COM4
                61: o_data <= 16'h14_18; // COM9
                62: o_data <= 16'ha5_05; // BD50MAX
                63: o_data <= 16'hab_07; // DB60MAX
                64: o_data <= 16'h24_95; // AGC upper limit
                65: o_data <= 16'h25_33; // AGC lower limit
                66: o_data <= 16'h26_e3; // AGC/AEC fast mode
                67: o_data <= 16'h9f_78; // HAECC1
                68: o_data <= 16'ha0_68; // HAECC2
                69: o_data <= 16'ha1_03; // HAECC3
                70: o_data <= 16'ha6_d8; // HAECC4
                71: o_data <= 16'ha7_d8; // HAECC5
                72: o_data <= 16'ha8_f0; // HAECC6
                73: o_data <= 16'ha9_90; // HAECC7
                74: o_data <= 16'haa_94; // HAECC7
                75: o_data <= 16'h13_a7; // COM8, enable AGC/AEC
                76: o_data <= 16'h1E_23; // mirror image
                77: o_data <= 16'h69_06;
                default: o_data <= 16'hFF_FF;  // end of ROM
            endcase
        end
    end

endmodule