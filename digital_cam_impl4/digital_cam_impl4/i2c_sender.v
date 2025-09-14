// This is used to send commands to the OV7670 camera module
// over an I2C-like interface

module i2c_sender(
    input clk,
    output reg siod,
    output reg sioc,
    output reg taken,
    input send,
    input [7:0] id,
    input [7:0] reg_addr,
    input [7:0] value
);

    reg [7:0] divider = 8'h01; // this value gives a 254 cycle pause before the initial frame is sent
    reg [31:0] busy_sr = 32'b0;
    reg [31:0] data_sr = 32'hFFFFFFFF;

    // SIOD control logic
    always @* begin
        if (busy_sr[11:10] == 2'b10 ||
            busy_sr[20:19] == 2'b10 ||
            busy_sr[29:28] == 2'b10) begin
            siod = 1'bZ;
        end else begin
            siod = data_sr[31];
        end
    end

    always @(posedge clk) begin
        taken <= 1'b0;
        if (busy_sr[31] == 1'b0) begin
            sioc <= 1'b1;
            if (send == 1'b1) begin
                if (divider == 8'h00) begin
                    data_sr <= {8'h10, id, 1'b0, reg_addr, 1'b0, value, 1'b0, 2'b01};
                    busy_sr <= {8'h11, 9'h1FF, 9'h1FF, 9'h1FF, 2'h3};
                    taken <= 1'b1;
                end else begin
                    divider <= divider + 1; // this only happens on powerup
                end
            end
        end else begin
            // State machine for I2C protocol
            case ({busy_sr[31:29], busy_sr[2:0]})
                // Start sequence
                6'b111111: begin // start seq #1
                    case (divider[7:6])
                        2'b00: sioc <= 1'b1;
                        2'b01: sioc <= 1'b1;
                        2'b10: sioc <= 1'b1;
                        default: sioc <= 1'b1;
                    endcase
                end

                6'b111110: begin // start seq #2
                    case (divider[7:6])
                        2'b00: sioc <= 1'b1;
                        2'b01: sioc <= 1'b1;
                        2'b10: sioc <= 1'b1;
                        default: sioc <= 1'b1;
                    endcase
                end

                6'b111100: begin // start seq #3
                    case (divider[7:6])
                        2'b00: sioc <= 1'b0;
                        2'b01: sioc <= 1'b0;
                        2'b10: sioc <= 1'b0;
                        default: sioc <= 1'b0;
                    endcase
                end

                // End sequence
                6'b110000: begin // end seq #1
                    case (divider[7:6])
                        2'b00: sioc <= 1'b0;
                        2'b01: sioc <= 1'b1;
                        2'b10: sioc <= 1'b1;
                        default: sioc <= 1'b1;
                    endcase
                end

                6'b100000: begin // end seq #2
                    case (divider[7:6])
                        2'b00: sioc <= 1'b1;
                        2'b01: sioc <= 1'b1;
                        2'b10: sioc <= 1'b1;
                        default: sioc <= 1'b1;
                    endcase
                end

                // Idle
                6'b000000: begin // Idle
                    case (divider[7:6])
                        2'b00: sioc <= 1'b1;
                        2'b01: sioc <= 1'b1;
                        2'b10: sioc <= 1'b1;
                        default: sioc <= 1'b1;
                    endcase
                end

                // Data transmission
                default: begin
                    case (divider[7:6])
                        2'b00: sioc <= 1'b0;
                        2'b01: sioc <= 1'b1;
                        2'b10: sioc <= 1'b1;
                        default: sioc <= 1'b0;
                    endcase
                end
            endcase

            if (divider == 8'hFF) begin
                busy_sr <= {busy_sr[30:0], 1'b0};
                data_sr <= {data_sr[30:0], 1'b1};
                divider <= 8'h00;
            end else begin
                divider <= divider + 1;
            end
        end
    end

endmodule
