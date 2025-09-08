module ov7670_i2c_config(
    input wire clk,
    input wire reset,
    output reg sioc,
    inout wire siod,
    output reg config_done
);

    // I2C parameters
    parameter CAMERA_ADDR = 8'h42;
    parameter CLK_DIVIDER = 250;  // 100MHz / 250 = 400kHz for I2C
    
    // Configuration registers (RGB565, QVGA 320x240)
    parameter CONFIG_SIZE = 20;
    
    reg [15:0] config_data [0:CONFIG_SIZE-1];
    initial begin
        config_data[0]  = 16'h12_80;  // Reset all registers
        config_data[1]  = 16'h11_00;  // Use external clock
        config_data[2]  = 16'h3A_04;  // Output format control
        config_data[3]  = 16'h12_04;  // RGB mode
        config_data[4]  = 16'h8C_00;  // RGB444/RGB565 selection
        config_data[5]  = 16'h40_C0;  // RGB565 format
        config_data[6]  = 16'h14_1A;  // AGC/AEC control
        config_data[7]  = 16'h4F_B3;  // Color matrix coefficient
        config_data[8]  = 16'h50_B3;  // Color matrix coefficient
        config_data[9]  = 16'h51_00;  // Color matrix coefficient
        config_data[10] = 16'h52_3D;  // Color matrix coefficient
        config_data[11] = 16'h53_A7;  // Color matrix coefficient
        config_data[12] = 16'h54_E4;  // Color matrix coefficient
        config_data[13] = 16'h3D_C3;  // Enable gamma, UV average, color correction
        config_data[14] = 16'h17_11;  // HSTART
        config_data[15] = 16'h18_61;  // HSTOP
        config_data[16] = 16'h19_02;  // VSTART
        config_data[17] = 16'h1A_7A;  // VSTOP
        config_data[18] = 16'h32_80;  // HREF control
        config_data[19] = 16'h03_0A;  // Common control A
    end
    
    // I2C state machine
    reg [4:0] state;
    reg [7:0] clk_count;
    reg [4:0] config_index;
    reg [3:0] bit_count;
    reg [7:0] tx_data;
    reg sda_out;
    reg sda_oe;
    
    assign siod = sda_oe ? sda_out : 1'bz;
    
    parameter IDLE = 5'd0,
              START = 5'd1,
              SEND_ADDR = 5'd2,
              WAIT_ACK1 = 5'd3,
              SEND_REG = 5'd4,
              WAIT_ACK2 = 5'd5,
              SEND_DATA = 5'd6,
              WAIT_ACK3 = 5'd7,
              STOP = 5'd8,
              DELAY = 5'd9,
              DONE = 5'd10;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            sioc <= 1'b1;
            sda_out <= 1'b1;
            sda_oe <= 1'b1;
            clk_count <= 8'd0;
            config_index <= 5'd0;
            bit_count <= 4'd0;
            config_done <= 1'b0;
        end else begin
            // Clock divider for I2C timing
            if (clk_count < CLK_DIVIDER) begin
                clk_count <= clk_count + 1;
            end else begin
                clk_count <= 8'd0;
                
                case (state)
                    IDLE: begin
                        if (config_index < CONFIG_SIZE) begin
                            state <= START;
                            sioc <= 1'b1;
                            sda_out <= 1'b1;
                        end else begin
                            state <= DONE;
                        end
                    end
                    
                    START: begin
                        sda_out <= 1'b0;  // Start condition
                        state <= SEND_ADDR;
                        tx_data <= CAMERA_ADDR;
                        bit_count <= 4'd7;
                    end
                    
                    SEND_ADDR: begin
                        sioc <= ~sioc;
                        if (!sioc) begin  // Falling edge of SCL
                            sda_out <= tx_data[bit_count];
                            if (bit_count == 0) begin
                                state <= WAIT_ACK1;
                                sda_oe <= 1'b0;  // Release SDA for ACK
                            end else begin
                                bit_count <= bit_count - 1;
                            end
                        end
                    end
                    
                    WAIT_ACK1: begin
                        sioc <= ~sioc;
                        if (!sioc) begin
                            state <= SEND_REG;
                            sda_oe <= 1'b1;
                            tx_data <= config_data[config_index][15:8];
                            bit_count <= 4'd7;
                        end
                    end
                    
                    SEND_REG: begin
                        sioc <= ~sioc;
                        if (!sioc) begin
                            sda_out <= tx_data[bit_count];
                            if (bit_count == 0) begin
                                state <= WAIT_ACK2;
                                sda_oe <= 1'b0;
                            end else begin
                                bit_count <= bit_count - 1;
                            end
                        end
                    end
                    
                    WAIT_ACK2: begin
                        sioc <= ~sioc;
                        if (!sioc) begin
                            state <= SEND_DATA;
                            sda_oe <= 1'b1;
                            tx_data <= config_data[config_index][7:0];
                            bit_count <= 4'd7;
                        end
                    end
                    
                    SEND_DATA: begin
                        sioc <= ~sioc;
                        if (!sioc) begin
                            sda_out <= tx_data[bit_count];
                            if (bit_count == 0) begin
                                state <= WAIT_ACK3;
                                sda_oe <= 1'b0;
                            end else begin
                                bit_count <= bit_count - 1;
                            end
                        end
                    end
                    
                    WAIT_ACK3: begin
                        sioc <= ~sioc;
                        if (!sioc) begin
                            state <= STOP;
                            sda_oe <= 1'b1;
                            sda_out <= 1'b0;
                        end
                    end
                    
                    STOP: begin
                        sioc <= 1'b1;
                        sda_out <= 1'b1;  // Stop condition
                        state <= DELAY;
                        clk_count <= 8'd0;
                    end
                    
                    DELAY: begin
                        if (clk_count == 8'd50) begin  // Short delay between configs
                            config_index <= config_index + 1;
                            state <= IDLE;
                        end
                    end
                    
                    DONE: begin
                        config_done <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
