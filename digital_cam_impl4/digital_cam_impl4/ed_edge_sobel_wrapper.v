// Note: this implementation of the Sobel filter assumes that we work
// with a "gray scale camera" and so each pixel is transmitted just as 8 bits;
// the gray value of each pixel is represented using 8 bits, so a total of 256
// different gray values are possible;
// we apply it to the gray image that was taken, stored inside sdram, then
// transformed into gray format and placed into buffer 2;

module edge_sobel_wrapper #(
    parameter DATA_WIDTH = 8
)(
    input clk,
    input fsync_in,
    input rsync_in,
    input [DATA_WIDTH-1:0] pdata_in,
    output fsync_out,
    output rsync_out,
    output [DATA_WIDTH-1:0] pdata_out
);

    wire [DATA_WIDTH-1:0] pdata_int1, pdata_int2, pdata_int3, pdata_int4, pdata_int5;
    wire [DATA_WIDTH-1:0] pdata_int6, pdata_int7, pdata_int8, pdata_int9;
    wire fsynch_int, rsynch_int;

    CacheSystem #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_SIZE(3),
        .ROW_BITS(8),
        .COL_BITS(9),
        .NO_OF_ROWS(240),
        .NO_OF_COLS(320)
    ) CacheSystem_inst (
        .clk(clk),
        .fsync_in(fsync_in),
        .rsync_in(rsync_in),
        .pdata_in(pdata_in),
        .fsync_out(fsynch_int),
        .rsync_out(rsynch_int),
        .pdata_out1(pdata_int1),
        .pdata_out2(pdata_int2),
        .pdata_out3(pdata_int3),
        .pdata_out4(pdata_int4),
        .pdata_out5(pdata_int5),
        .pdata_out6(pdata_int6),
        .pdata_out7(pdata_int7),
        .pdata_out8(pdata_int8),
        .pdata_out9(pdata_int9)
    );

    edge_sobel #(
        .DATA_WIDTH(DATA_WIDTH)
    ) krnl (
        .pclk_i(clk),
        .fsync_i(fsynch_int),
        .rsync_i(rsynch_int),
        .pData1(pdata_int1),
        .pData2(pdata_int2),
        .pData3(pdata_int3),
        .pData4(pdata_int4),
        .pData5(pdata_int5),
        .pData6(pdata_int6),
        .pData7(pdata_int7),
        .pData8(pdata_int8),
        .pData9(pdata_int9),
        .fsync_o(fsync_out),
        .rsync_o(rsync_out),
        .pdata_o(pdata_out)
    );

endmodule
