
 // Megafunction wizard: %RAM: 2-PORT%
// This is a generated memory block from Quartus MegaWizard
// In a real implementation, this would be replaced with the actual IP core

module my_frame_buffer_15to0(
    input [11:0] data,
    input [15:0] rdaddress,
    input rdclock,
    input [15:0] wraddress,
    input wrclock,
    input wren,
    output reg [11:0] q
);

    // Simple dual-port RAM model
    // In practice, this would be implemented using FPGA block RAM
    reg [11:0] ram [0:65535];

    // Write operation
    always @(posedge wrclock) begin
        if (wren) begin
            ram[wraddress] <= data;
        end
    end

    // Read operation
    always @(posedge rdclock) begin
        q <= ram[rdaddress];
    end

endmodule
