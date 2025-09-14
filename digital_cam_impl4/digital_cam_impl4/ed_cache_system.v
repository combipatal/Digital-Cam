module CacheSystem #(
    parameter DATA_WIDTH = 8,
    parameter WINDOW_SIZE = 3,
    parameter ROW_BITS = 8, // 9 for 640x480
    parameter COL_BITS = 9, // 10 for 640x480
    parameter NO_OF_ROWS = 240,
    parameter NO_OF_COLS = 320
)(
    input clk,
    input fsync_in,
    input rsync_in,
    input [DATA_WIDTH-1:0] pdata_in,
    output fsync_out,
    output rsync_out,
    output [DATA_WIDTH-1:0] pdata_out1,
    output [DATA_WIDTH-1:0] pdata_out2,
    output [DATA_WIDTH-1:0] pdata_out3,
    output [DATA_WIDTH-1:0] pdata_out4,
    output [DATA_WIDTH-1:0] pdata_out5,
    output [DATA_WIDTH-1:0] pdata_out6,
    output [DATA_WIDTH-1:0] pdata_out7,
    output [DATA_WIDTH-1:0] pdata_out8,
    output [DATA_WIDTH-1:0] pdata_out9
);

    wire [ROW_BITS-1:0] RowsCounterOut;
    wire [COL_BITS-1:0] ColsCounterOut;
    wire [DATA_WIDTH-1:0] dout1, dout2, dout3;
    wire fsync_temp, rsync_temp;

    // Pixel elements caches
    // |--------------------------------|
    // | z9-z6-z3 | z8-z5-z2 | z7-z4-z1 |
    // |--------------------------------|
    // 23       16|15       8|7         0
    reg [WINDOW_SIZE*DATA_WIDTH-1:0] cache1;
    reg [WINDOW_SIZE*DATA_WIDTH-1:0] cache2;
    reg [WINDOW_SIZE*DATA_WIDTH-1:0] cache3;

    DoubleFiFOLineBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NO_OF_COLS(NO_OF_COLS)
    ) DoubleLineBuffer (
        .clk(clk),
        .fsync(fsync_in),
        .rsync(rsync_in),
        .pdata_in(pdata_in),
        .pdata_out1(dout1),
        .pdata_out2(dout2),
        .pdata_out3(dout3)
    );

    SyncSignalsDelayer #(
        .ROW_BITS(ROW_BITS)
    ) Delayer (
        .clk(clk),
        .fsync_in(fsync_in),
        .rsync_in(rsync_in),
        .fsync_out(fsync_temp),
        .rsync_out(rsync_temp)
    );

    // Note: these counters work with sync signals that are delayed!
    Counter #(
        .n(ROW_BITS)
    ) RowsCounter (
        .clk(rsync_temp),
        .en(fsync_temp),
        .reset(fsync_temp),
        .output_count(RowsCounterOut)
    );

    // Number of pixels in a row/line is counted by ColsCounter that is reset by
    // rsync_temp while it stays on 0; once rsync_temp goes high 1, counter starts;
    Counter #(
        .n(COL_BITS)
    ) ColsCounter (
        .clk(clk),
        .en(rsync_temp),
        .reset(rsync_temp),
        .output_count(ColsCounterOut)
    );

    assign fsync_out = fsync_temp;
    assign rsync_out = rsync_temp;

    // Shifting process
    always @(posedge clk) begin
        // The pixel in the middle part is copied into the low part
        cache1[DATA_WIDTH-1:0] <= cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1:(WINDOW_SIZE-2)*DATA_WIDTH];
        cache2[DATA_WIDTH-1:0] <= cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1:(WINDOW_SIZE-2)*DATA_WIDTH];
        cache3[DATA_WIDTH-1:0] <= cache3[(WINDOW_SIZE-1)*DATA_WIDTH-1:(WINDOW_SIZE-2)*DATA_WIDTH];

        // The pixel in the high part is copied into the middle part
        cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1:(WINDOW_SIZE-2)*DATA_WIDTH] <= cache1[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
        cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1:(WINDOW_SIZE-2)*DATA_WIDTH] <= cache2[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
        cache3[(WINDOW_SIZE-1)*DATA_WIDTH-1:(WINDOW_SIZE-2)*DATA_WIDTH] <= cache3[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];

        // The output of the ram is put in the high part of the variable
        cache1[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH] <= dout1;
        cache2[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH] <= dout2;
        cache3[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH] <= dout3;
    end

    // Emitting process
    reg [DATA_WIDTH-1:0] pdata_out1_reg, pdata_out2_reg, pdata_out3_reg, pdata_out4_reg, pdata_out5_reg;
    reg [DATA_WIDTH-1:0] pdata_out6_reg, pdata_out7_reg, pdata_out8_reg, pdata_out9_reg;

    always @* begin
        if (fsync_temp == 1'b1) begin
            case ({RowsCounterOut, ColsCounterOut})
                // Corner cases and edge cases for 3x3 window
                // Top-left corner
                {8'd0, 9'd0}: begin
                    pdata_out1_reg = {DATA_WIDTH{1'b0}};
                    pdata_out2_reg = {DATA_WIDTH{1'b0}};
                    pdata_out3_reg = {DATA_WIDTH{1'b0}};
                    pdata_out4_reg = {DATA_WIDTH{1'b0}};
                    pdata_out5_reg = cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1:(WINDOW_SIZE-2)*DATA_WIDTH];
                    pdata_out6_reg = cache2[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                    pdata_out7_reg = {DATA_WIDTH{1'b0}};
                    pdata_out8_reg = cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1:(WINDOW_SIZE-2)*DATA_WIDTH];
                    pdata_out9_reg = cache1[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                end

                // Top row, middle columns
                {8'd0, 9'b000000001}: begin  // ColsCounterOut > 0 and < 319
                    pdata_out1_reg = {DATA_WIDTH{1'b0}};
                    pdata_out2_reg = {DATA_WIDTH{1'b0}};
                    pdata_out3_reg = {DATA_WIDTH{1'b0}};
                    pdata_out4_reg = cache2[DATA_WIDTH-1:0];
                    pdata_out5_reg = cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out6_reg = cache2[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                    pdata_out7_reg = cache1[DATA_WIDTH-1:0];
                    pdata_out8_reg = cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out9_reg = cache1[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                end

                // Top-right corner
                {8'd0, 9'd319}: begin
                    pdata_out1_reg = {DATA_WIDTH{1'b0}};
                    pdata_out2_reg = {DATA_WIDTH{1'b0}};
                    pdata_out3_reg = {DATA_WIDTH{1'b0}};
                    pdata_out4_reg = cache2[DATA_WIDTH-1:0];
                    pdata_out5_reg = cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out6_reg = {DATA_WIDTH{1'b0}};
                    pdata_out7_reg = cache1[DATA_WIDTH-1:0];
                    pdata_out8_reg = cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out9_reg = {DATA_WIDTH{1'b0}};
                end

                // Left column, middle rows
                {8'b00000001, 9'd0}: begin  // RowsCounterOut > 0 and < 239
                    pdata_out1_reg = {DATA_WIDTH{1'b0}};
                    pdata_out2_reg = cache3[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out3_reg = cache3[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                    pdata_out4_reg = {DATA_WIDTH{1'b0}};
                    pdata_out5_reg = cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out6_reg = cache2[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                    pdata_out7_reg = {DATA_WIDTH{1'b0}};
                    pdata_out8_reg = cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out9_reg = cache1[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                end

                // Middle pixels
                default: begin
                    pdata_out1_reg = cache3[DATA_WIDTH-1:0];
                    pdata_out2_reg = cache3[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out3_reg = cache3[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                    pdata_out4_reg = cache2[DATA_WIDTH-1:0];
                    pdata_out5_reg = cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out6_reg = cache2[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                    pdata_out7_reg = cache1[DATA_WIDTH-1:0];
                    pdata_out8_reg = cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1:DATA_WIDTH];
                    pdata_out9_reg = cache1[WINDOW_SIZE*DATA_WIDTH-1:(WINDOW_SIZE-1)*DATA_WIDTH];
                end
            endcase
        end
    end

    assign pdata_out1 = pdata_out1_reg;
    assign pdata_out2 = pdata_out2_reg;
    assign pdata_out3 = pdata_out3_reg;
    assign pdata_out4 = pdata_out4_reg;
    assign pdata_out5 = pdata_out5_reg;
    assign pdata_out6 = pdata_out6_reg;
    assign pdata_out7 = pdata_out7_reg;
    assign pdata_out8 = pdata_out8_reg;
    assign pdata_out9 = pdata_out9_reg;

endmodule
