module Address_Generator(
    input rst_i,
    input CLK25,  // 25 MHz clock and activation signal respectively
    input enable,
    input vsync,
    output [16:0] address  // generated address
);

    reg [16:0] val; // intermediate signal

    // Assign output
    assign address = val;

    always @(posedge CLK25) begin
        if (rst_i == 1'b1) begin
            val <= 17'b0;
        end else begin
            if (enable == 1'b1) begin  // if enable = 0, stop address generation
                if (val < 320*240) begin  // if the memory space is completely scanned
                    val <= val + 1;
                end
            end
            if (vsync == 1'b0) begin
                val <= 17'b0;
            end
        end
    end

endmodule
