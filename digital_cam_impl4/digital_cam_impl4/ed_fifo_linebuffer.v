module FIFOLineBuffer #(
    parameter DATA_WIDTH = 8,
    parameter NO_OF_COLS = 320
)(
    input clk,
    input fsync,
    input rsync,
    input [DATA_WIDTH-1:0] pdata_in,
    output reg [DATA_WIDTH-1:0] pdata_out
);

    reg clk2;
    reg [8:0] ColsCounter = 9'b0; // Since 320 < 512, 9 bits are sufficient

    // Memory array to store line buffer data
    reg [DATA_WIDTH-1:0] ram_array [0:NO_OF_COLS-1];

    // Generate inverted clock for writing
    always @* begin
        clk2 = ~clk;
    end

    // Reading from the memory
    always @(posedge clk) begin
        if (fsync == 1'b1) begin
            if (rsync == 1'b1) begin
                pdata_out <= ram_array[ColsCounter];
            end
        end
    end

    // Writing into the memory
    always @(posedge clk2) begin
        if (fsync == 1'b1) begin
            if (rsync == 1'b1) begin
                ram_array[ColsCounter] <= pdata_in;
                if (ColsCounter < NO_OF_COLS-1) begin
                    ColsCounter <= ColsCounter + 1;
                end else begin
                    ColsCounter <= 9'b0;
                end
            end else begin
                ColsCounter <= 9'b0;
            end
        end
    end

endmodule
