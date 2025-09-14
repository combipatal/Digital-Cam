// This entity delays vsync (frame) and hsync (rows) signals that
// are used for VGA driving; vsync is delayed with 320 + 2
// and hsync is delayed with 2; this effectively accounts for
// the latency that we need to wait from the moment we start reading
// pixels of a frame till the time Sobel filter is applied and gives
// the first computed pixel of the edge detected image;

module SyncSignalsDelayer #(
    parameter ROW_BITS = 8
)(
    input clk,
    input fsync_in,
    input rsync_in,
    output reg fsync_out,
    output reg rsync_out
);

    wire [ROW_BITS-1:0] rowsDelayCounterRising;
    reg [ROW_BITS-1:0] rowsDelayCounterFalling = {ROW_BITS{1'b0}};
    reg rsync2, rsync1, fsync_temp;

    // Step 1 - delay of two clock cycles
    always @(posedge clk) begin
        rsync2 <= rsync1;
        rsync1 <= rsync_in;
    end

    assign rsync_out = rsync2;
    assign fsync_out = fsync_temp;

    // Step 2
    Counter #(
        .n(ROW_BITS)
    ) RowsCounterComp (
        .clk(rsync2),
        .en(fsync_in),
        .reset(fsync_in),
        .output_count(rowsDelayCounterRising)
    );

    // Steps 3 and 5
    always @* begin
        // rows2 = 2
        if (rowsDelayCounterRising == 8'd2) begin
            fsync_temp = 1'b1;
        end else if (rowsDelayCounterFalling == 8'd0) begin
            fsync_temp = 1'b0;
        end
    end

    // Step 4
    always @(negedge rsync2) begin
        if (fsync_temp == 1'b1) begin
            // 239
            if (rowsDelayCounterFalling < 8'd239) begin
                rowsDelayCounterFalling <= rowsDelayCounterFalling + 1;
            end else begin
                rowsDelayCounterFalling <= 8'd0;
            end
        end else begin
            rowsDelayCounterFalling <= 8'd0;
        end
    end

endmodule
