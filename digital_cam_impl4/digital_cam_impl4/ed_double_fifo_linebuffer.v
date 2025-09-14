module DoubleFiFOLineBuffer #(
    parameter DATA_WIDTH = 8,
    parameter NO_OF_COLS = 320
)(
    input clk,
    input fsync,
    input rsync,
    input [DATA_WIDTH-1:0] pdata_in,
    output [DATA_WIDTH-1:0] pdata_out1,
    output [DATA_WIDTH-1:0] pdata_out2,
    output [DATA_WIDTH-1:0] pdata_out3
);

    wire [DATA_WIDTH-1:0] intermediate_out;

    FIFOLineBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NO_OF_COLS(NO_OF_COLS)
    ) LineBuffer1 (
        .clk(clk),
        .fsync(fsync),
        .rsync(rsync),
        .pdata_in(pdata_in),
        .pdata_out(pdata_out2)
    );

    FIFOLineBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NO_OF_COLS(NO_OF_COLS)
    ) LineBuffer2 (
        .clk(clk),
        .fsync(fsync),
        .rsync(rsync),
        .pdata_in(pdata_out2),
        .pdata_out(pdata_out3)
    );

    assign pdata_out1 = pdata_in;

endmodule
